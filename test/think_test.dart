// The thinking games: the content in every language, fair rounds, and
// whole rounds played with taps on the fake clock.
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
import 'package:phoneme_party/ui/emoji_image.dart';
import 'package:phoneme_party/think/feelings_data.dart';
import 'package:phoneme_party/think/think_data.dart';
import 'package:phoneme_party/think/think_rules.dart';
import 'package:phoneme_party/think/think_screen.dart';
import 'package:phoneme_party/ui/intros.dart';
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
  late Facts facts;
  final books = <String, PhraseBook>{};
  setUpAll(() {
    facts = Facts.parse(File(Facts.asset).readAsStringSync());
    comparer = PhonemeComparer.fromJson(
      File('assets/panphon/panphon_features.json').readAsStringSync(),
    );
    for (final l in langs) {
      books[l] = load(l);
    }
  });

  group('content', () {
    test('every picture is in every book', () {
      final all = {
        for (final n in needs) ...{...n.yes, ...n.maybe},
        ...needExtras,
        for (final r in riddles) ...{r.emoji, ...r.alike},
      };
      for (final lang in langs) {
        for (final e in all) {
          expect(pictureOf(books[lang]!, e), isNotNull, reason: '$lang $e');
        }
      }
    });

    test('every problem and riddle in every language', () {
      for (final lang in langs) {
        final code = lang.split('-').first;
        expect(needQuestion[code], isNotEmpty);
        for (final n in needs) {
          expect(n.say[code], isNotEmpty, reason: '$code ${n.yes}');
          expect(n.yes.intersection(n.maybe), isEmpty);
        }
        for (final r in riddles) {
          expect(r.clues[code], hasLength(3), reason: '$code ${r.emoji}');
          expect(r.clues[code]!.every((c) => c.isNotEmpty), isTrue);
        }
      }
      expect(riddles.map((r) => r.emoji).toSet(), hasLength(riddles.length));
    });

    test('every feeling, story and help in every language', () {
      for (final lang in langs) {
        final code = lang.split('-').first;
        expect(feelingQuestion[code], isNotEmpty);
        expect(faceQuestion[code], contains('{f}'));
        expect(introLine(GameIntro.feelings, lang), isNotEmpty);
        expect(introLine(GameIntro.faces, lang), isNotEmpty);
        final names = feelingNames[code]!;
        expect(names.keys.toSet(), Feeling.values.toSet());
        expect(names.values.toSet(), hasLength(Feeling.values.length));
        for (final st in feelingStories) {
          expect(st.say[code], isNotEmpty, reason: '$code ${st.yes}');
          expect(st.help[code], isNotEmpty, reason: '$code ${st.yes}');
          expect(st.maybe, isNot(contains(st.yes)));
        }
      }
      // every feeling is the answer of some story
      expect(feelingStories.map((s) => s.yes).toSet(), Feeling.values.toSet());
      for (final e in feelingEmoji.values) {
        expect(File('assets/emoji/${emojiKey(e)}.webp').existsSync(), isTrue);
      }
    });

    test('odd one out and who lives here: every language, every picture', () {
      for (final k in oddKinds.keys) {
        Prop.values.byName(k); // a facts.tsv property
      }
      final animals = {
        for (final h in habitats) ...{...h.yes, ...h.maybe},
        ...habitatAnimals,
      };
      for (final lang in langs) {
        final code = lang.split('-').first;
        expect(oddQuestion[code], isNotEmpty);
        for (final k in oddKinds.values) {
          expect(k[code], isNotEmpty, reason: code);
        }
        expect(oddHints.keys.toSet(), oddKinds.keys.toSet());
        for (final k in oddHints.values) {
          expect(k[code], isNotEmpty, reason: code);
        }
        for (final h in habitats) {
          expect(h.say[code], isNotEmpty, reason: '$code ${h.scene}');
        }
        for (final e in animals) {
          expect(pictureOf(books[lang]!, e), isNotNull, reason: '$lang $e');
        }
      }
      for (final h in habitats) {
        expect(h.yes.intersection(h.maybe), isEmpty, reason: h.scene);
        // whoever lives there is an animal of the wrong-picture pool too
        expect(habitatAnimals.containsAll(h.yes), isTrue, reason: h.scene);
        expect(
          File('assets/emoji/${emojiKey(h.scene)}.webp').existsSync(),
          isTrue,
          reason: h.scene,
        );
      }
    });
  });

  group('rounds', () {
    for (final lang in langs) {
      test('$lang: what do I need', () {
        for (var seed = 0; seed < 30; seed++) {
          final round = makeNeedsRound(books[lang]!, math.Random(seed));
          expect(round, hasLength(6));
          expect(round.map((q) => q.answer.emoji).toSet(), hasLength(6));
          for (final q in round) {
            expect(q.options, hasLength(3), reason: '$q');
            expect(q.options, contains(q.answer));
            expect(q.options.map((o) => o.emoji).toSet(), hasLength(3));
            expect(q.clues, hasLength(1));
            final need = needs.firstWhere(
              (n) => q.clues.first.startsWith(n.say[lang.split('-').first]!),
            );
            final helps = {...need.yes, ...need.maybe}.map(bareEmoji);
            expect(helps, contains(bareEmoji(q.answer.emoji)));
            for (final o in q.options) {
              if (o != q.answer) {
                expect(
                  helps,
                  isNot(contains(bareEmoji(o.emoji))),
                  reason: '$q',
                );
              }
            }
          }
        }
      });

      test('$lang: odd one out', () {
        final code = lang.split('-').first;
        final kinds = oddKinds.keys.map(Prop.values.byName).toSet();
        Set<Prop> kindOf(Phrase p) => facts.of(p)!.yes.intersection(kinds);
        final seen = <Prop>{};
        for (var seed = 0; seed < 30; seed++) {
          final round = makeOddRound(books[lang]!, facts, math.Random(seed));
          expect(round, hasLength(6));
          expect(round.map((q) => q.answer.emoji).toSet(), hasLength(6));
          for (final q in round) {
            expect(q.options, hasLength(4), reason: '$q');
            expect(q.options.map((o) => o.emoji).toSet(), hasLength(4));
            expect(q.clues, hasLength(2));
            expect(q.clues.first, oddQuestion[code]);
            final three = [
              for (final o in q.options)
                if (o != q.answer) o,
            ];
            final kind = kindOf(three.first);
            expect(kind, hasLength(1), reason: '$q');
            for (final o in three) {
              expect(kindOf(o), kind, reason: '$q');
            }
            final odd = kindOf(q.answer);
            expect(odd, hasLength(1), reason: '$q');
            expect(odd, isNot(kind), reason: '$q');
            expect({
              odd.single.name,
              kind.single.name,
            }, isNot({'plant', 'eat'}));
            expect(q.because, oddKinds[kind.single.name]![code]);
            expect(q.clues.last, oddHints[kind.single.name]![code]);
            // exactly one answer: nothing unclear across the two kinds
            expect(facts.of(q.answer)!.truth(kind.single), Truth.no);
            for (final o in three) {
              expect(facts.of(o)!.truth(odd.single), Truth.no, reason: '$q');
            }
            seen.add(kind.single);
          }
        }
        // every kind is asked sometimes
        expect(seen, kinds);
      });

      test('$lang: who lives here', () {
        final code = lang.split('-').first;
        for (var seed = 0; seed < 30; seed++) {
          final round = makeHomeRound(books[lang]!, math.Random(seed));
          expect(round, hasLength(6));
          expect(round.map((q) => q.scene).toSet(), hasLength(6));
          for (final q in round) {
            expect(q.options, hasLength(3), reason: '$q');
            expect(q.options.map((o) => o.emoji).toSet(), hasLength(3));
            final h = habitats.firstWhere((h) => h.scene == q.scene);
            expect(q.clues, [h.say[code]]);
            expect(h.yes.map(bareEmoji), contains(bareEmoji(q.answer.emoji)));
            final lives = {...h.yes, ...h.maybe}.map(bareEmoji).toSet();
            for (final o in q.options) {
              if (o != q.answer) {
                expect(
                  lives,
                  isNot(contains(bareEmoji(o.emoji))),
                  reason: '$q',
                );
              }
            }
          }
        }
      });

      test('$lang: who am I', () {
        for (var seed = 0; seed < 30; seed++) {
          final round = makeRiddleRound(books[lang]!, math.Random(seed));
          expect(round, hasLength(6));
          expect(round.map((q) => q.answer.emoji).toSet(), hasLength(6));
          for (final q in round) {
            expect(q.options, hasLength(4), reason: '$q');
            expect(q.options, contains(q.answer));
            expect(q.options.map((o) => o.emoji).toSet(), hasLength(4));
            expect(q.clues, hasLength(3));
            final r = riddles.firstWhere(
              (r) => bareEmoji(r.emoji) == bareEmoji(q.answer.emoji),
            );
            for (final o in q.options) {
              final e = bareEmoji(o.emoji);
              expect(r.alike.map(bareEmoji), isNot(contains(e)), reason: '$q');
              final other = riddles.firstWhere((x) => bareEmoji(x.emoji) == e);
              expect(
                other.alike.map(bareEmoji),
                isNot(contains(bareEmoji(r.emoji))),
                reason: '$q',
              );
            }
          }
        }
      });
    }
  });

  group('feelings rounds', () {
    for (final lang in langs) {
      test('$lang: how do I feel', () {
        final code = lang.split('-').first;
        for (var seed = 0; seed < 30; seed++) {
          final round = makeFeelingsRound(lang, math.Random(seed));
          expect(round, hasLength(6));
          // every feeling once
          expect(round.map((q) => q.answer.emoji).toSet(), hasLength(6));
          for (final q in round) {
            expect(q.options, hasLength(3), reason: '$q');
            expect(q.options, contains(q.answer));
            expect(q.options.map((o) => o.emoji).toSet(), hasLength(3));
            final st = feelingStories.firstWhere(
              (st) => q.clues.single.startsWith(st.say[code]!),
            );
            expect(q.answer.emoji, feelingEmoji[st.yes]);
            expect(q.because, st.help[code]);
            final fits = {st.yes, ...st.maybe}.map((f) => feelingEmoji[f]);
            for (final o in q.options) {
              if (o != q.answer) {
                expect(fits, isNot(contains(o.emoji)), reason: '$q');
              }
            }
          }
        }
      });

      test('$lang: feeling faces', () {
        for (var seed = 0; seed < 30; seed++) {
          final round = makeFacesRound(lang, math.Random(seed));
          expect(round, hasLength(6));
          expect(round.map((q) => q.answer.emoji).toSet(), hasLength(6));
          for (final q in round) {
            expect(q.options, hasLength(4), reason: '$q');
            expect(q.options, contains(q.answer));
            expect(q.options.map((o) => o.emoji).toSet(), hasLength(4));
            expect(q.clues.single, contains(q.answer.text));
          }
        }
      });
    }
  });

  group('screen', () {
    Phrase w(String text) =>
        books['de-DE']!.phrases.firstWhere((p) => p.text == text);

    Future<(FakeDevices, Progress)> play(
      WidgetTester t,
      ThinkGame game,
      List<ThinkQuestion> round, {
      bool intro = false,
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
              ThinkScreen(app: app, game: game, round: round, intro: intro),
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
      expect(log.started('mic'), isEmpty);
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await t.tap(find.text('Great'));
      }
      await t.pumpWidget(const SizedBox());
      await wait(t);
    }

    const cold = 'Meine Hände sind kalt. Was brauche ich?';
    ThinkQuestion gloves() => ThinkQuestion(
      [cold],
      [w('Löffel'), w('Handschuhe'), w('Buch')],
      w('Handschuhe'),
    );
    ThinkQuestion cow() => ThinkQuestion(
      ['Ich lebe auf dem Bauernhof.', 'Ich fresse Gras.', 'Ich sage Muh!'],
      [w('Schaf'), w('Kuh'), w('Fisch'), w('Sonne')],
      w('Kuh'),
    );

    testWidgets('what do I need: right at once, three stars', (t) async {
      final (dev, progress) = await play(t, ThinkGame.needs, [gloves()]);
      await wait(t, 1500);
      expect(dev.log.started('tts'), [cold]);
      expect(find.text(cold), findsOneWidget);
      // one clue only: no 💡
      expect(find.byKey(const ValueKey('think-hint')), findsNothing);
      await t.tap(find.byKey(const ValueKey('think-option-1')));
      await wait(t, 6000);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(progress.thinkBest('needs', 'de-DE'), 3);
      // the record is said in the study language (the screen is English)
      expect(dev.log.started('tts').last, endsWith('Neuer Rekord!'));
      await close(t, dev.log);
    });

    testWidgets('what do I need: wrong, its word and the problem again', (
      t,
    ) async {
      final (dev, progress) = await play(t, ThinkGame.needs, [gloves()]);
      await wait(t, 1500);
      await t.tap(find.byKey(const ValueKey('think-option-0'))); // Löffel
      await wait(t, 4000);
      expect(dev.log.started('tts'), [cold, 'Löffel', cold]);
      await t.tap(find.byKey(const ValueKey('think-option-1')));
      await wait(t, 6000);
      expect(find.text('0 / 1'), findsOneWidget);
      expect(progress.thinkBest('needs', 'de-DE'), 0);
      await close(t, dev.log);
    });

    testWidgets('how do I feel: the face, what helps, then praise', (t) async {
      final faces = feelingFaces('de-DE');
      const story = 'Mein Eis ist auf den Boden gefallen. Wie fühle ich mich?';
      const help = 'Wenn ich traurig bin, hilft mir eine Umarmung.';
      final q = ThinkQuestion(
        [story],
        [faces[Feeling.happy]!, faces[Feeling.sad]!, faces[Feeling.disgusted]!],
        faces[Feeling.sad]!,
        because: help,
      );
      final (dev, progress) = await play(t, ThinkGame.feelings, [q]);
      await wait(t, 1500);
      expect(dev.log.started('tts'), [story]);
      expect(find.byKey(const ValueKey('think-hint')), findsNothing);
      await t.tap(find.byKey(const ValueKey('think-option-0'))); // fröhlich
      await wait(t, 4000);
      expect(dev.log.started('tts'), [story, 'fröhlich', story]);
      await t.tap(find.byKey(const ValueKey('think-option-1')));
      await wait(t, 1500);
      expect(dev.log.started('tts').last, startsWith('traurig! $help '));
      expect(find.text('traurig'), findsOneWidget);
      await wait(t, 8000);
      expect(progress.thinkBest('feelings', 'de-DE'), 0);
      await close(t, dev.log);
    });

    testWidgets('feeling faces: right at once, three stars', (t) async {
      final round = makeFacesRound('de-DE', math.Random(1), count: 1);
      final (dev, progress) = await play(t, ThinkGame.faces, round);
      await wait(t, 1500);
      expect(dev.log.started('tts'), [round.single.clues.single]);
      final i = round.single.options.indexOf(round.single.answer);
      await t.tap(find.byKey(ValueKey('think-option-$i')));
      await wait(t, 6000);
      expect(progress.thinkBest('faces', 'de-DE'), 3);
      await close(t, dev.log);
    });

    testWidgets('who am I: 💡 gives the next clue, free', (t) async {
      final (dev, progress) = await play(t, ThinkGame.riddle, [cow()]);
      await wait(t, 1500);
      expect(dev.log.started('tts'), ['Ich lebe auf dem Bauernhof.']);
      await t.tap(find.byKey(const ValueKey('think-hint')));
      await wait(t, 2000);
      await t.tap(find.byKey(const ValueKey('think-hint')));
      await wait(t, 2000);
      expect(dev.log.started('tts'), cow().clues);
      expect(find.text('Ich sage Muh!'), findsOneWidget);
      // all said: 💡 does nothing more
      await t.tap(find.byKey(const ValueKey('think-hint')));
      await wait(t, 1000);
      expect(dev.log.started('tts'), hasLength(3));
      // 🔊: all clues so far
      await t.tap(find.byKey(const ValueKey('think-repeat')));
      await wait(t, 3000);
      expect(dev.log.started('tts').last, cow().clues.join(' '));
      await t.tap(find.byKey(const ValueKey('think-option-1')));
      await wait(t, 6000);
      expect(progress.thinkBest('riddle', 'de-DE'), 3);
      await close(t, dev.log);
    });

    testWidgets('who am I: a wrong tap brings the next clue', (t) async {
      final (dev, progress) = await play(t, ThinkGame.riddle, [cow()]);
      await wait(t, 1500);
      await t.tap(find.byKey(const ValueKey('think-option-0'))); // Schaf
      await wait(t, 4000);
      expect(dev.log.started('tts'), [
        'Ich lebe auf dem Bauernhof.',
        'Schaf',
        'Ich fresse Gras.',
      ]);
      await t.tap(find.byKey(const ValueKey('think-option-1')));
      await wait(t, 6000);
      expect(progress.thinkBest('riddle', 'de-DE'), 0);
      await close(t, dev.log);
    });

    testWidgets('paused during the intro: the first clue on resume', (t) async {
      final (dev, progress) = await play(t, ThinkGame.riddle, [
        cow(),
      ], intro: true);
      await t.pump(const Duration(milliseconds: 100));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await wait(t, 2000);
      expect(dev.log.started('tts'), [introLine(GameIntro.riddle, 'de-DE')]);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await wait(t, 2000);
      expect(dev.log.started('tts').last, 'Ich lebe auf dem Bauernhof.');
      await t.tap(find.byKey(const ValueKey('think-option-1')));
      await wait(t, 6000);
      expect(progress.thinkBest('riddle', 'de-DE'), 3);
      await close(t, dev.log);
    });

    testWidgets('a wrong tap, then 🔊 at once: the next clue is kept', (
      t,
    ) async {
      final (dev, _) = await play(t, ThinkGame.riddle, [cow()]);
      await wait(t, 1500);
      await t.tap(find.byKey(const ValueKey('think-option-0'))); // Schaf
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.byKey(const ValueKey('think-repeat')));
      await wait(t, 3000);
      expect(
        dev.log.started('tts').last,
        'Ich lebe auf dem Bauernhof. Ich fresse Gras.',
      );
      await close(t, dev.log);
    });

    testWidgets('the intro first, no taps during it', (t) async {
      final (dev, progress) = await play(t, ThinkGame.riddle, [
        cow(),
      ], intro: true);
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.byKey(const ValueKey('think-option-0')));
      await wait(t, 12000);
      expect(dev.log.started('tts'), [
        introLine(GameIntro.riddle, 'de-DE'),
        'Ich lebe auf dem Bauernhof.',
      ]);
      await t.tap(find.byKey(const ValueKey('think-option-1')));
      await wait(t, 6000);
      expect(progress.thinkBest('riddle', 'de-DE'), 3);
      await close(t, dev.log);
    });

    testWidgets('odd one out: the right tap says why', (t) async {
      final q = ThinkQuestion(
        ['Was passt nicht dazu?'],
        [w('Apfel'), w('Banane'), w('Katze'), w('Birne')],
        w('Katze'),
        because: 'Die anderen kann man essen.',
      );
      final (dev, progress) = await play(t, ThinkGame.odd, [q]);
      await wait(t, 1500);
      expect(dev.log.started('tts'), ['Was passt nicht dazu?']);
      await t.tap(find.byKey(const ValueKey('think-option-2')));
      await wait(t, 6000);
      expect(
        dev.log.started('tts')[1],
        startsWith('Katze! Die anderen kann man essen. '),
      );
      expect(progress.thinkBest('odd', 'de-DE'), 3);
      await close(t, dev.log);
    });

    testWidgets('who lives here: the place is shown', (t) async {
      final q = ThinkQuestion(
        ['Wer wohnt im Meer?'],
        [w('Kuh'), w('Fisch'), w('Löwe')],
        w('Fisch'),
        scene: '🌊',
      );
      final (dev, progress) = await play(t, ThinkGame.home, [q]);
      await wait(t, 1500);
      expect(find.byKey(const ValueKey('think-scene')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('think-option-0'))); // Kuh
      await wait(t, 4000);
      expect(dev.log.started('tts'), [
        'Wer wohnt im Meer?',
        'Kuh',
        'Wer wohnt im Meer?',
      ]);
      await t.tap(find.byKey(const ValueKey('think-option-1')));
      await wait(t, 6000);
      expect(progress.thinkBest('home', 'de-DE'), 0);
      await close(t, dev.log);
    });

    testWidgets('odd one out: a wrong tap brings the nudge', (t) async {
      final q = ThinkQuestion(
        ['Was passt nicht dazu?', 'Drei davon kann man essen.'],
        [w('Apfel'), w('Banane'), w('Hut'), w('Birne')],
        w('Hut'),
        because: 'Die anderen kann man essen.',
      );
      final (dev, progress) = await play(t, ThinkGame.odd, [q]);
      await wait(t, 1500);
      await t.tap(find.byKey(const ValueKey('think-option-0'))); // Apfel
      await wait(t, 6000);
      expect(dev.log.started('tts'), [
        'Was passt nicht dazu?',
        'Apfel',
        'Drei davon kann man essen.',
      ]);
      // 🔊: the question and the nudge, each once
      await t.tap(find.byKey(const ValueKey('think-repeat')));
      await wait(t, 4000);
      expect(
        dev.log.started('tts').last,
        'Was passt nicht dazu? Drei davon kann man essen.',
      );
      await t.tap(find.byKey(const ValueKey('think-option-2')));
      await wait(t, 6000);
      expect(progress.thinkBest('odd', 'de-DE'), 0);
      await close(t, dev.log);
    });
  });
}
