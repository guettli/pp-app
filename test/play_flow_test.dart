// The whole play screen with fake devices: what happens after the child has
// spoken, without anyone tapping, and when the child or the phone gets in
// the way. The fake clock runs the timers, so a world takes a second.
//
// Every test runs twice: with flutter_tts as on Android (stop() ends a
// running speak()) and as on iOS (it does not; the app's timeout must).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/game/rules.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/game.dart';

late PhonemeComparer comparer;
late PhraseBook book;

/// IPA the fake recognizer answers for a word said badly (0 stars).
const mumble = 'ŋŋ';

/// The fakes of one test.
class Fakes {
  Fakes(this.dev, this.rec);
  final FakeDevices dev;
  final FakeRecognizer rec;
}

/// Opens world 0 with fakes. [answer]: what the fake recognizer hears
/// (default: the word the phone said, 3 stars).
Future<(Game, Fakes)> start(
  WidgetTester t, {
  required bool iosTts,
  String Function(Game g)? answer,
  Child Function()? child,
  bool fromMemory = true,
  bool permission = true,
  bool ttsHangs = false,
  Duration recognizing = Duration.zero,
  bool listensWhileSpeaking = true,
  Duration micStartup = Duration.zero,
  Duration micLatency = Duration.zero,
  FakeQuizReports? reports,
}) async {
  SharedPreferences.setMockInitialValues({});
  final progress = await Progress.load();
  if (reports != null) await progress.setQuizReports(true);
  final t0 = t.binding.clock.now();
  final log = IoLog(() => t.binding.clock.now().difference(t0));
  final dev = FakeDevices(
    log,
    child: child,
    fromMemory: fromMemory,
    ttsCompletesOnStop: !iosTts,
    listensWhileSpeaking: listensWhileSpeaking,
  );
  dev.mic.permission = permission;
  dev.mic.startup = micStartup;
  dev.mic.latency = micLatency;
  dev.speaker.hang = ttsHangs;
  // the recognizer is asked only after the game exists
  late final Game game;
  final rec = FakeRecognizer(
    () => answer == null ? game.current.ipa : answer(game),
    delay: recognizing,
    log: log,
  );
  final app = AppState(
    rec,
    comparer,
    progress,
    book,
    io: dev.io,
    quizReports: reports,
  );
  game = await Game.open(t, app, log);
  return (game, Fakes(dev, rec));
}

void main() {
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

  test('the fake answers score as intended', () {
    for (final p in book.world(0)) {
      expect(scorePhrase(comparer, p, p.ipa, 'de-DE').stars, 3, reason: p.text);
      expect(
        scorePhrase(comparer, p, mumble, 'de-DE').stars,
        0,
        reason: p.text,
      );
    }
  });

  for (final ios in [false, true]) {
    group(ios ? 'iOS TTS:' : 'Android TTS:', () => flows(ios));
  }

  testWidgets('🐞 sends the word with the recording and what was heard', (
    t,
  ) async {
    final reports = FakeQuizReports();
    final (g, _) = await start(
      t,
      iosTts: false,
      answer: (_) => mumble,
      reports: reports,
    );
    final bug = find.byTooltip('Send to the developer');
    expect(bug, findsOneWidget);
    await g.until(() => g.recordings == 1 && g.praise.isNotEmpty);
    final word = g.words.first;
    await t.tap(bug);
    await t.pump();
    await t.tap(find.text('Send'));
    await g.wait(const Duration(seconds: 1));
    final r = reports.sent.single;
    expect(r.question, 'world 1: ${word.text}');
    expect(r.answer, word.text);
    final tr = r.tries.single;
    expect(tr.heard, mumble);
    expect(tr.said, '0');
    expect(tr.pcm.length, greaterThan(16000));
    // the game waits for a tap
    final mics = g.recordings;
    await g.wait(const Duration(seconds: 10));
    expect(g.recordings, mics);
  });

  for (final (w, h, scale) in [
    (360.0, 640.0, 1.6),
    (640.0, 360.0, 1.0),
    (640.0, 360.0, 1.6),
  ]) {
    testWidgets('the world-done dialog fits a ${w.toInt()}x${h.toInt()} phone '
        'at text $scale', (t) async {
      t.view.physicalSize = Size(w, h);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final (g, _) = await start(t, iosTts: false);
      await g.until(
        () => g.dialog.evaluate().isNotEmpty,
        limit: const Duration(minutes: 3),
        reason: 'world-done dialog',
      );
      await g.wait(const Duration(seconds: 3));
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(
        find.byIcon(Icons.check_rounded),
        50,
        scrollable: find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byIcon(Icons.check_rounded).hitTestable(), findsOneWidget);
    });
  }
}

