// The sound detective: first sounds, fair "starts like" questions in every
// language, and a round in the quiz screen.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:phoneme_party/quiz/facts.dart';
import 'package:phoneme_party/quiz/quiz_lines.dart';
import 'package:phoneme_party/quiz/quiz_rules.dart';
import 'package:phoneme_party/quiz/quiz_screen.dart';
import 'package:phoneme_party/quiz/sound_rules.dart';
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

  Phrase w(String text, [String lang = 'de-DE']) =>
      books[lang]!.phrases.firstWhere((p) => p.text == text);

  test('first sounds: consonants only, length marks dropped', () {
    expect(firstSound(comparer, w('Kuh'), 'de-DE'), 'k');
    expect(firstSound(comparer, w('Schuh'), 'de-DE'), 'ʃ');
    expect(firstSound(comparer, w('Ei'), 'de-DE'), isNull);
    expect(firstSound(comparer, w('Ohr'), 'de-DE'), isNull);
  });

  test('affricates are one sound', () {
    expect(firstSound(comparer, w('Zahn'), 'de-DE'), 'ts');
    expect(firstSound(comparer, w('Pferd'), 'de-DE'), 'pf');
    expect(firstSound(comparer, w('chair', 'en-GB'), 'en-GB'), 'tʃ');
    expect(firstSound(comparer, w('giraffe', 'en-GB'), 'en-GB'), 'dʒ');
    expect(firstSound(comparer, w('zucca', 'it-IT'), 'it-IT'), isNotNull);
    expect(firstSound(comparer, w('zucca', 'it-IT'), 'it-IT')!.length, 2);
    // ts is not clearly other than t or s, so never offered against them
    expect(clearlyOther(comparer, ['t'], ['ts'], 'de-DE'), isFalse);
    expect(clearlyOther(comparer, ['ʃ'], ['tʃ'], 'en-GB'), isFalse);
    expect(clearlyOther(comparer, ['m'], ['ts'], 'de-DE'), isTrue);
  });

  test('the onset is every consonant before the first vowel', () {
    expect(firstSound(comparer, w('Stuhl'), 'de-DE'), 'ʃt');
    expect(firstSound(comparer, w('Spinne'), 'de-DE'), 'ʃp');
    expect(firstSound(comparer, w('Schuh'), 'de-DE'), 'ʃ');
    expect(firstSound(comparer, w('Maus'), 'de-DE'), 'm');
    expect(onsetOf(comparer, '/t͡svɛrk/', 'de-DE'), 'tsv');
    expect(onsetOf(comparer, '/ʃtɛrn/', 'de-DE'), 'ʃt');
    // only the first word of a phrase
    expect(onsetOf(comparer, '/ˈaɪs kriːm/', 'en-GB'), isNull);
    // Schuh and Spinne are not offered against Stuhl (both start with ʃ)
    expect(clearlyOther(comparer, ['ʃ'], ['ʃ', 't'], 'de-DE'), isFalse);
  });

  test('Stuhl never starts like Spinne', () {
    final book = books['de-DE']!;
    final stuhl = w('Stuhl');
    var asked = 0;
    for (var seed = 0; seed < 50; seed++) {
      final q = makeSoundQuestion(
        stuhl,
        book.phrases,
        comparer,
        'de-DE',
        math.Random(seed),
        // as in the app
        similar: (a, b) => soundsSimilar(comparer, 'de-DE', a, b),
      );
      if (q == null) continue;
      asked++;
      expect(firstSound(comparer, q.answer, 'de-DE'), 'ʃt', reason: '$q');
      expect(q.options.map((o) => o.text), isNot(contains('Spinne')));
    }
    expect(asked, greaterThan(0)); // Stern starts like Stuhl
  });

  test('German r and ʁ are one sound', () {
    expect(onsetOf(comparer, '/trɔmˈpeːtə/', 'de-DE'), 'tʁ');
    expect(onsetOf(comparer, '/ˈtʁaktoːɐ̯/', 'de-DE'), 'tʁ');
  });

  test('glides after a consonant: part of the vowel in fr, it, es', () {
    expect(onsetOf(comparer, '/pwasɔ̃/', 'fr-FR'), 'p');
    expect(onsetOf(comparer, '/tʁwa/', 'fr-FR'), 'tʁ');
    expect(onsetOf(comparer, '/ˈpweɾta/', 'es-ES'), 'p');
    expect(onsetOf(comparer, '/ˈpjɛːde/', 'it-IT'), 'p');
    expect(onsetOf(comparer, '/ˈtjuːlɪp/', 'en-GB'), 't');
    expect(onsetOf(comparer, '/kwiːn/', 'en-GB'), 'kw');
    // a glide at the start stays: huevo starts with w
    expect(onsetOf(comparer, '/ˈweβo/', 'es-ES'), 'w');
    // and is not clearly other than a vowel start
    expect(clearlyOther(comparer, null, ['w'], 'es-ES'), isFalse);
    // the first word of a phrase
    expect(onsetOf(comparer, '/flamɑ̃ ʁoz/', 'fr-FR'), 'fl');
  });

  test('marks do not change the first sound', () {
    expect(onsetOf(comparer, '/tʰiː/', 'en-GB'), 't');
    expect(onsetOf(comparer, '/ˈt‍ʃiːz/', 'en-GB'), 'tʃ');
  });

  test('close sounds are not clearly other', () {
    for (final (a, b) in [
      ('b', 'p'),
      ('f', 'v'),
      ('m', 'n'),
      ('f', 'θ'),
      ('l', 'r'),
      ('s', 'ʃ'),
    ]) {
      expect(
        clearlyOther(comparer, [a], [b], 'en-GB'),
        isFalse,
        reason: '$a $b',
      );
    }
  });

  for (final lang in langs) {
    test('$lang: fair rounds', () {
      final book = books[lang]!;
      bool similar(Phrase a, Phrase b) => soundsSimilar(comparer, lang, a, b);
      for (var seed = 0; seed < 10; seed++) {
        final round = makeSoundRound(
          book.phrases,
          comparer,
          lang,
          math.Random(seed),
          similar: similar,
        );
        expect(round, hasLength(8), reason: '$lang seed $seed');
        expect(round.map((q) => q.answer.text).toSet(), hasLength(8));
        for (final q in round) {
          final like = q.ask.like!;
          final onset = firstSound(comparer, like, lang)!;
          expect(q.options, hasLength(3), reason: '$q');
          expect(q.options, contains(q.answer));
          expect(q.options.map((o) => o.emoji).toSet(), hasLength(3));
          expect(q.options.any((o) => o.emoji == like.emoji), isFalse);
          // every name the child may say: the answer starts like it,
          // the others clearly not
          for (final a in q.answer.accepted) {
            expect(onsetOf(comparer, a.ipa, lang), onset, reason: '$q');
          }
          final sounds = onsetSounds(comparer, like.ipa, lang)!;
          for (final o in q.options) {
            if (o == q.answer) continue;
            for (final a in o.accepted) {
              expect(
                clearlyOther(
                  comparer,
                  onsetSounds(comparer, a.ipa, lang),
                  sounds,
                  lang,
                ),
                isTrue,
                reason: '$q: ${a.text}',
              );
            }
          }
          for (final a in q.options) {
            for (final b in q.options) {
              if (a != b) expect(similar(a, b), isFalse, reason: '$q');
            }
          }
          // the question can be said
          expect(QuizLines.of(lang).ask(q), contains(like.text));
        }
      }
    });
  }

  test('b and p are never offered against each other', () {
    expect(comparer.phonemeCost('b', 'p', 'de-DE'), lessThan(minOnsetCost));
  });

  group('screen', () {
    String ipa(String t) => w(t).ipa.replaceAll('/', '');

    testWidgets('a round: asked like the quiz, own record', (t) async {
      SharedPreferences.setMockInitialValues({});
      final progress = await Progress.load();
      final t0 = t.binding.clock.now();
      final log = IoLog(() => t.binding.clock.now().difference(t0));
      final dev = FakeDevices(log);
      final app = AppState(
        FakeRecognizer(() => ipa('Kuh')),
        comparer,
        progress,
        books['de-DE']!,
        io: dev.io,
      );
      final q = QuizQuestion(Ask.startsLike(w('Katze')), [
        w('Ei'),
        w('Kuh'),
        w('Bett'),
      ], w('Kuh'));
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(navigatorKey: nav, home: const Scaffold()),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              QuizScreen(app: app, sounds: true, round: [q], intro: false),
        ),
      );
      await t.pump();
      await t.pump();
      expect(find.text('Was fängt an wie Katze?'), findsOneWidget);
      expect(find.byKey(const ValueKey('quiz-like')), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      for (var i = 0; i < 1200 && dialog.evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(dialog, findsOneWidget, reason: '$log');
      expect(
        log.started('tts').first,
        'Was fängt an wie Katze? Ei, Kuh oder Bett?',
      );
      expect(progress.soundsBest('de-DE'), 3);
      expect(progress.quizBest('de-DE'), 0);
      expect(log.soundsWhileRecording(), isEmpty, reason: '$log');
      await t.tap(find.text('Great'));
      await t.pumpWidget(const SizedBox());
      for (var i = 0; i < 60; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    });
  });
}
