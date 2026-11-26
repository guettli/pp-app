// Every game says what to do before its first word: tap or speak.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/listen/listen_rules.dart';
import 'package:phoneme_party/game/play_screen.dart';
import 'package:phoneme_party/listen/listen_screen.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:phoneme_party/quiz/facts.dart';
import 'package:phoneme_party/quiz/quiz_lines.dart';
import 'package:phoneme_party/quiz/quiz_screen.dart';
import 'package:phoneme_party/read/read_aloud_screen.dart';
import 'package:phoneme_party/spell/spell_rules.dart';
import 'package:phoneme_party/spell/spell_screen.dart';
import 'package:phoneme_party/ui/intros.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  late PhonemeComparer comparer;
  late PhraseBook book;
  setUpAll(() {
    comparer = PhonemeComparer.fromJson(
      File('assets/panphon/panphon_features.json').readAsStringSync(),
    );
    final raw = File('assets/phrases/de-DE.json').readAsStringSync();
    book = PhraseBook('de-DE', [
      for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        Phrase.fromJson(j),
    ]);
  });

  Phrase w(String text) => book.phrases.firstWhere((p) => p.text == text);

  test('an intro for every game in every language', () {
    for (final lang in ['de-DE', 'en-GB', 'fr-FR', 'it-IT', 'es-ES']) {
      for (final g in GameIntro.values) {
        expect(introLine(g, lang), isNotEmpty);
      }
    }
    expect(introLine(GameIntro.sayWord, 'xx-XX'), contains('say'));
  });

  test('"nothing heard" is said in every language, two different lines', () {
    final en = notHeardLine('en-GB', again: true);
    for (final lang in ['de-DE', 'fr-FR', 'it-IT', 'es-ES']) {
      final again = notHeardLine(lang, again: true);
      final tap = notHeardLine(lang, again: false);
      expect(again, isNot(en), reason: lang);
      expect(tap, isNot(again), reason: lang);
    }
    expect(notHeardLine('xx-XX', again: true), en);
  });

  /// Shows [screen] and lets it run [seconds]; the devices for checks.
  Future<FakeDevices> run(
    WidgetTester t,
    Widget Function(AppState app) screen, {
    int seconds = 8,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final progress = await Progress.load();
    final t0 = t.binding.clock.now();
    final log = IoLog(() => t.binding.clock.now().difference(t0));
    final dev = FakeDevices(log, child: () => Child.silent);
    final app = AppState(
      FakeRecognizer(() => '', log: log),
      comparer,
      progress,
      book,
      io: dev.io,
    );
    await t.pumpWidget(MaterialApp(home: screen(app)));
    for (var i = 0; i < seconds * 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    return dev;
  }

  Future<void> close(WidgetTester t, FakeDevices dev) async {
    expect(dev.log.soundsWhileRecording(), isEmpty, reason: '${dev.log}');
    expect(dev.log.problems, isEmpty, reason: '${dev.log}');
    await t.pumpWidget(const SizedBox());
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('quiz: say the word, then the question, then the mic', (t) async {
    final q = QuizQuestion(Ask.startsLike(w('Katze')), [
      w('Ei'),
      w('Kuh'),
      w('Bett'),
    ], w('Kuh'));
    final dev = await run(
      t,
      (app) => QuizScreen(app: app, sounds: true, round: [q]),
    );
    expect(dev.log.started('tts').take(2), [
      introLine(GameIntro.sayWord, 'de-DE'),
      QuizLines.of('de-DE').ask(q),
    ]);
    expect(dev.log.started('mic'), isNotEmpty);
    await close(t, dev);
  });

  testWidgets('world: say it after me, then the word, then the mic', (t) async {
    final dev = await run(t, (app) => PlayScreen(app: app, world: 0));
    expect(dev.log.started('tts').take(2), [
      introLine(GameIntro.repeat, 'de-DE'),
      book.world(0).first.text,
    ]);
    // the microphone opens with the word, not during the intro
    final intro = dev.log.intervals('tts').first;
    final mic = dev.log.intervals('mic').first;
    expect(mic.from, greaterThanOrEqualTo(intro.to!));
    // (the world opens the mic while it says the word, on purpose: the
    // echo gate; so not close(), which forbids any sound while recording)
    expect(dev.log.problems, isEmpty, reason: '${dev.log}');
    await t.pumpWidget(const SizedBox());
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('listen: tap the picture, then the word', (t) async {
    final dev = await run(
      t,
      (app) => ListenScreen(
        app: app,
        round: [
          ListenQuestion(w('Kuh'), [w('Ei'), w('Kuh'), w('Ohr'), w('Bett')]),
        ],
      ),
    );
    expect(dev.log.started('tts'), [
      introLine(GameIntro.tapPicture, 'de-DE'),
      'Kuh',
    ]);
    await close(t, dev);
  });

  testWidgets('word to picture: the intro only, the word is read', (t) async {
    final dev = await run(
      t,
      (app) => ListenScreen(
        app: app,
        reading: true,
        round: [
          ListenQuestion(w('Kuh'), [w('Ei'), w('Kuh'), w('Ohr'), w('Bett')]),
        ],
      ),
    );
    expect(dev.log.started('tts'), [
      introLine(GameIntro.readTapPicture, 'de-DE'),
    ]);
    await close(t, dev);
  });

  testWidgets('letters: tap the letters, then the word', (t) async {
    final dev = await run(
      t,
      (app) => SpellScreen(
        app: app,
        round: [
          SpellPuzzle(w('Ei'), const ['E', 'i'], const ['i', 'E']),
        ],
      ),
    );
    expect(dev.log.started('tts'), [
      introLine(GameIntro.tapLetters, 'de-DE'),
      'Ei',
    ]);
    await close(t, dev);
  });

  testWidgets('read aloud: read it out, then the mic (not during it)', (
    t,
  ) async {
    final dev = await run(
      t,
      (app) => ReadAloudScreen(app: app, round: [w('Ei')]),
    );
    expect(
      dev.log.started('tts').first,
      introLine(GameIntro.readAloud, 'de-DE'),
    );
    expect(dev.log.started('mic'), hasLength(1));
    await close(t, dev);
  });

  testWidgets('quiz: the intro once, not before the second question', (
    t,
  ) async {
    final q1 = QuizQuestion(Ask.startsLike(w('Katze')), [
      w('Ei'),
      w('Kuh'),
      w('Bett'),
    ], w('Kuh'));
    final q2 = QuizQuestion(Ask.startsLike(w('Maus')), [
      w('Ei'),
      w('Mond'),
      w('Bett'),
    ], w('Mond'));
    final dev = await run(
      t,
      (app) => QuizScreen(app: app, sounds: true, round: [q1, q2]),
      seconds: 40,
    );
    final intro = introLine(GameIntro.sayWord, 'de-DE');
    expect(dev.log.started('tts').where((s) => s == intro), hasLength(1));
    await close(t, dev);
  });

  testWidgets('listen: a tap during the intro does nothing', (t) async {
    final dev = await run(
      t,
      (app) => ListenScreen(
        app: app,
        round: [
          ListenQuestion(w('Kuh'), [w('Ei'), w('Kuh'), w('Ohr'), w('Bett')]),
        ],
      ),
      seconds: 0,
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(dev.speaker.speaking, isTrue);
    await t.tap(find.byKey(const ValueKey('listen-option-0'))); // wrong
    for (var i = 0; i < 100; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(dev.log.started('tts'), [
      introLine(GameIntro.tapPicture, 'de-DE'),
      'Kuh',
    ]);
    await close(t, dev);
  });

  testWidgets('read aloud: 🎤 and ➡ wait for the intro', (t) async {
    final dev = await run(
      t,
      (app) => ReadAloudScreen(app: app, round: [w('Ei'), w('Bett')]),
      seconds: 0,
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(dev.speaker.speaking, isTrue);
    await t.tap(find.byTooltip('Speak'));
    await t.tap(find.byIcon(Icons.arrow_forward_rounded));
    await t.pump(const Duration(milliseconds: 50));
    expect(dev.speaker.speaking, isTrue);
    expect(dev.mic.recording, isFalse);
    for (var i = 0; i < 100; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(dev.log.started('mic'), hasLength(1));
    expect(find.text('Ei'), findsOneWidget);
    await close(t, dev);
  });

  testWidgets('quiz: paused during the intro, it comes again', (t) async {
    final q = QuizQuestion(Ask.startsLike(w('Katze')), [
      w('Ei'),
      w('Kuh'),
      w('Bett'),
    ], w('Kuh'));
    final dev = await run(
      t,
      (app) => QuizScreen(app: app, sounds: true, round: [q]),
      seconds: 0,
    );
    await t.pump(const Duration(milliseconds: 300));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(const Duration(milliseconds: 500));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.byTooltip('Speak'));
    for (var i = 0; i < 100; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final intro = introLine(GameIntro.sayWord, 'de-DE');
    expect(dev.log.started('tts').where((s) => s == intro), hasLength(2));
    await close(t, dev);
  });
}
