// The memory games: fair rounds in every language, and whole rounds
// played with taps on the fake clock.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/memory/memory_rules.dart';
import 'package:phoneme_party/memory/memory_screen.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:phoneme_party/quiz/quiz_rules.dart' show soundsSimilar;
import 'package:phoneme_party/think/think_rules.dart' show bareEmoji;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const langs = ['de-DE', 'en-GB', 'fr-FR', 'it-IT', 'es-ES'];

PhraseBook load(String lang) {
  final raw = File('assets/phrases/$lang.json').readAsStringSync();
  return PhraseBook(lang, [
    for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
      Phrase.fromJson(j),
  ]);
}

void main() {
  late PhonemeComparer comparer;
  final books = {for (final l in langs) l: load(l)};

  setUpAll(() {
    comparer = PhonemeComparer.fromJson(
      File('assets/panphon/panphon_features.json').readAsStringSync(),
    );
  });

  group('rounds', () {
    for (final lang in langs) {
      for (final game in MemoryGame.values) {
        test('$lang ${game.name}: fair, from the first three worlds', () {
          final book = books[lang]!;
          final pool = [for (var w = 0; w < 3; w++) ...book.world(w)];
          for (var seed = 0; seed < 50; seed++) {
            final round = makeMemoryRound(game, pool, math.Random(seed));
            expect(round, hasLength(memorySizes[game]!.length));
            MemoryQuestion? last;
            for (final (i, q) in round.indexed) {
              expect(q.shown, hasLength(memorySizes[game]![i]));
              expect(q.options, hasLength(memoryOptions(game)));
              final pics = {...q.shown, ...q.options}.map((p) => p.emoji);
              // no picture twice
              expect(
                pics.map(bareEmoji).toSet(),
                hasLength(pics.length),
                reason: '$q',
              );
              for (final a in q.answers) {
                expect(q.options, contains(a));
              }
              if (game == MemoryGame.missing) {
                expect(q.shown, contains(q.missing));
                // the other options were not shown
                expect(q.options.where(q.shown.contains), [
                  q.missing,
                ], reason: '$q');
              } else {
                expect(q.answers, q.shown);
              }
              // nothing of the question before: it would be remembered
              if (last != null) {
                final before = {...last.shown, ...last.options};
                expect(
                  {...q.shown, ...q.options}.where(before.contains),
                  isEmpty,
                  reason: '$last / $q',
                );
              }
              last = q;
            }
          }
        });
      }
    }

    for (final lang in langs) {
      test('$lang: no look-alikes, and no sound-alikes to hear', () {
        final book = books[lang]!;
        final pool = [for (var w = 0; w < 3; w++) ...book.world(w)];
        bool similar(Phrase a, Phrase b) => soundsSimilar(comparer, lang, a, b);
        for (final game in MemoryGame.values) {
          for (var seed = 0; seed < 40; seed++) {
            final round = makeMemoryRound(
              game,
              pool,
              math.Random(seed),
              similar: game == MemoryGame.hear || game == MemoryGame.say
                  ? similar
                  : null,
            );
            expect(round, hasLength(memorySizes[game]!.length));
            for (final q in round) {
              final all = {...q.shown, ...q.options}.toList();
              final families = [for (final p in all) ?lookAlikeFamily(p.emoji)];
              expect(
                families.toSet(),
                hasLength(families.length),
                reason: '$q',
              );
              if (game != MemoryGame.hear && game != MemoryGame.say) continue;
              for (final a in all) {
                for (final b in all) {
                  if (a != b) {
                    expect(similar(a, b), isFalse, reason: '$a / $b in $q');
                  }
                }
              }
            }
          }
        }
      });
    }

    test('the number pictures are one family', () {
      expect(lookAlikeFamily('3️⃣'), 'number');
      expect(lookAlikeFamily('🔟'), 'number');
      expect(lookAlikeFamily('🚕'), lookAlikeFamily('🚗'));
      expect(lookAlikeFamily('🐮'), isNull);
    });

    test('a small pool: as many questions as it allows', () {
      final pool = books['de-DE']!.phrases.take(5).toList();
      expect(makeMemoryRound(MemoryGame.look, pool, math.Random(1)), isEmpty);
      expect(
        makeMemoryRound(MemoryGame.missing, pool, math.Random(1)),
        hasLength(2), // three and four pictures need five and six
      );
    });
  });

  group('screen', () {
    Phrase w(String text) =>
        books['de-DE']!.phrases.firstWhere((p) => p.text == text);

    Future<(FakeDevices, Progress)> play(
      WidgetTester t,
      MemoryGame game,
      List<MemoryQuestion> round, {
      List<String> answers = const [],
      Child Function()? child,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final progress = await Progress.load();
      final t0 = t.binding.clock.now();
      final dev = FakeDevices(
        IoLog(() => t.binding.clock.now().difference(t0)),
        child: child,
      );
      var heard = 0;
      final app = AppState(
        // what the child says, one after the other
        FakeRecognizer(() => heard < answers.length ? answers[heard++] : ''),
        comparer,
        progress,
        books['de-DE']!,
        io: dev.io,
      );
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(navigatorKey: nav, home: const Scaffold()),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              MemoryScreen(app: app, game: game, round: round, intro: false),
        ),
      );
      await t.pump();
      await t.pump();
      return (dev, progress);
    }

    Future<void> wait(WidgetTester t, [int ms = 3000]) async {
      for (var e = 0; e < ms; e += 50) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> close(WidgetTester t, IoLog log, {bool mic = false}) async {
      expect(log.problems, isEmpty, reason: '$log');
      if (!mic) expect(log.started('mic'), isEmpty);
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await t.tap(find.text('Great'));
      }
      await t.pumpWidget(const SizedBox());
      await wait(t, 7000);
    }

    Finder option(int i) => find.byKey(ValueKey('memory-option-$i'));
    bool visible(String key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty;

    // shown: Hund, Buch; options: Buch, Kuh, Hund, Mond, Sonne, Fisch
    MemoryQuestion two() => MemoryQuestion(
      [w('Hund'), w('Buch')],
      [w('Buch'), w('Kuh'), w('Hund'), w('Mond'), w('Sonne'), w('Fisch')],
    );

    /// Waits until the pictures can be tapped; checks what was on screen
    /// meanwhile.
    Future<List<String>> untilPick(WidgetTester t) async {
      final phases = <String>[];
      for (var e = 0; e < 30000 && !visible('memory-option-0'); e += 50) {
        await t.pump(const Duration(milliseconds: 50));
        for (final k in [
          'memory-wait',
          'memory-shown-0',
          'memory-hearing',
          'memory-hide',
        ]) {
          if (visible(k) && (phases.isEmpty || phases.last != k)) {
            phases.add(k);
          }
        }
      }
      return phases;
    }

    /// Waits until the places of the pictures to name are there.
    Future<void> untilSlots(WidgetTester t) async {
      for (var e = 0; e < 30000 && !visible('memory-slot-0'); e += 50) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const ValueKey('memory-slot-0')), findsOneWidget);
    }

    testWidgets('remember the pictures: look, they hide for five seconds, '
        'find them, three stars', (t) async {
      final (dev, progress) = await play(t, MemoryGame.look, [two()]);
      final start = t.binding.clock.now();
      DateTime? hidden;
      DateTime? back;
      while (!visible('memory-option-0')) {
        await t.pump(const Duration(milliseconds: 50));
        if (visible('memory-hide')) hidden ??= t.binding.clock.now();
        // while hidden: nothing to see of the pictures
        if (visible('memory-hide')) {
          expect(find.byKey(const ValueKey('memory-shown-0')), findsNothing);
        }
        expect(
          t.binding.clock.now().difference(start),
          lessThan(const Duration(seconds: 30)),
        );
      }
      back = t.binding.clock.now();
      expect(back.difference(hidden!).inMilliseconds, closeTo(5000, 100));
      await wait(t, 2000);
      expect(dev.log.started('tts'), [
        'Schau genau!',
        'Welche Bilder waren es?',
      ]);
      await t.tap(option(2)); // Hund
      await wait(t, 1500);
      expect(dev.log.started('tts').last, 'Hund');
      expect(find.byType(AlertDialog), findsNothing);
      await t.tap(option(0)); // Buch
      await wait(t, 8000);
      expect(dev.log.started('tts'), contains(startsWith('Buch! ')));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(progress.thinkBest('memory-look', 'de-DE'), 3);
      await close(t, dev.log);
    });

    testWidgets('remember the pictures: two wrong taps show the right ones '
        'and go on, no star', (t) async {
      final (dev, progress) = await play(t, MemoryGame.look, [two()]);
      await untilPick(t);
      await wait(t, 2000);
      await t.tap(option(2)); // Hund, right
      await wait(t, 1000);
      await t.tap(option(1)); // Kuh, wrong
      await wait(t, 1500);
      expect(dev.log.started('tts').last, 'Kuh');
      // a wrong picture cannot be tapped twice
      await t.tap(option(1));
      await wait(t, 1500);
      expect(dev.log.started('tts').where((s) => s == 'Kuh'), hasLength(1));
      await t.tap(option(3)); // Mond, wrong: enough
      await wait(t, 1500);
      expect(dev.log.started('tts'), contains('Buch.'));
      await wait(t, 6000);
      expect(find.text('0 / 1'), findsOneWidget);
      expect(progress.thinkBest('memory-look', 'de-DE'), 0);
      await close(t, dev.log);
    });

    testWidgets('remember the words: said one by one, no pictures until the '
        'wait is over', (t) async {
      final (dev, _) = await play(t, MemoryGame.hear, [two()]);
      final phases = await untilPick(t);
      expect(phases, ['memory-wait', 'memory-hearing', 'memory-hide']);
      await wait(t, 2500);
      expect(dev.log.started('tts'), [
        'Hör genau zu!',
        'Hund',
        'Buch',
        'Welche Wörter hast du gehört?',
      ]);
      await t.tap(option(0));
      await t.tap(option(2));
      await wait(t, 8000);
      expect(find.text('1 / 1'), findsOneWidget);
      await close(t, dev.log);
    });

    testWidgets('what is missing: the gap, then the missing one fills it', (
      t,
    ) async {
      final q = MemoryQuestion(
        [w('Hund'), w('Buch'), w('Kuh')],
        [w('Mond'), w('Buch'), w('Sonne')],
        missing: w('Buch'),
      );
      final (dev, progress) = await play(t, MemoryGame.missing, [q]);
      final phases = await untilPick(t);
      expect(phases, ['memory-wait', 'memory-shown-0', 'memory-hide']);
      expect(find.byKey(const ValueKey('memory-gap')), findsOneWidget);
      expect(find.byKey(const ValueKey('memory-left-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('memory-left-1')), findsNothing);
      await wait(t, 2000);
      expect(dev.log.started('tts').last, 'Welches Bild fehlt?');
      // 🔊: the question once more
      await t.tap(find.byKey(const ValueKey('memory-repeat')));
      await wait(t, 2000);
      expect(dev.log.started('tts').last, 'Welches Bild fehlt?');
      await t.tap(option(1));
      await wait(t, 8000);
      expect(progress.thinkBest('memory-missing', 'de-DE'), 3);
      await close(t, dev.log);
    });

    testWidgets('paused while the pictures hide: the question from the '
        'start, taps only afterwards', (t) async {
      final (dev, _) = await play(t, MemoryGame.look, [two()]);
      while (!visible('memory-hide')) {
        await t.pump(const Duration(milliseconds: 50));
      }
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await wait(t, 8000);
      expect(find.byKey(const ValueKey('memory-option-0')), findsNothing);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final phases = await untilPick(t);
      expect(phases, ['memory-wait', 'memory-shown-0', 'memory-hide']);
      expect(
        dev.log.started('tts').where((s) => s == 'Schau genau!'),
        hasLength(2),
      );
      await close(t, dev.log);
    });

    testWidgets('the intro first, then the cue only from the second '
        'question', (t) async {
      SharedPreferences.setMockInitialValues({});
      final progress = await Progress.load();
      final t0 = t.binding.clock.now();
      final dev = FakeDevices(
        IoLog(() => t.binding.clock.now().difference(t0)),
      );
      final app = AppState(
        FakeRecognizer(() => ''),
        comparer,
        progress,
        books['de-DE']!,
        io: dev.io,
      );
      await t.pumpWidget(
        MaterialApp(
          home: MemoryScreen(
            app: app,
            game: MemoryGame.look,
            round: [two(), two()],
          ),
        ),
      );
      while (!visible('memory-option-0')) {
        await t.pump(const Duration(milliseconds: 50));
      }
      await wait(t, 2000);
      expect(dev.log.started('tts').first, startsWith('Schau dir die Bilder'));
      expect(dev.log.started('tts'), isNot(contains('Schau genau!')));
      await t.tap(option(0));
      await t.tap(option(2));
      await wait(t, 6000);
      expect(dev.log.started('tts'), contains('Schau genau!'));
      await t.pumpWidget(const SizedBox());
      await wait(t, 7000);
    });

    testWidgets('what did you see: the child names both, they come back, '
        'three stars', (t) async {
      final (dev, progress) = await play(
        t,
        MemoryGame.say,
        [two()],
        answers: [w('Buch').ipa, w('Hund').ipa],
      );
      await untilSlots(t);
      await wait(t, 12000);
      expect(dev.log.started('tts').take(4).toList(), [
        'Schau genau!',
        'Was hast du gesehen? Sag es mir!',
        'Buch! Und was noch?',
        startsWith('Hund! '),
      ]);
      expect(dev.log.started('mic'), hasLength(2));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(progress.thinkBest('memory-say', 'de-DE'), 3);
      await close(t, dev.log, mic: true);
    });

    testWidgets('what did you see: a word that was not there, then both: '
        'no star', (t) async {
      final (dev, progress) = await play(
        t,
        MemoryGame.say,
        [two()],
        answers: [w('Kuh').ipa, w('Hund').ipa, w('Buch').ipa],
      );
      await untilSlots(t);
      await wait(t, 15000);
      expect(dev.log.started('tts'), contains('Das war nicht dabei.'));
      expect(find.text('0 / 1'), findsOneWidget);
      expect(progress.thinkBest('memory-say', 'de-DE'), 0);
      await close(t, dev.log, mic: true);
    });

    testWidgets('what did you see: nothing heard, the mic waits for a tap', (
      t,
    ) async {
      final (dev, _) = await play(t, MemoryGame.say, [
        two(),
      ], child: () => Child.silent);
      await untilSlots(t);
      await wait(t, 15000);
      expect(dev.log.started('mic'), hasLength(1));
      await t.tap(find.byKey(const ValueKey('memory-mic')));
      await wait(t, 15000);
      expect(dev.log.started('mic'), hasLength(2));
      await close(t, dev.log, mic: true);
    });

    testWidgets('what did you see: paused while listening, the mic stays '
        'closed until tapped', (t) async {
      final (dev, _) = await play(
        t,
        MemoryGame.say,
        [two()],
        answers: [w('Buch').ipa, w('Hund').ipa],
      );
      await untilSlots(t);
      while (dev.log.started('mic').isEmpty) {
        await t.pump(const Duration(milliseconds: 50));
      }
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await wait(t, 3000);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await wait(t, 8000);
      expect(dev.log.started('mic'), hasLength(1));
      await t.tap(find.byKey(const ValueKey('memory-mic')));
      await wait(t, 15000);
      expect(find.byType(AlertDialog), findsOneWidget);
      await close(t, dev.log, mic: true);
    });
  });
}
