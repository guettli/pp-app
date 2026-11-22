// A child plays: not a test of the rules (test/ does that) but a way to
// look at the app as a child would. Renders real screenshots (Roboto,
// Material icons, the bundled emoji images) and writes what the phone
// says, step by step, to build/play/:
//
//   dagger call -m ci play export --path build/play
//
// The child taps the pictures one after the other until one is right,
// like a child that guesses. Only with PLAY=1 (the Play function sets
// it): a plain `flutter test` skips it.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/game/game_io.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:phoneme_party/quiz/facts.dart';
import 'package:phoneme_party/listen/listen_screen.dart';
import 'package:phoneme_party/memory/memory_rules.dart';
import 'package:phoneme_party/memory/memory_screen.dart';
import 'package:phoneme_party/quiz/quiz_screen.dart';
import 'package:phoneme_party/read/read_aloud_screen.dart';
import 'package:phoneme_party/voice/voice_screen.dart';
import 'package:phoneme_party/spell/spell_screen.dart';
import 'package:phoneme_party/think/think_screen.dart';
import 'package:phoneme_party/ui/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

final out = Directory('build/play');
final shotKey = GlobalKey();
var shots = 0;
final transcript = StringBuffer();

Future<void> loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  final dir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final file = File('$dir/$f');
      if (file.existsSync()) {
        l.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      }
    }
    await l.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Future<void> settle(WidgetTester t, [int ms = 600]) async {
  // real time for the images to load and decode, fake time for the app
  for (var i = 0; i < 3; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pump(Duration(milliseconds: ms ~/ 3));
  }
}

Future<void> shot(WidgetTester t, String name) async {
  await settle(t, 100);
  final boundary =
      shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final png = await t.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final file = File(
    '${out.path}/${(++shots).toString().padLeft(3, '0')}-$name.png',
  );
  file.writeAsBytesSync(png!);
  transcript.writeln('  [screenshot ${file.uri.pathSegments.last}]');
}

