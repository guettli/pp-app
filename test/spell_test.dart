// The letter puzzle: which words can be spelled, the rounds, and whole
// rounds played with taps on the fake clock.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:phoneme_party/spell/spell_rules.dart';
import 'package:phoneme_party/spell/spell_screen.dart';
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

Phrase word(String text) =>
    Phrase(text: text, emoji: '🐭', ipa: '/x/', level: 1);

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

  group('rules', () {
    test('letters: an accent stays on its letter', () {
      expect(lettersOf('Bär'), ['B', 'ä', 'r']);
      // e + combining acute: one tile
      expect(lettersOf('café'), hasLength(4));
      expect(lettersOf('niño'), ['n', 'i', 'ñ', 'o']);
      expect(lettersOf('œuf'), ['œ', 'u', 'f']);
    });

    test('only single words of 2 to 7 letters', () {
      expect(spellable(word('Hund')), isTrue);
      expect(spellable(word('Ei')), isTrue);
      expect(spellable(word('ice cream')), isFalse);
      expect(spellable(word('pop-corn')), isFalse);
      expect(spellable(word("l'eau")), isFalse);
      expect(spellable(word('Schmetterling')), isFalse);
      expect(spellable(word('a')), isFalse);
    });

    test('looks alike: the same letter with another accent', () {
      expect(looksAlike('o', 'ó'), isTrue);
      expect(looksAlike('A', 'ä'), isTrue);
      expect(looksAlike('é', 'è'), isTrue);
      expect(looksAlike('ñ', 'n'), isTrue);
      expect(looksAlike('ß', 's'), isFalse);
      expect(looksAlike('o', 'u'), isFalse);
    });

    for (final lang in langs) {
      test('$lang: rounds from the first three worlds', () {
        final book = books[lang]!;
        final pool = [for (var w = 0; w < 3; w++) ...book.world(w)];
        final alphabet = alphabetOf(book.phrases);
        expect(alphabet.length, greaterThan(20));
        for (var seed = 0; seed < 20; seed++) {
          final round = makeSpellRound(pool, alphabet, math.Random(seed));
          expect(round, hasLength(6), reason: '$lang seed $seed');
          expect(round.map((p) => p.phrase).toSet(), hasLength(6));
          var last = 0;
          for (final (i, p) in round.indexed) {
            expect(p.letters.join(), p.phrase.text, reason: '$p');
            // short words first
            expect(p.letters.length, greaterThanOrEqualTo(last));
            last = p.letters.length;
            final extra = p.tiles.length - p.letters.length;
            expect(extra, i < 2 ? 0 : (i < 4 ? 1 : 2), reason: '$p');
            // every letter has its tile, the extra ones are not in the word
            final rest = [...p.tiles];
            for (final l in p.letters) {
              expect(rest.remove(l), isTrue, reason: '$p');
            }
            for (final x in rest) {
              expect(p.letters.any((l) => looksAlike(l, x)), isFalse);
            }
          }
        }
      });
    }
  });

  group('screen', () {
    Phrase w(String text) =>
        books['de-DE']!.phrases.firstWhere((p) => p.text == text);
    List<SpellPuzzle> two() => [
      SpellPuzzle(w('Ei'), const ['E', 'i'], const ['i', 'E']),
      SpellPuzzle(
        w('Bett'),
        const ['B', 'e', 't', 't'],
        const ['t', 'x', 'B', 't', 'e'],
      ),
    ];

    Future<(FakeDevices, Progress)> play(
      WidgetTester t, {
      List<SpellPuzzle>? round,
    }) async {
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
          builder: (_) =>
              SpellScreen(app: app, round: round ?? two(), intro: false),
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

    Future<void> tile(WidgetTester t, int i) async {
      await t.tap(find.byKey(ValueKey('spell-tile-$i')));
      await t.pump(const Duration(milliseconds: 50));
    }

    Future<void> close(WidgetTester t, IoLog log) async {
      expect(log.problems, isEmpty, reason: '$log');
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await t.tap(find.byIcon(Icons.check_rounded));
      }
      await t.pumpWidget(const SizedBox());
      await wait(t);
    }

    testWidgets('the tiles as written in the word: E, not e', (t) async {
      final (dev, _) = await play(t);
      await wait(t, 1500);
      final e = find.descendant(
        of: find.byKey(const ValueKey('spell-tile-1')),
        matching: find.text('E'),
      );
      expect(e, findsOneWidget);
      await close(t, dev.log);
    });

    testWidgets('the small e is not the capital E of Ente', (t) async {
      final ente = SpellPuzzle(
        w('Ente'),
        const ['E', 'n', 't', 'e'],
        const ['e', 'n', 'E', 't'],
      );
      final (dev, progress) = await play(t, round: [ente]);
      await wait(t, 1000);
      await tile(t, 0); // e: wrong for the first letter
      await wait(t, 600);
      for (final i in [2, 1, 3, 0]) {
        await tile(t, i);
      }
      await wait(t, 6000);
      expect(find.text('0 / 1'), findsOneWidget);
      expect(progress.spellBest('de-DE'), 0);
      await close(t, dev.log);
    });

    testWidgets('all right: on by itself, three stars', (t) async {
      final (dev, progress) = await play(t);
      await wait(t, 1000);
      expect(dev.log.started('tts'), ['Ei']);
      await tile(t, 1); // E
      await tile(t, 0); // i
      await wait(t, 6000);
      expect(dev.log.started('tts'), contains('Bett'));
      // both t tiles work for either t
      for (final i in [2, 4, 3, 0]) {
        await tile(t, i);
      }
      await wait(t, 6000);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(progress.spellBest('de-DE'), 3);
      expect(dev.log.started('mic'), isEmpty);
      await close(t, dev.log);
    });

    testWidgets('wrong tiles: no star for that word, the right one glows', (
      t,
    ) async {
      final (dev, progress) = await play(t);
      await wait(t, 1000);
      Color color(int i) =>
          t.widget<Material>(find.byKey(ValueKey('spell-tile-$i'))).color!;
      final normal = color(1);
      await tile(t, 0); // i, but E is next
      await wait(t, 500);
      expect(color(1), normal);
      await tile(t, 0);
      await wait(t, 500);
      expect(color(1), isNot(normal)); // E glows
      await tile(t, 1);
      await tile(t, 0);
      await wait(t, 6000);
      for (final i in [2, 4, 0, 3]) {
        await tile(t, i);
      }
      await wait(t, 6000);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(progress.spellBest('de-DE'), 1);
      await close(t, dev.log);
    });

    testWidgets('background during the praise: it waits for ➡', (t) async {
      final (dev, _) = await play(t);
      await wait(t, 1000);
      await tile(t, 1);
      await tile(t, 0);
      await wait(t, 800);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump(const Duration(milliseconds: 50));
      expect(dev.speaker.speaking, isFalse);
      await wait(t, 3000);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await wait(t, 3000);
      expect(dev.log.started('tts'), isNot(contains('Bett')));
      await t.tap(find.byIcon(Icons.arrow_forward_rounded));
      await wait(t, 1500);
      expect(dev.log.started('tts').last, 'Bett');
      await close(t, dev.log);
    });

    testWidgets('background mid-word: the word again on return', (t) async {
      final (dev, _) = await play(t);
      await wait(t, 1000);
      await tile(t, 1);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await wait(t, 1000);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await wait(t, 1000);
      expect(dev.log.started('tts'), ['Ei', 'Ei']);
      await tile(t, 0);
      await wait(t, 6000);
      expect(dev.log.started('tts'), contains('Bett'));
      await close(t, dev.log);
    });

    testWidgets('➡ during the last praise: it stops, the dialog once', (
      t,
    ) async {
      final (dev, _) = await play(t);
      await wait(t, 1000);
      await tile(t, 1);
      await tile(t, 0);
      await wait(t, 6000);
      for (final i in [2, 4, 3, 0]) {
        await tile(t, i);
      }
      await wait(t, 800);
      expect(dev.speaker.speaking, isTrue);
      await t.tap(find.byIcon(Icons.arrow_forward_rounded));
      await t.pump(const Duration(milliseconds: 50));
      expect(dev.speaker.speaking, isFalse);
      await wait(t, 3000);
      expect(find.byType(AlertDialog), findsOneWidget);
      await close(t, dev.log);
    });

    testWidgets('closing the screen mid-praise stops everything', (t) async {
      final (dev, _) = await play(t);
      await wait(t, 1000);
      await tile(t, 1);
      await tile(t, 0);
      await wait(t, 800);
      await t.pageBack();
      await wait(t, 3000);
      expect(dev.speaker.speaking, isFalse);
      expect(dev.log.started('tts'), isNot(contains('Bett')));
      await close(t, dev.log);
    });

    testWidgets('➡ right after the last letter: the next word, no praise', (
      t,
    ) async {
      final (dev, _) = await play(t);
      await wait(t, 1000);
      await tile(t, 1);
      await tile(t, 0);
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.byIcon(Icons.arrow_forward_rounded));
      await wait(t, 3000);
      final said = dev.log.started('tts');
      expect(said.last, 'Bett');
      expect(said.where((s) => s.contains('!')), isEmpty);
      await close(t, dev.log);
    });

    testWidgets('🔊 during the praise does not cut it off', (t) async {
      final (dev, _) = await play(t);
      await wait(t, 1000);
      await tile(t, 1);
      await tile(t, 0);
      await wait(t, 800);
      await t.tap(find.byKey(const ValueKey('spell-picture')));
      await wait(t, 6000);
      expect(dev.log.started('tts'), hasLength(3)); // Ei, praise, Bett
      await close(t, dev.log);
    });

    testWidgets('the picture says the word again', (t) async {
      final (dev, _) = await play(t);
      await wait(t, 1000);
      await t.tap(find.byKey(const ValueKey('spell-picture')));
      await wait(t, 1000);
      expect(dev.log.started('tts'), ['Ei', 'Ei']);
      await close(t, dev.log);
    });
  });
}
