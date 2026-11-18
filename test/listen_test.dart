// "Listen closely": the rounds made from the word lists, and whole rounds
// played with taps on the fake clock.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/listen/listen_rules.dart';
import 'package:phoneme_party/listen/listen_screen.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
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

  Closeness closeness(String lang) =>
      (a, b) => comparer.compare(a.ipa, b.ipa, lang).score;

  group('rounds', () {
    for (final lang in langs) {
      test('$lang: fair rounds from the first three worlds', () {
        final book = books[lang]!;
        final pool = [for (var w = 0; w < 3; w++) ...book.world(w)];
        for (var seed = 0; seed < 20; seed++) {
          final round = makeListenRound(
            pool,
            math.Random(seed),
            closeness: closeness(lang),
          );
          expect(round, hasLength(8));
          expect(round.map((q) => q.answer).toSet(), hasLength(8));
          for (final q in round) {
            expect(q.options, hasLength(4), reason: '$q');
            expect(q.options, contains(q.answer), reason: '$q');
            expect(q.options.map((o) => o.emoji).toSet(), hasLength(4));
            for (final a in q.options) {
              for (final b in q.options) {
                if (a != b) expect(sameForTheEar(a, b), isFalse, reason: '$q');
              }
            }
          }
        }
      });
    }

    test('second half: the closest-sounding word is one of the options', () {
      final book = books['de-DE']!;
      final round = makeListenRound(
        book.phrases,
        math.Random(3),
        closeness: closeness('de-DE'),
      );
      for (final q in round.skip(4)) {
        final others = [
          for (final p in book.phrases)
            if (!sameForTheEar(p, q.answer)) p,
        ];
        final c = closeness('de-DE');
        others.sort((a, b) => c(b, q.answer).compareTo(c(a, q.answer)));
        expect(q.options, contains(others.first), reason: '$q');
      }
    });

    test('the same picture or the same word is never a wrong option', () {
      Phrase p(String text, String ipa, String emoji) =>
          Phrase(text: text, emoji: emoji, ipa: ipa, level: 1);
      expect(
        sameForTheEar(p('Maus', '/maʊ̯s/', '🐭'), p('Maus', '/x/', '🐁')),
        isTrue,
      );
      expect(
        sameForTheEar(p('a', '/ˈmeːɐ/', '🌊'), p('b', '/meːɐ/', '🏝')),
        isTrue,
      );
      expect(sameForTheEar(p('a', '/a/', '🐭'), p('b', '/b/', '🐭')), isTrue);
      expect(
        sameForTheEar(p('Maus', '/maʊ̯s/', '🐭'), p('Haus', '/haʊ̯s/', '🏠')),
        isFalse,
      );
    });

    test('too few words: no round instead of a broken one', () {
      final few = books['de-DE']!.phrases.take(3).toList();
      expect(
        makeListenRound(few, math.Random(1), closeness: closeness('de-DE')),
        isEmpty,
      );
    });
  });

  group('screen', () {
    Phrase w(String text) =>
        books['de-DE']!.phrases.firstWhere((p) => p.text == text);
    List<ListenQuestion> two() => [
      ListenQuestion(w('Kuh'), [w('Ei'), w('Kuh'), w('Ohr'), w('Bett')]),
      ListenQuestion(w('Bett'), [w('Bett'), w('Ei'), w('Kuh'), w('Ohr')]),
    ];

    Future<(FakeDevices, Progress)> play(WidgetTester t) async {
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
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(navigatorKey: nav, home: const Scaffold()),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ListenScreen(app: app, round: two()),
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

    Future<void> close(WidgetTester t, IoLog log) async {
      expect(log.problems, isEmpty, reason: '$log');
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await t.tap(find.text('Great'));
      }
      await t.pumpWidget(const SizedBox());
      await wait(t);
    }

    testWidgets('right at once: on by itself, three stars', (t) async {
      final (dev, progress) = await play(t);
      await wait(t, 1500);
      expect(dev.log.started('tts'), ['Kuh']);
      // no word under the pictures before the answer
      expect(find.text('Kuh'), findsNothing);
      await t.tap(find.byKey(const ValueKey('listen-option-1')));
      await wait(t, 6000);
      expect(dev.log.started('tts'), contains('Bett'));
      await t.tap(find.byKey(const ValueKey('listen-option-0')));
      await wait(t, 6000);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(progress.listenBest('de-DE'), 3);
      expect(dev.log.started('mic'), isEmpty);
      await close(t, dev.log);
    });

    testWidgets('a wrong tap: its word, the word again, no star', (t) async {
      final (dev, progress) = await play(t);
      await wait(t, 1500);
      await t.tap(find.byKey(const ValueKey('listen-option-0'))); // Ei
      await wait(t, 4000);
      expect(dev.log.started('tts'), ['Kuh', 'Ei', 'Kuh']);
      // the same wrong picture again does nothing
      await t.tap(find.byKey(const ValueKey('listen-option-0')));
      await wait(t, 1000);
      expect(dev.log.started('tts'), hasLength(3));
      await t.tap(find.byKey(const ValueKey('listen-option-1'))); // Kuh
      await wait(t, 6000);
      await t.tap(find.byKey(const ValueKey('listen-option-0'))); // Bett
      await wait(t, 6000);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(progress.listenBest('de-DE'), 1);
      await close(t, dev.log);
    });

    testWidgets('a tap while the word is said stops it', (t) async {
      final (dev, _) = await play(t);
      await t.pump(const Duration(milliseconds: 100));
      expect(dev.speaker.speaking, isTrue);
      await t.tap(find.byKey(const ValueKey('listen-option-1')));
      await t.pump(const Duration(milliseconds: 50));
      await wait(t, 6000);
      expect(dev.log.started('tts'), contains('Bett'));
      await close(t, dev.log);
    });
  });
}