void main() {
  if (Platform.environment['PLAY'] != '1') return;
  late PhonemeComparer comparer;
  late Facts facts;
  late PhraseBook book;
  setUpAll(() async {
    out.createSync(recursive: true);
    comparer = PhonemeComparer.fromJson(
      File('assets/panphon/panphon_features.json').readAsStringSync(),
    );
    facts = Facts.parse(File(Facts.asset).readAsStringSync());
    final raw = File('assets/phrases/de-DE.json').readAsStringSync();
    book = PhraseBook('de-DE', [
      for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        Phrase.fromJson(j),
    ]);
  });

  tearDownAll(() {
    File('${out.path}/transcript.txt').writeAsStringSync('$transcript');
  });

  Future<(FakeDevices, AppState)> start(
    WidgetTester t,
    int seed, {
    bool speaks = false,
    Map<String, Object> prefs = const {},
  }) async {
    await loadFonts();
    t.view.physicalSize = const Size(1080, 2280); // a phone like the A80
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    final progress = await Progress.load();
    final t0 = t.binding.clock.now();
    final dev = FakeDevices(
      IoLog(() => t.binding.clock.now().difference(t0)),
      child: () => speaks ? Child.speaks : Child.silent,
    );
    // a speaking child says the word the phone said last; every third
    // time it mumbles something else
    var tries = 0;
    String answer() {
      final words = {for (final p in book.phrases) p.text: p};
      final said = dev.log.started('tts');
      tries++;
      // a written word (read aloud): read it, every third time mumbled
      final written = find.byKey(const ValueKey('read-word')).evaluate();
      if (written.isNotEmpty) {
        final texts = written
            .map((e) => e.widget)
            .whereType<Text>()
            .map((w) => w.data)
            .whereType<String>();
        final w = [for (final s in texts) ?words[s]];
        if (w.isNotEmpty) {
          transcript.writeln(
            tries % 3 == 0
                ? '  🗣️ (mumbles)'
                : '  🗣️ "${w.first.text}" (reads)',
          );
          return tries % 3 == 0 ? 'ma' : w.first.ipa;
        }
      }
      // a word alone (the worlds): say it after the phone, every third
      // time mumbled
      final last = said.isEmpty ? '' : said.last;
      if (words[last] case final p?) {
        transcript.writeln(
          tries % 3 == 0 ? '  🗣️ (mumbles)' : '  🗣️ "${p.text}"',
        );
        return tries % 3 == 0 ? 'ma' : p.ipa;
      }
      // a question with the answers in it (the quiz): guess one of them
      final named = [
        // the last question only (it ends with the answers and a ?)
        for (final s in said.reversed.where((s) => s.contains('?')).take(1))
          for (final p in book.phrases)
            if (RegExp(
              '(^|[ ,?!.])${RegExp.escape(p.text)}([ ,?!.]|\$)',
            ).hasMatch(s))
              p,
      ];
      if (named.isEmpty) {
        transcript.writeln('  🗣️ (says nothing)');
        return '';
      }
      final p = named[math.Random(tries).nextInt(named.length)];
      transcript.writeln('  🗣️ "${p.text}" (guessing)');
      return p.ipa;
    }

    final d = dev.io;
    final app = AppState(
      FakeRecognizer(answer),
      comparer,
      progress,
      book,
      io: GameIo(
        mic: d.mic,
        speaker: d.speaker,
        replayPlayer: d.replayPlayer,
        soundPlayer: d.soundPlayer,
        random: () => math.Random(seed),
        listensWhileSpeaking: d.listensWhileSpeaking,
      ),
      facts: facts,
    );
    return (dev, app);
  }

  Future<void> show(WidgetTester t, Widget home) async {
    await t.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto'),
          home: home,
        ),
      ),
    );
  }

  /// What the phone said since [from], one line each.
  int said(FakeDevices dev, int from) {
    final all = dev.log.started('tts');
    for (final s in all.skip(from)) {
      transcript.writeln('  🔊 "$s"');
    }
    return all.length;
  }

  /// A game with pictures to tap ([prefix]-0, [prefix]-1, ...): the child
  /// taps one after the other until the phone says "Word! ..." (right).
  Future<void> tapGame(
    WidgetTester t,
    FakeDevices dev,
    String name,
    String prefix, {
    int questions = 8,
  }) async {
    var n = 0;
    await settle(t, 9000);
    n = said(dev, n);
    await shot(t, '$name-q1');
    for (var q = 0; q < questions; q++) {
      final count = find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                RegExp(
                  '^$prefix-\\d+\$',
                ).hasMatch((w.key! as ValueKey<String>).value),
          )
          .evaluate()
          .length;
      if (count == 0) break;
      var right = false;
      for (var o = 0; o < count && !right; o++) {
        transcript.writeln('  👆 $prefix-$o');
        final before = dev.log.started('tts').length;
        await t.tap(find.byKey(ValueKey('$prefix-$o')), warnIfMissed: false);
        await settle(t, 900);
        right = dev.log
            .started('tts')
            .skip(before)
            .any((s) => s.contains('! '));
        if (q == 0) await shot(t, '$name-q1-tap$o');
        await settle(t, 6000);
        n = said(dev, n);
      }
      if (find.byType(AlertDialog).evaluate().isNotEmpty) break;
      if (q < 3) await shot(t, '$name-q${q + 2}');
    }
    await settle(t, 3000);
    n = said(dev, n);
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await shot(t, '$name-end');
    }
    await t.pumpWidget(const SizedBox());
    await settle(t, 3000);
  }

  testWidgets('home and the groups', (t) async {
    final (dev, app) = await start(t, 1);
    transcript.writeln('# Home');
    await show(t, HomeScreen(app: app));
    await shot(t, 'home');
    for (final g in ['hear', 'read', 'speak', 'think', 'memory']) {
      transcript.writeln('# Group $g');
      await t.ensureVisible(find.byKey(ValueKey('group-$g')));
      await settle(t);
      await t.tap(find.byKey(ValueKey('group-$g')));
      await settle(t);
      await shot(t, 'group-$g');
      await t.pageBack();
      await settle(t);
    }
    said(dev, 0);
  });

  testWidgets('home after some rounds', (t) async {
    final (_, app) = await start(
      t,
      2,
      prefs: {'needs|de-DE': 3, 'riddle|de-DE': 2, 'listen|de-DE': 1},
    );
    transcript.writeln('# Home after some rounds');
    await show(t, HomeScreen(app: app));
    await shot(t, 'home-stars');
    await t.tap(find.byKey(const ValueKey('group-think')));
    await settle(t);
    await shot(t, 'group-think-stars');
  });

  testWidgets('listen closely', (t) async {
    final (dev, app) = await start(t, 3);
    transcript.writeln('# Listen closely');
    await show(t, ListenScreen(app: app));
    await tapGame(t, dev, 'listen', 'listen-option');
  });

  testWidgets('word to picture', (t) async {
    final (dev, app) = await start(t, 4);
    transcript.writeln('# Word to picture');
    await show(t, ListenScreen(app: app, reading: true));
    await tapGame(t, dev, 'readpick', 'listen-option');
  });

  testWidgets('letters', (t) async {
    final (dev, app) = await start(t, 5);
    transcript.writeln('# Letters');
    await show(t, SpellScreen(app: app));
    var n = 0;
    await settle(t, 9000);
    n = said(dev, n);
    await shot(t, 'spell-w1');
    // the child tries the tiles from left to right, again and again
    for (var word = 0; word < 6; word++) {
      final before = dev.log.started('tts').length;
      for (var sweep = 0; sweep < 12; sweep++) {
        final tiles = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              RegExp(
                r'^spell-tile-\d+$',
              ).hasMatch((w.key! as ValueKey<String>).value),
        );
        final count = tiles.evaluate().length;
        if (count == 0) break;
        for (var i = 0; i < count; i++) {
          await t.tap(
            find.byKey(ValueKey('spell-tile-$i')),
            warnIfMissed: false,
          );
          await settle(t, 300);
        }
        if (word == 0 && sweep == 0) await shot(t, 'spell-w1-sweep');
        if (dev.log.started('tts').skip(before).any((s) => s.contains('! '))) {
          break;
        }
      }
      transcript.writeln('  👆 tiles left to right');
      await settle(t, 6000);
      n = said(dev, n);
      if (find.byType(AlertDialog).evaluate().isNotEmpty) break;
      if (word < 2) await shot(t, 'spell-w${word + 2}');
    }
    await settle(t, 3000);
    said(dev, n);
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await shot(t, 'spell-end');
    }
    await t.pumpWidget(const SizedBox());
    await settle(t, 3000);
  });

  testWidgets('world 1', (t) async {
    final (dev, app) = await start(t, 6, speaks: true);
    transcript.writeln('# World 1');
    await show(t, HomeScreen(app: app));
    await settle(t);
    // the first world tile: the child taps it
    await t.tap(find.text('0/24'));
    await settle(t, 3000);
    var n = said(dev, 0);
    await shot(t, 'world-start');
    for (var step = 0; step < 14; step++) {
      await settle(t, 5000);
      n = said(dev, n);
      if (step < 6) await shot(t, 'world-step${step + 1}');
      if (find.byType(AlertDialog).evaluate().isNotEmpty) break;
    }
    await settle(t, 4000);
    said(dev, n);
    await shot(t, 'world-end');
    await t.pumpWidget(const SizedBox());
    await settle(t, 3000);
  });

  for (final sounds in [false, true]) {
    testWidgets(sounds ? 'sound detective' : 'quiz', (t) async {
      final name = sounds ? 'sounds' : 'quiz';
      final (dev, app) = await start(t, sounds ? 9 : 8, speaks: true);
      transcript.writeln('# ${sounds ? 'Sound detective' : 'Quiz'}');
      await show(t, QuizScreen(app: app, sounds: sounds));
      var n = 0;
      for (var step = 0; step < 16; step++) {
        await settle(t, 5000);
        n = said(dev, n);
        if (step < 4) await shot(t, '$name-step${step + 1}');
        if (find.byType(AlertDialog).evaluate().isNotEmpty) break;
      }
      await settle(t, 3000);
      said(dev, n);
      await shot(t, '$name-end');
      await t.pumpWidget(const SizedBox());
      await settle(t, 3000);
    });
  }

  for (final game in VoiceGame.values) {
    testWidgets('voice: ${game.name}', (t) async {
      final (dev, app) = await start(t, 10, speaks: true);
      transcript.writeln('# Voice game: ${game.name}');
      await show(t, VoiceGameScreen(app: app, game: game));
      var n = 0;
      for (var step = 0; step < 8; step++) {
        await settle(t, 5000);
        n = said(dev, n);
        if (step < 4) await shot(t, 'voice-${game.name}-step${step + 1}');
      }
      await t.pumpWidget(const SizedBox());
      await settle(t, 3000);
    });
  }

  testWidgets('read aloud', (t) async {
    final (dev, app) = await start(t, 11, speaks: true);
    transcript.writeln('# Read aloud');
    await show(t, ReadAloudScreen(app: app));
    var n = 0;
    for (var step = 0; step < 12; step++) {
      await settle(t, 5000);
      n = said(dev, n);
      if (step < 4) await shot(t, 'readaloud-step${step + 1}');
      if (find.byType(AlertDialog).evaluate().isNotEmpty) break;
    }
    await settle(t, 3000);
    said(dev, n);
    await shot(t, 'readaloud-end');
    await t.pumpWidget(const SizedBox());
    await settle(t, 3000);
  });

  for (final game in ThinkGame.values) {
    testWidgets('think: ${game.name}', (t) async {
      final (dev, app) = await start(t, game.index + 7);
      transcript.writeln('# Thinking game: ${game.name}');
      await show(t, ThinkScreen(app: app, game: game));
      var n = 0;
      // the intro, then the first question
      await settle(t, 9000);
      n = said(dev, n);
      await shot(t, '${game.name}-q1');
      for (var q = 0; q < 6; q++) {
        final options = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('think-option-'),
        );
        final count = options.evaluate().length;
        var right = false;
        for (var o = 0; o < count && !right; o++) {
          transcript.writeln('  👆 option $o');
          final before = dev.log.started('tts').length;
          await t.tap(find.byKey(ValueKey('think-option-$o')));
          await settle(t, 900);
          final now = dev.log.started('tts');
          // the right picture: "Word! ..." (a wrong one: just the word)
          right = now.skip(before).any((s) => s.contains('! '));
          if (q == 0) await shot(t, '${game.name}-q1-tap$o');
          await settle(t, 6000);
          n = said(dev, n);
        }
        if (find.byType(AlertDialog).evaluate().isNotEmpty) break;
        if (q < 5) await shot(t, '${game.name}-q${q + 2}');
      }
      await settle(t, 3000);
      n = said(dev, n);
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await shot(t, '${game.name}-end');
      }
      await t.pumpWidget(const SizedBox());
      await settle(t, 3000);
    });
  }

  for (final game in MemoryGame.values) {
    testWidgets('memory: ${game.name}', (t) async {
      final (dev, app) = await start(t, game.index + 11);
      transcript.writeln('# Memory game: ${game.name}');
      await show(t, MemoryScreen(app: app, game: game));
      bool seen(String k) => find.byKey(ValueKey(k)).evaluate().isNotEmpty;
      var n = 0;
      for (var q = 0; q < 5; q++) {
        final shots = <String>{};
        // look (or listen), wait while hidden, then the pictures
        for (var e = 0; e < 40000 && !seen('memory-option-0'); e += 100) {
          await t.pump(const Duration(milliseconds: 100));
          for (final k in ['memory-shown-0', 'memory-hearing', 'memory-hide']) {
            if (q < 2 && seen(k) && shots.add(k)) {
              await shot(t, '${game.name}-q${q + 1}-$k');
            }
          }
        }
        await settle(t, 2500);
        n = said(dev, n);
        if (q < 2) await shot(t, '${game.name}-q${q + 1}-pick');
        // a child who remembers some: taps from the first picture on
        final before = dev.log.started('tts').length;
        for (var o = 0; o < memoryOptions(game); o++) {
          if (!seen('memory-option-$o')) break;
          transcript.writeln('  👆 memory-option-$o');
          await t.tap(
            find.byKey(ValueKey('memory-option-$o')),
            warnIfMissed: false,
          );
          await settle(t, 800);
          if (dev.log
              .started('tts')
              .skip(before)
              .any((s) => s.contains('!') || s.endsWith('.'))) {
            break;
          }
        }
        if (q < 2) await shot(t, '${game.name}-q${q + 1}-result');
        await settle(t, 4000);
        n = said(dev, n);
        if (find.byType(AlertDialog).evaluate().isNotEmpty) break;
      }
      await settle(t, 3000);
      n = said(dev, n);
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await shot(t, '${game.name}-end');
      }
      await t.pumpWidget(const SizedBox());
      await settle(t, 6000);
    });
  }
}
