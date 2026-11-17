// The quiz: its data, the questions made from it, how an answer is
// understood, and whole rounds with fake devices on the fake clock.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/net/feedback.dart' show SendResult;
import 'package:phoneme_party/net/quiz_report.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:phoneme_party/quiz/facts.dart';
import 'package:phoneme_party/quiz/quiz_lines.dart';
import 'package:phoneme_party/quiz/quiz_rules.dart';
import 'package:phoneme_party/quiz/quiz_screen.dart';
import 'package:phoneme_party/ui/round_button.dart';
import 'package:phoneme_party/ui/word_list_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

late PhonemeComparer comparer;
late Facts facts;
final books = <String, PhraseBook>{};

PhraseBook load(String lang) {
  final raw = File('assets/phrases/$lang.json').readAsStringSync();
  return PhraseBook(lang, [
    for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
      Phrase.fromJson(j),
  ]);
}

/// Checks what makes a question fair: one clear answer, two clear wrong
/// ones, nothing that sounds alike.
void expectFair(QuizQuestion q, Similar similar) {
  final o = q.options;
  expect(o, hasLength(3), reason: '$q');
  expect(o.map((p) => p.emoji).toSet(), hasLength(3), reason: '$q');
  expect(o, contains(q.answer), reason: '$q');
  for (final a in o) {
    for (final b in o) {
      if (a != b) expect(similar(a, b), isFalse, reason: '$q');
    }
  }
  final prop = q.ask.prop;
  if (prop != null) {
    for (final p in o) {
      expect(
        facts.of(p)!.truth(prop),
        p == q.answer ? Truth.yes : Truth.no,
        reason: '$q',
      );
    }
    return;
  }
  final e = q.ask.extreme!;
  final bySize = e == Extreme.biggest || e == Extreme.smallest;
  final most = e == Extreme.biggest || e == Extreme.heaviest;
  double v(Phrase p) => (bySize ? facts.of(p)!.sizeCm : facts.of(p)!.weightKg)!;
  for (final p in o) {
    if (p == q.answer) continue;
    expect(
      most
          ? clearlyMore(v(q.answer), v(p), bySize: bySize)
          : clearlyMore(v(p), v(q.answer), bySize: bySize),
      isTrue,
      reason: '$q',
    );
  }
}

