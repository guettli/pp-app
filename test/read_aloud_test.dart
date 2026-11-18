// Read aloud: the rounds, and whole rounds with the fake microphone and
// recogniser on the fake clock.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:phoneme_party/read/read_aloud_screen.dart';
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
  final books = <String, PhraseBook>{};
  setUpAll(() {
    comparer = PhonemeComparer.fromJson(
      File('assets/panphon/panphon_features.json').readAsStringSync(),
    );
    for (final l in langs) {
      books[l] = load(l);
    }
  });

  group('rounds', () {
    for (final lang in langs) {
      test('$lang: six short words, short ones first', () {
        final book = books[lang]!;
        final pool = [for (var w = 0; w < 3; w++) ...book.world(w)];
        for (var seed = 0; seed < 10; seed++) {
          final round = makeReadRound(pool, math.Random(seed));
          expect(round, hasLength(6));
          expect(round.toSet(), hasLength(6));
          for (var i = 1; i < round.length; i++) {
            expect(
              round[i].text.length,
              greaterThanOrEqualTo(round[i - 1].text.length),
            );
          }
          expect(round.every((p) => p.text.length <= 12), isTrue);
        }
      });
    }

    test('round stars: the average', () {
      expect(readRoundStars([3, 3, 3]), 3);
      expect(readRoundStars([3, 2, 2]), 2);
      expect(readRoundStars([0, 0, 1]), 0);
      expect(readRoundStars([]), 0);
    });
  });

  group('screen', () {
    Phrase w(String text) =>
        books['de-DE']!.phrases.firstWhere((p) => p.text == text);
    String ipa(String t) => w(t).ipa.replaceAll('/', '');

    Future<(FakeDevices, Progress)> play(
      WidgetTester t,
      List<String> answers, {
      List<Child>? child,
      void Function(FakeDevices)? prepare,
      bool failRecognizer = false,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final progress = await Progress.load();
      final t0 = t.binding.clock.now();
      final log = IoLog(() => t.binding.clock.now().difference(t0));
      var c = 0;
      final dev = FakeDevices(
        log,
        child: () => child == null
            ? Child.speaks
            : child[(c++).clamp(0, child.length - 1)],
      );
      prepare?.call(dev);
      var n = 0;
      final app = AppState(
        FakeRecognizer(() {
          if (failRecognizer) throw StateError('model gone');
          return answers[(n++).clamp(0, answers.length - 1)];
        }, log: log),
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
              ReadAloudScreen(app: app, round: [w('Ei'), w('Bett')]),
        ),
      );
      await t.pump();
      await t.pump();
      return (dev, progress);
    }

    Future<void> until(
      WidgetTester t,
      bool Function() done,
      IoLog log, {
      Duration limit = const Duration(seconds: 90),
    }) async {
      const step = Duration(milliseconds: 50);
      for (var e = Duration.zero; e < limit; e += step) {
        if (done()) return;
        await t.pump(step);
      }
      fail('timed out\n$log');
    }

    Future<void> wait(WidgetTester t, [int ms = 3000]) async {
      for (var e = 0; e < ms; e += 50) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> close(WidgetTester t, IoLog log) async {
      expect(log.soundsWhileRecording(), isEmpty, reason: '$log');
      expect(log.problems, isEmpty, reason: '$log');
      await wait(t, 3000);
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await t.tap(find.text('Great'));
      }
      await t.pumpWidget(const SizedBox());
      await wait(t);
    }

    final dialog = find.byType(AlertDialog);

    testWidgets('read well: the word after each try, three stars', (t) async {
      final (dev, progress) = await play(t, [ipa('Ei'), ipa('Bett')]);
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      final said = dev.log.started('tts');
      // nothing is said before the child reads
      expect(dev.log.events.firstWhere((e) => e.on).device, 'mic');
      expect(said.where((s) => s.startsWith('Ei!')), hasLength(1));
      expect(said.where((s) => s.startsWith('Bett!')), hasLength(1));
      expect(dev.log.started('mic'), hasLength(2));
      expect(find.text('6 / 6'), findsOneWidget);
      expect(progress.readAloudBest('de-DE'), 3);
      await close(t, dev.log);
    });

    testWidgets('0 stars: once more, the better try counts', (t) async {
      final (dev, progress) = await play(t, [
        ipa('Kuh'), // not Ei
        ipa('Ei'),
        ipa('Bett'),
      ]);
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      expect(dev.log.started('mic'), hasLength(3));
      expect(find.text('6 / 6'), findsOneWidget);
      expect(progress.readAloudBest('de-DE'), 3);
      await close(t, dev.log);
    });

    testWidgets('twice 0 stars: on to the next word', (t) async {
      final (dev, progress) = await play(t, [
        ipa('Kuh'),
        ipa('Kuh'),
        ipa('Bett'),
      ]);
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      expect(dev.log.started('mic'), hasLength(3));
      expect(find.text('3 / 6'), findsOneWidget);
      expect(progress.readAloudBest('de-DE'), 2);
      await close(t, dev.log);
    });

    testWidgets('silence: a hint, the mic waits for a tap', (t) async {
      final (dev, _) = await play(
        t,
        [ipa('Ei'), ipa('Bett')],
        child: [Child.silent, Child.speaks],
      );
      await until(
        t,
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        dev.log,
      );
      await wait(t, 2000);
      expect(dev.log.started('mic'), hasLength(1));
      await t.tap(find.byTooltip('Speak'));
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      expect(dev.log.started('mic'), hasLength(3));
      await close(t, dev.log);
    });

    testWidgets('background while listening: the mic goes off', (t) async {
      final (dev, _) = await play(t, [ipa('Ei'), ipa('Bett')]);
      await until(t, () => dev.mic.recording, dev.log);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await wait(t, 500);
      expect(dev.mic.recording, isFalse);
      await wait(t, 3000);
      expect(dev.log.started('tts'), isEmpty);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await wait(t, 500);
      await t.tap(find.byTooltip('Speak'));
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      await close(t, dev.log);
    });

    testWidgets('➡ during the praise stops it', (t) async {
      final (dev, _) = await play(t, [ipa('Ei'), ipa('Bett')]);
      await until(t, () => dev.speaker.speaking, dev.log);
      await t.tap(find.byIcon(Icons.arrow_forward_rounded));
      await t.pump(const Duration(milliseconds: 50));
      expect(dev.speaker.speaking, isFalse);
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      expect(dev.log.started('mic'), hasLength(2));
      await close(t, dev.log);
    });

    testWidgets('no microphone allowed: a hint, nothing recorded', (t) async {
      final (dev, _) = await play(
        t,
        [ipa('Ei')],
        prepare: (d) {
          d.mic.permission = false;
        },
      );
      await until(
        t,
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        dev.log,
      );
      expect(find.text('Please allow the microphone.'), findsWidgets);
      expect(dev.log.started('mic'), isEmpty);
      await close(t, dev.log);
    });

    testWidgets('the recogniser fails: try again, the mic is off', (t) async {
      final (dev, _) = await play(t, [ipa('Ei')], failRecognizer: true);
      await until(
        t,
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        dev.log,
      );
      expect(dev.mic.recording, isFalse);
      expect(dev.log.started('mic'), hasLength(1));
      await close(t, dev.log);
    });

    testWidgets('🎤 while listening: done now, scored', (t) async {
      final (dev, _) = await play(
        t,
        [ipa('Ei'), ipa('Bett')],
        child: [Child.speaksAtOnce],
      );
      await until(t, () => dev.mic.recording, dev.log);
      await t.pump(const Duration(milliseconds: 1500));
      await t.tap(find.byTooltip('Your turn!'));
      await until(t, () => dev.speaker.speaking, dev.log);
      expect(dev.mic.recording, isFalse);
      expect(dev.log.started('tts').first, startsWith('Ei!'));
      await close(t, dev.log);
    });

    testWidgets('➡ skips a word the child cannot read', (t) async {
      final (dev, _) = await play(
        t,
        [ipa('Bett')],
        child: [Child.silent, Child.speaks],
      );
      await until(
        t,
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        dev.log,
      );
      await t.tap(find.byIcon(Icons.arrow_forward_rounded));
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      // Ei skipped: 0 stars, Bett: 3
      expect(find.text('3 / 6'), findsOneWidget);
      await close(t, dev.log);
    });

    testWidgets('the child starts late: still heard', (t) async {
      final (dev, _) = await play(t, [
        ipa('Ei'),
        ipa('Bett'),
      ], prepare: (d) => d.mic.speechDelay = const Duration(seconds: 9));
      await until(t, () => dev.speaker.speaking, dev.log);
      expect(find.byType(SnackBar), findsNothing);
      expect(dev.log.started('tts').first, startsWith('Ei!'));
      await close(t, dev.log);
    });

    testWidgets('closing the screen while listening: nothing scored', (
      t,
    ) async {
      final (dev, progress) = await play(t, [ipa('Ei'), ipa('Bett')]);
      await until(t, () => dev.mic.recording, dev.log);
      await t.pageBack();
      await wait(t, 3000);
      expect(dev.mic.recording, isFalse);
      expect(dev.log.started('tts'), isEmpty);
      expect(progress.readAloudBest('de-DE'), 0);
      await close(t, dev.log);
    });
  });
}