void flows(bool ios) {
  // The world-done praise comes this long after the dialog opened.
  const donePraise = Duration(milliseconds: 1400);
  // Longer than any wait the game has by itself (TTS timeout, advance).
  const quiet = Duration(seconds: 20);

  testWidgets('a whole world goes by itself, nothing is recorded but the '
      'child', (t) async {
    final (g, f) = await start(t, iosTts: ios);
    await g.until(
      () => g.dialog.evaluate().isNotEmpty,
      limit: const Duration(minutes: 3),
      reason: 'world-done dialog',
    );
    await g.wait(donePraise * 2);
    expect(g.said, [for (final p in g.words) p.text]);
    expect(g.recordings, g.words.length);
    expect(f.rec.calls, g.words.length);
    expect(f.dev.mic.voices, greaterThan(0), reason: 'keeps the screen on');
    expect(g.replays, g.words.length, reason: 'one replay per word');
    // once per word and once for the world, never twice the same in a row
    final praise = g.praise;
    expect(praise, hasLength(g.words.length + 1));
    for (var i = 1; i < praise.length; i++) {
      expect(praise[i], isNot(praise[i - 1]));
    }
    g.expectClean();

    // the round is over: nothing starts behind the dialog
    final mics = g.recordings, players = g.replays;
    await g.wait(quiet);
    expect(g.recordings, mics);
    expect(g.replays, players);
    expect(g.dialog, findsOneWidget);
    expect(g.running, isEmpty);
  });

  testWidgets('0 stars: one more try, then on to the next word', (t) async {
    final (g, _) = await start(t, iosTts: ios, answer: (_) => mumble);
    await g.until(() => g.recordings == 2, reason: 'retry');
    expect(g.said, [g.words[0].text, g.words[0].text]);
    expect(g.showsWord(1), isTrue);
    await g.until(() => g.recordings == 3, reason: 'next word');
    expect(g.said.last, g.words[1].text);
    expect(g.showsWord(2), isTrue);
    g.expectClean();
  });

  testWidgets('nothing heard: waits for a tap', (t) async {
    final (g, f) = await start(t, iosTts: ios, child: () => Child.silent);
    await g.until(
      () => g.recordings == 1 && g.log.intervals('mic').single.to != null,
    );
    await g.wait(const Duration(milliseconds: 500));
    expect(find.byType(SnackBar), findsOneWidget);
    await g.wait(quiet);
    expect(g.recordings, 1);
    expect(f.rec.calls, 0);
    expect(g.replays, 0);
    expect(f.dev.mic.voices, 0, reason: 'the screen may go off');
    await g.tap('Speak');
    await g.until(() => g.recordings == 2);
    expect(g.said, [g.words[0].text, g.words[0].text]);
  });

  testWidgets('no microphone permission: nothing is said or recorded', (
    t,
  ) async {
    final (g, _) = await start(t, iosTts: ios, permission: false);
    await g.wait(const Duration(milliseconds: 500));
    expect(find.byType(SnackBar), findsOneWidget);
    await g.wait(quiet);
    expect(g.recordings, 0);
    expect(g.said, isEmpty);
  });

  testWidgets('the child taps the mic to finish early', (t) async {
    final (g, f) = await start(t, iosTts: ios);
    await g.until(() => g.recordings == 1);
    await g.wait(const Duration(milliseconds: 1200)); // after the speech
    await g.tap('Your turn!');
    expect(g.log.intervals('mic').single.to, isNotNull);
    await g.until(() => g.praise.isNotEmpty);
    expect(f.rec.calls, 1);
    await g.until(() => g.recordings == 2);
    expect(g.said.last, g.words[1].text);
    g.expectClean();
  });

  for (final how in [Child.micBreaks, Child.micEnds]) {
    testWidgets('the recording ends early (${how.name}): what was said is '
        'still scored', (t) async {
      final (g, f) = await start(t, iosTts: ios, child: () => how);
      await g.until(() => g.log.intervals('mic').firstOrNull?.to != null);
      // right away, not only when the recording time limit is up
      await g.wait(const Duration(milliseconds: 300));
      expect(f.rec.calls, 1);
      await g.until(() => g.recordings == 2, reason: 'goes on');
      expect(g.said.last, g.words[1].text);
      g.expectClean();
    });
  }

  testWidgets('background during the praise: everything stops, and it goes '
      'on when the app is back', (t) async {
    final (g, _) = await start(t, iosTts: ios);
    await g.until(() => g.praise.isNotEmpty, reason: 'praise');
    await g.lifecycle(AppLifecycleState.paused);
    expect(g.running, isEmpty);
    await g.wait(quiet);
    expect(g.recordings, 1);
    expect(g.running, isEmpty);
    await g.lifecycle(AppLifecycleState.resumed);
    await g.until(() => g.recordings == 2, reason: 'next word after resume');
    expect(g.said.last, g.words[1].text);
    g.expectClean();
  });

  testWidgets('background while listening: the recording is dropped', (
    t,
  ) async {
    final (g, f) = await start(t, iosTts: ios);
    await g.until(() => f.dev.mic.recording);
    await g.wait(const Duration(milliseconds: 800)); // the child is talking
    await g.lifecycle(AppLifecycleState.paused);
    expect(f.dev.mic.recording, isFalse);
    await g.wait(quiet);
    expect(f.rec.calls, 0, reason: 'never scored');
    expect(g.praise, isEmpty);
    await g.lifecycle(AppLifecycleState.resumed);
    await g.wait(quiet);
    expect(g.recordings, 1, reason: 'waits for a tap');
  });

  testWidgets('a child who answers at once is heard from the first sound, '
      'the phone is not', (t) async {
    final (g, f) = await start(
      t,
      iosTts: ios,
      child: () => Child.speaksAtOnce,
      // the mic is up before the end of "Ei" (420 ms), and its audio comes
      // late, so the end of the phrase arrives after speak() completed
      micStartup: const Duration(milliseconds: 200),
      micLatency: const Duration(milliseconds: 100),
    );
    await g.until(() => f.rec.calls == 1);
    // all of the 0.7 s answer (a gate waiting its 300 ms would cut 0.15 s)
    expect(f.rec.lastSpeechSeconds, greaterThanOrEqualTo(0.65));
    await g.until(() => g.recordings == 2, reason: 'goes on');
    g.expectClean(); // and none of the phrase (FakeRecognizer checks)
  });

  testWidgets('a short phrase, done before the mic is up: the answer is '
      'still heard', (t) async {
    final (g, f) = await start(
      t,
      iosTts: ios,
      child: () => Child.speaksAtOnce,
      micStartup: const Duration(milliseconds: 500), // as on the A80
    );
    await g.until(() => f.rec.calls == 1);
    expect(f.rec.lastSpeechSeconds, greaterThanOrEqualTo(0.5));
    await g.until(() => g.recordings == 2, reason: 'goes on');
    g.expectClean();
  });

  testWidgets('the mic fails to start while the phone speaks: try again, '
      'and the mic stays off', (t) async {
    final (g, f) = await start(t, iosTts: ios);
    // the first start already ran: fail from the second word on
    await g.until(() => f.rec.calls == 1);
    f.dev.mic.startThrows = true;
    await g.until(() => g.said.length == 2);
    await g.until(() => find.byType(SnackBar).evaluate().isNotEmpty);
    await g.wait(quiet);
    expect(f.dev.mic.recording, isFalse);
    expect(f.rec.calls, 1);
    f.dev.mic.startThrows = false;
    await g.tap('Speak');
    await g.until(() => f.rec.calls == 2, reason: 'works again');
    await g.until(() => g.recordings == 3, reason: 'goes on');
    g.expectClean();
  });

  testWidgets('background while the phone speaks and the mic is open: '
      'all off, nothing scored', (t) async {
    final (g, f) = await start(t, iosTts: ios);
    await g.until(() => f.dev.mic.recording && f.dev.speaker.speaking);
    await g.lifecycle(AppLifecycleState.paused);
    await g.wait(const Duration(seconds: 1));
    expect(f.dev.mic.recording, isFalse);
    expect(f.dev.speaker.speaking, isFalse);
    await g.wait(quiet);
    expect(f.rec.calls, 0);
    expect(f.dev.mic.recording, isFalse);
    await g.lifecycle(AppLifecycleState.resumed);
    await g.tap('Speak');
    await g.until(() => f.rec.calls == 1, reason: 'works again');
    await g.until(() => g.recordings == 3, reason: 'goes on');
    g.expectClean();
  });

  testWidgets('the mic stream ends while the phone speaks: no waiting for '
      'the time limit', (t) async {
    final (g, f) = await start(t, iosTts: ios);
    f.dev.mic.endsAfter = const Duration(milliseconds: 100);
    await g.until(() => g.log.intervals('tts').firstOrNull?.to != null);
    final spoken = g.log.intervals('tts').first.to!;
    await g.until(() => find.byType(SnackBar).evaluate().isNotEmpty);
    expect(g.log.now() - spoken, lessThan(const Duration(seconds: 1)));
    expect(f.rec.calls, 0, reason: 'nothing of the child was heard');
    f.dev.mic.endsAfter = null;
    await g.wait(quiet);
  });

  testWidgets('a mic that starts slowly, the app in the background meanwhile: '
      'its late stop does not end the next recording', (t) async {
    final (g, f) = await start(
      t,
      iosTts: ios,
      micStartup: const Duration(milliseconds: 800),
    );
    await g.wait(const Duration(milliseconds: 100)); // the mic is starting
    await g.lifecycle(AppLifecycleState.paused);
    await g.lifecycle(AppLifecycleState.resumed);
    await g.tap('Speak');
    await g.until(() => f.rec.calls == 1, reason: 'the new round is scored');
    expect(f.rec.lastSpeechSeconds, greaterThan(0.5));
    await g.until(() => g.recordings == 3, reason: 'goes on');
    g.expectClean();
  });

  testWidgets('without listening while speaking (iOS) the mic opens after '
      'the phrase, and a quick answer is not even heard', (t) async {
    final (g, f) = await start(
      t,
      iosTts: ios,
      child: () => Child.speaksAtOnce,
      listensWhileSpeaking: false,
      micStartup: const Duration(milliseconds: 500), // as on the A80
    );
    await g.until(() => g.log.intervals('mic').firstOrNull?.to != null);
    // the mic opened 0.75 s after the phrase: 0.1 s of the answer is left
    expect(f.rec.calls, 0);
    g.expectClean();
  });

  testWidgets('background while listening, and the TTS fails to stop: the '
      'mic still goes off', (t) async {
    final (g, f) = await start(t, iosTts: ios);
    await g.until(() => f.dev.mic.recording);
    f.dev.speaker.failStop = true;
    await g.lifecycle(AppLifecycleState.paused);
    await g.wait(const Duration(seconds: 1));
    expect(f.dev.mic.recording, isFalse);
    expect(f.rec.calls, 0);
    f.dev.speaker.failStop = false; // let the screen close cleanly
  });

  testWidgets('background while recognizing: the result is dropped', (t) async {
    final (g, f) = await start(
      t,
      iosTts: ios,
      recognizing: const Duration(seconds: 2),
    );
    await g.until(() => f.rec.calls == 1);
    await g.lifecycle(AppLifecycleState.paused);
    await g.wait(quiet);
    expect(g.praise, isEmpty);
    expect(g.replays, 0);
    await g.lifecycle(AppLifecycleState.resumed);
    await g.wait(quiet);
    expect(g.recordings, 1, reason: 'waits for a tap');
    expect(g.praise, isEmpty);
  });

  testWidgets('Next during the praise skips the rest at once', (t) async {
    final (g, _) = await start(t, iosTts: ios);
    await g.until(() => g.praise.isNotEmpty);
    final said = g.praise.last;
    await g.tap('Next');
    expect(
      g.log.intervals('tts').lastWhere((i) => i.what == said).to,
      isNotNull,
      reason: 'the praise stops at once',
    );
    await g.until(() => g.recordings == 2);
    expect(g.replays, 0, reason: 'no replay of the old word');
    expect(g.said, [g.words[0].text, g.words[1].text]);
    g.expectClean();
    await g.wait(quiet); // iOS: the stopped praise times out
  });

  testWidgets('Next during the praise of the last word: the dialog opens '
      'once', (t) async {
    final (g, _) = await start(t, iosTts: ios);
    final last = g.words.length;
    await g.until(
      () => g.showsWord(last) && g.praise.length == last,
      limit: const Duration(minutes: 3),
    );
    await g.tap('Next');
    await g.wait(quiet);
    expect(g.dialog, findsOneWidget);
    expect(g.recordings, last);
    expect(g.running, isEmpty);
    g.expectClean();
  });

  testWidgets('the mic tapped during the praise: the word once more', (
    t,
  ) async {
    final (g, _) = await start(t, iosTts: ios);
    await g.until(() => g.praise.isNotEmpty);
    await g.tap('Speak');
    await g.until(() => g.recordings == 2);
    expect(g.said, [g.words[0].text, g.words[0].text]);
    g.expectClean();
    await g.wait(quiet); // iOS: the stopped praise times out
  });

  testWidgets('listen again during the replay, then it goes on', (t) async {
    final (g, _) = await start(t, iosTts: ios);
    await g.until(() => g.replays == 1);
    await g.tap('Listen');
    expect(g.log.intervals('replay').last.to, isNotNull);
    await g.until(() => g.said.length == 2);
    expect(g.said, [g.words[0].text, g.words[0].text]);
    await g.until(() => g.recordings == 2, reason: 'goes on afterwards');
    expect(g.said.last, g.words[1].text);
    g.expectClean();
  });

  testWidgets('funny voice tapped during the replay: plays again, then goes '
      'on', (t) async {
    final (g, _) = await start(t, iosTts: ios);
    await g.until(() => g.replays == 1);
    await g.tap('Funny voice');
    await g.wait(FakeOut.startup * 2);
    expect(g.replays, 2);
    expect(g.log.intervals('replay').first.to, isNotNull);
    await g.until(() => g.recordings == 2);
    expect(g.said.last, g.words[1].text);
    g.expectClean();
  });

  testWidgets('Next while the replay starts, then closing the screen', (
    t,
  ) async {
    final (g, f) = await start(t, iosTts: ios);
    await g.until(() => f.dev.player.starting);
    await g.tap('Next');
    await g.until(() => g.recordings == 2);
    expect(g.replays, 0, reason: 'the start was cancelled');
    g.nav.currentState!.pop();
    // fails here if the replay's wait for its end became an unhandled error
    await g.wait(const Duration(seconds: 2));
    expect(g.running, isEmpty);
  });

  testWidgets('a stuck TTS engine does not stop the game', (t) async {
    final (g, _) = await start(t, iosTts: ios, ttsHangs: true);
    await g.until(() => g.recordings == 2, limit: const Duration(minutes: 1));
    // the app waited for its timeout, stopped the engine, listened anyway
    final first = g.log.intervals('tts').first;
    expect(
      first.to! - first.from,
      greaterThanOrEqualTo(const Duration(seconds: 3)),
    );
    g.expectClean();
  });

  testWidgets('a player that cannot play from memory never gets the '
      'recording', (t) async {
    final (g, _) = await start(t, iosTts: ios, fromMemory: false);
    await g.until(() => g.recordings == 3);
    expect(g.replays, 0);
    expect(find.byTooltip('Funny voice'), findsNothing);
    g.expectClean();
  });

  testWidgets('background while the world-done dialog opens: no praise', (
    t,
  ) async {
    final (g, _) = await start(t, iosTts: ios);
    await g.until(
      () => g.dialog.evaluate().isNotEmpty,
      limit: const Duration(minutes: 3),
    );
    final praise = g.praise.length;
    await g.lifecycle(AppLifecycleState.paused);
    await g.wait(donePraise * 2);
    expect(g.praise.length, praise);
    expect(g.running, isEmpty);
  });

  testWidgets('closing the screen during the praise stops everything', (
    t,
  ) async {
    final (g, _) = await start(t, iosTts: ios);
    await g.until(() => g.praise.isNotEmpty);
    g.nav.currentState!.pop();
    await g.wait(const Duration(seconds: 1));
    expect(g.running, isEmpty);
    await g.wait(quiet);
    expect(g.recordings, 1);
  });

  testWidgets('closing the screen while listening: nothing is scored', (
    t,
  ) async {
    final (g, f) = await start(t, iosTts: ios);
    await g.until(() => f.dev.mic.recording);
    g.nav.currentState!.pop();
    await g.wait(const Duration(seconds: 1));
    expect(f.dev.mic.recording, isFalse);
    await g.wait(quiet);
    expect(f.rec.calls, 0);
    expect(g.running, isEmpty);
  });
}