void main() {
  setUpAll(() {
    comparer = PhonemeComparer.fromJson(
      File('assets/panphon/panphon_features.json').readAsStringSync(),
    );
    facts = Facts.parse(File(Facts.asset).readAsStringSync());
    for (final l in studyLanguages) {
      books[l] = load(l);
    }
  });

  test('every picture of every language has its facts', () {
    for (final b in books.values) {
      for (final p in b.phrases) {
        expect(facts.of(p), isNotNull, reason: '${b.lang} ${p.emoji}');
      }
    }
    expect(facts.byEmoji, hasLength(168));
  });

  test('every question can be asked, in every language', () {
    for (final p in Prop.values) {
      expect(
        facts.byEmoji.values.where((f) => f.yes.contains(p)),
        isNotEmpty,
        reason: p.name,
      );
    }
    for (final l in studyLanguages) {
      final lines = QuizLines.of(l);
      for (final a in Ask.all) {
        expect(lines.question(a), isNotEmpty);
      }
      for (final p in Prop.values) {
        expect(lines.label(p), isNotEmpty);
      }
    }
  });

  test('the phone asks with all three words', () {
    final b = books['de-DE']!;
    Phrase w(String t) => b.phrases.firstWhere((p) => p.text == t);
    final q = QuizQuestion(const Ask.prop(Prop.flies), [
      w('Baum'),
      w('Vogel'),
      w('Haus'),
    ], w('Vogel'));
    expect(
      QuizLines.of('de-DE').ask(q),
      'Was kann fliegen? Baum, Vogel oder Haus?',
    );
    final es = books['es-ES']!;
    Phrase e(String t) => es.phrases.firstWhere((p) => p.text == t);
    expect(
      QuizLines.of('es-ES').ask(
        QuizQuestion(const Ask.prop(Prop.animal), [
          e('casa'),
          e('árbol'),
          e('oso'),
        ], e('oso')),
      ),
      '¿Cuál es un animal? ¿casa, árbol u oso?',
    );
  });

  test('weights must differ clearly: 5x and 3 kg', () {
    bool heavier(double a, double b) => clearlyMore(a, b, bySize: false);
    expect(heavier(0.2, 0.02), isFalse); // scarf, mouse
    expect(heavier(4, 0.2), isTrue); // cat, scarf
    expect(heavier(3, 0.5), isFalse); // drum, book: only 2.5 kg more
    expect(heavier(1200, 500), isFalse); // car, horse: not 5x
    expect(heavier(12000, 1200), isTrue); // bus, car
  });

  test('questions are fair, in every language, for many rounds', () {
    for (final b in books.values) {
      bool similar(Phrase x, Phrase y) => soundsSimilar(comparer, b.lang, x, y);
      final firstWorlds = [for (var w = 0; w < 3; w++) ...b.world(w)];
      final kinds = <String>{};
      for (var seed = 0; seed < 25; seed++) {
        for (final pool in [firstWorlds, b.phrases]) {
          final round = makeRound(
            pool,
            facts,
            math.Random(seed),
            similar: similar,
          );
          expect(round, hasLength(8), reason: '${b.lang} seed $seed');
          expect(round.map((q) => q.answer.text).toSet(), hasLength(8));
          expect(round.map((q) => q.ask).toSet(), hasLength(8));
          for (final q in round) {
            expectFair(q, similar);
            kinds.add(q.ask.toString());
          }
        }
      }
      // all kinds of questions come up
      expect(kinds, hasLength(Ask.all.length), reason: b.lang);
    }
  });

  test('an answer counts only when it is clearly one of the words', () {
    final b = books['de-DE']!;
    Phrase w(String t) => b.phrases.firstWhere((p) => p.text == t);
    final o = [w('Baum'), w('Vogel'), w('Haus')];
    String ipa(String t) => w(t).ipa.replaceAll('/', '');
    expect(heardOption(comparer, o, ipa('Vogel'), 'de-DE'), w('Vogel'));
    expect(heardOption(comparer, o, ipa('Baum'), 'de-DE'), w('Baum'));
    // "der Vogel"
    expect(
      heardOption(comparer, o, 'deːɐ̯${ipa('Vogel')}', 'de-DE'),
      w('Vogel'),
    );
    expect(heardOption(comparer, o, '', 'de-DE'), isNull);
    expect(heardOption(comparer, o, ipa('Schmetterling'), 'de-DE'), isNull);
    expect(heardOption(comparer, o, 'pst', 'de-DE'), isNull);
    // other words are not one of the three, unless they sound alike
    // (Kuh for Schuh)
    final food = [w('Schuh'), w('Apfel'), w('Bus')];
    final taken = [
      for (final other in b.phrases)
        if (!food.contains(other))
          if (heardOption(comparer, food, ipa(other.text), 'de-DE')
              case final got?)
            if (!soundsSimilar(comparer, 'de-DE', got, other))
              '${other.text} -> ${got.text}',
    ];
    expect(taken, isEmpty);
  });

  test('Spanish: "u" before an o sound', () {
    final es = books['es-ES']!;
    Phrase e(String t) => es.phrases.firstWhere((p) => p.text == t);
    final q = QuizQuestion(const Ask.prop(Prop.plant), [
      e('casa'),
      e('oso'),
      e('hoja'),
    ], e('hoja'));
    expect(QuizLines.of('es-ES').ask(q), endsWith('oso u hoja?'));
  });

  test('stars of a round', () {
    expect(quizStars(8, 8), 3);
    expect(quizStars(6, 8), 2);
    expect(quizStars(4, 8), 1);
    expect(quizStars(3, 8), 0);
  });

  test('sizes and weights read roughly', () {
    expect(formatSize(30, 'de'), '≈ 30 cm');
    expect(formatSize(1.5, 'de'), '≈ 1,5 cm');
    expect(formatSize(1200, 'en'), '≈ 12 m');
    expect(formatSize(100000, 'en'), '≈ 1 km');
    expect(formatWeight(0.15, 'de'), '≈ 150 g');
    expect(formatWeight(190, 'de'), '≈ 190 kg');
    expect(formatWeight(12000, 'de'), '≈ 12 t');
    expect(formatWeight(0.0001, 'de'), '< 1 g');
    expect(formatWeight(3500, 'de'), '≈ 3,5 t');
  });

  group('a round with fake devices', () {
    late PhraseBook book;
    Phrase w(String t) => book.phrases.firstWhere((p) => p.text == t);
    String ipa(String t) => w(t).ipa.replaceAll('/', '');
    final lines = QuizLines.of('de-DE');

    setUp(() => book = books['de-DE']!);

    List<QuizQuestion> three() => [
      QuizQuestion(const Ask.prop(Prop.flies), [
        w('Baum'),
        w('Vogel'),
        w('Haus'),
      ], w('Vogel')),
      QuizQuestion(const Ask.prop(Prop.eat), [
        w('Schuh'),
        w('Apfel'),
        w('Bus'),
      ], w('Apfel')),
      QuizQuestion(const Ask.extreme(Extreme.biggest), [
        w('Maus'),
        w('Elefant'),
        w('Ei'),
      ], w('Elefant')),
    ];

    /// The child's answers, one per recording (the last one repeats).
    Future<(FakeDevices, Progress, Finder)> play(
      WidgetTester t,
      List<String> answers, {
      List<Child>? child,
      bool fixed = true,
      void Function(FakeDevices dev)? prepare,
      FakeQuizReports? reports,
      bool reportsOn = true,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final progress = await Progress.load();
      if (reports != null && reportsOn) await progress.setQuizReports(true);
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
      final rec = FakeRecognizer(
        () => answers[(n++).clamp(0, answers.length - 1)],
      );
      final app = AppState(
        rec,
        comparer,
        progress,
        book,
        io: dev.io,
        facts: facts,
        quizReports: reports,
      );
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(navigatorKey: nav, home: const Scaffold()),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => QuizScreen(
            app: app,
            round: fixed ? three() : null,
            info: () async => {'phone': 'test'},
          ),
        ),
      );
      await t.pump();
      await t.pump();
      return (dev, progress, find.byType(AlertDialog));
    }

    Future<void> until(
      WidgetTester t,
      bool Function() done,
      IoLog log, {
      Duration limit = const Duration(seconds: 120),
    }) async {
      const step = Duration(milliseconds: 50);
      for (var e = Duration.zero; e < limit; e += step) {
        if (done()) return;
        await t.pump(step);
      }
      fail('timed out\n$log');
    }

    /// Checks the devices, then closes the final dialog (and the quiz).
    Future<void> expectClean(WidgetTester t, IoLog log) async {
      expect(log.soundsWhileRecording(), isEmpty, reason: '$log');
      expect(log.problems, isEmpty, reason: '$log');
      for (var i = 0; i < 60; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await t.tap(find.text('Great'));
      }
      await t.pumpWidget(const SizedBox());
      for (var i = 0; i < 60; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('all right: by itself to the end, three stars', (t) async {
      final (dev, progress, dialog) = await play(t, [
        ipa('Vogel'),
        ipa('Apfel'),
        ipa('Elefant'),
      ]);
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      final said = dev.log.started('tts');
      expect(said, contains(lines.ask(three()[0])));
      expect(said, contains(lines.ask(three()[2])));
      expect(said.where((s) => s.startsWith('Die Antwort')), isEmpty);
      expect(dev.log.started('mic'), hasLength(3));
      expect(find.text('3 / 3'), findsOneWidget);
      expect(progress.quizBest('de-DE'), 3);
      await expectClean(t, dev.log);
    });

    testWidgets('a wrong answer: the phone says the right one', (t) async {
      final (dev, progress, dialog) = await play(t, [
        ipa('Haus'),
        ipa('Apfel'),
        ipa('Elefant'),
      ]);
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      expect(dev.log.started('tts'), contains(lines.answerIs('Vogel')));
      expect(find.text('2 / 3'), findsOneWidget);
      expect(progress.quizBest('de-DE'), 1);
      await expectClean(t, dev.log);
    });

    testWidgets('not understood: asked once more, then the answer', (t) async {
      final (dev, _, dialog) = await play(t, [
        ipa('Schmetterling'), // not one of the three: once more
        ipa('Vogel'),
        ipa('Krokodil'), // twice: the answer, on to the next
        ipa('Schmetterling'),
        ipa('Elefant'),
      ]);
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      final said = dev.log.started('tts');
      expect(said.where((s) => s == lines.notUnderstood), hasLength(2));
      expect(said, contains(lines.answerIs('Apfel')));
      expect(said.where((s) => s == lines.ask(three()[0])), hasLength(2));
      expect(dev.log.started('mic'), hasLength(5));
      expect(find.text('2 / 3'), findsOneWidget);
      await expectClean(t, dev.log);
    });

    testWidgets('silence: waits for a tap, then goes on', (t) async {
      final (dev, _, dialog) = await play(
        t,
        [ipa('Vogel'), ipa('Apfel'), ipa('Elefant')],
        child: [Child.silent, Child.speaks],
      );
      await until(
        t,
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        dev.log,
      );
      for (var i = 0; i < 100; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(dev.log.started('mic'), hasLength(1));
      expect(dev.mic.recording, isFalse);
      await t.tap(find.byTooltip('Speak'));
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      expect(find.text('3 / 3'), findsOneWidget);
      await expectClean(t, dev.log);
    });

    testWidgets('to the background while listening: the mic goes off', (
      t,
    ) async {
      final (dev, _, _) = await play(t, [ipa('Vogel')]);
      await until(t, () => dev.mic.recording, dev.log);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(dev.mic.recording, isFalse);
      expect(dev.log.started('mic'), hasLength(1));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      for (var i = 0; i < 100; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      // goes on with a tap only
      expect(dev.log.started('mic'), hasLength(1));
      await expectClean(t, dev.log);
    });

    testWidgets('the mic does not start: a message, then a tap works', (
      t,
    ) async {
      final (dev, _, dialog) = await play(t, [
        ipa('Vogel'),
        ipa('Apfel'),
        ipa('Elefant'),
      ], prepare: (d) => d.mic.startThrows = true);
      await until(
        t,
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        dev.log,
      );
      expect(find.byTooltip('Speak'), findsOneWidget); // not listening
      dev.mic.startThrows = false;
      for (var i = 0; i < 100; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.tap(find.byTooltip('Speak'));
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      expect(find.text('3 / 3'), findsOneWidget);
      await expectClean(t, dev.log);
    });

    testWidgets('to the background while "once more": nothing goes on', (
      t,
    ) async {
      final (dev, _, _) = await play(t, [ipa('Schmetterling')]);
      await until(
        t,
        () => dev.log.started('tts').contains(lines.notUnderstood),
        dev.log,
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      for (var i = 0; i < 200; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(dev.log.started('mic'), hasLength(1));
      expect(dev.log.started('tts').last, lines.notUnderstood);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await expectClean(t, dev.log);
    });

    testWidgets('a random round: eight questions from the open worlds', (
      t,
    ) async {
      final (dev, _, _) = await play(t, [''], fixed: false);
      await until(t, () => dev.mic.recording, dev.log);
      final asked = dev.log.started('tts').first;
      final first = [for (var w = 0; w < 3; w++) ...book.world(w)];
      final named = first.where((p) => asked.contains(p.text)).length;
      expect(named, greaterThanOrEqualTo(3), reason: asked);
      expect(find.byType(Container), findsWidgets);
      await expectClean(t, dev.log);
    });

    final bug = find.byTooltip('Send this question to the developer');

    testWidgets('quiz reports off: no 🐞, nothing sent', (t) async {
      final reports = FakeQuizReports();
      final (dev, _, dialog) = await play(
        t,
        [ipa('Haus'), ipa('Apfel'), ipa('Elefant')],
        reports: reports,
        reportsOn: false,
      );
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      expect(bug, findsNothing);
      expect(reports.sent, isEmpty);
      await expectClean(t, dev.log);
    });

    testWidgets('🐞 sends the question with the recording, the result waits', (
      t,
    ) async {
      final reports = FakeQuizReports();
      final (dev, _, dialog) = await play(t, [
        ipa('Haus'),
        ipa('Apfel'),
        ipa('Elefant'),
      ], reports: reports);
      expect(bug, findsOneWidget);
      // nothing to send before the first answer
      RoundButton button() => t.widget<RoundButton>(
        find.ancestor(of: bug, matching: find.byType(RoundButton)),
      );
      expect(button().onTap, isNull);
      await until(
        t,
        () => dev.log.started('tts').contains(lines.answerIs('Vogel')),
        dev.log,
      );
      await t.tap(bug);
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(reports.sent, hasLength(1));
      final r = reports.sent.single;
      expect(r.answer, 'Vogel');
      expect(r.asked, lines.ask(three()[0]));
      expect(r.options.map((o) => o.text), ['Baum', 'Vogel', 'Haus']);
      expect(r.tries, hasLength(1));
      final tr = r.tries.single;
      expect(tr.said, 'Haus');
      expect(tr.speech, isTrue);
      expect(tr.heard, ipa('Haus'));
      expect(tr.pcm.length, greaterThan(16000)); // the child's word
      expect(tr.scores.firstWhere((s) => s.option == 'Haus').score, 1.0);
      final wav = pcmWav(tr.pcm);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(r.toJson()['tries'][0]['audio'], isA<String>());
      expect(find.text('Sent. Thank you!'), findsOneWidget);
      // the result stays until a tap; sent once
      for (var i = 0; i < 100; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(dev.log.started('mic'), hasLength(1));
      await t.tap(bug);
      await t.pump();
      expect(reports.sent, hasLength(1));
      await t.tap(find.byTooltip('Speak'));
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      expect(reports.sent, hasLength(1));
      await expectClean(t, dev.log);
    });

    testWidgets('🐞 after "once more": both tries; offline: a message', (
      t,
    ) async {
      final reports = FakeQuizReports()..result = SendResult.later;
      final (dev, _, dialog) = await play(t, [
        ipa('Schmetterling'),
        ipa('Krokodil'),
        ipa('Apfel'),
        ipa('Elefant'),
      ], reports: reports);
      await until(
        t,
        () => dev.log.started('tts').contains(lines.answerIs('Vogel')),
        dev.log,
      );
      await t.tap(bug);
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Not sent. Is there internet?'), findsOneWidget);
      expect(reports.sent.single.tries.map((t) => t.said), [null, null]);
      expect(reports.sent.single.tries.map((t) => t.heard), [
        ipa('Schmetterling'),
        ipa('Krokodil'),
      ]);
      // not sent: can be tried again
      reports.result = SendResult.done;
      await t.tap(bug);
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(reports.sent, hasLength(2));
      await t.tap(find.byTooltip('Speak'));
      await until(t, () => dialog.evaluate().isNotEmpty, dev.log);
      await expectClean(t, dev.log);
    });

    testWidgets('a picture says its word', (t) async {
      final (dev, _, _) = await play(t, [ipa('Vogel')], child: [Child.silent]);
      await until(
        t,
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        dev.log,
      );
      await t.tap(find.text('Baum'));
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      expect(dev.log.started('tts').last, 'Baum');
      await expectClean(t, dev.log);
    });
  });
}

class FakeQuizReports implements QuizReportSender {
  final sent = <QuizReport>[];
  SendResult result = SendResult.done;

  @override
  Future<SendResult> send(QuizReport report) async {
    sent.add(report);
    return result;
  }
}
