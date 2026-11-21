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

  Future<(FakeDevices, AppState)> start(WidgetTester t, int seed) async {
    await loadFonts();
    t.view.physicalSize = const Size(1080, 2280); // a phone like the A80
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final progress = await Progress.load();
    final t0 = t.binding.clock.now();
    final dev = FakeDevices(
      IoLog(() => t.binding.clock.now().difference(t0)),
      child: () => Child.silent,
    );
    final d = dev.io;
    final app = AppState(
      FakeRecognizer(() => ''),
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
    for (final g in ['hear', 'read', 'speak', 'think']) {
      transcript.writeln('# Group $g');
      await t.tap(find.byKey(ValueKey('group-$g')));
      await settle(t);
      await shot(t, 'group-$g');
      await t.pageBack();
      await settle(t);
    }
    said(dev, 0);
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
}
