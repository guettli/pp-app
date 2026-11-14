// The play screen on a real phone (tool/device_test.sh): real TTS, real
// players, real audio focus and real timing. Built only into the test APK
// (ci DeviceTestApks), never into the release app.
//
// 1. Fake microphone: a whole world goes by itself; nothing the app plays
//    may overlap the recording.
// 2. Real microphone: the phone's TTS plays "the child" through the
//    loudspeaker, the real microphone, endpointer and recognizer hear it.
//    Recordings stay in memory, as in the app; only IPA and stars are
//    printed.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/game/game_io.dart';
import 'package:phoneme_party/game/rules.dart';
import 'package:phoneme_party/phonetics/recognizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';
import '../test/support/game.dart';
import '../test/support/logged.dart';

/// Prints the log for tool/device_test.sh (it reads logcat).
void report(String name, IoLog log) {
  for (final e in log.events) {
    debugPrint('IOLOG $name $e');
  }
}

/// Closes the play screen and lets the players wind down, so nothing of
/// it runs on after the test.
Future<void> close(Game game) async {
  game.nav.currentState!.popUntil((r) => r.isFirst);
  await game.wait(const Duration(seconds: 2));
  await game.t.pumpWidget(const SizedBox());
  await game.wait(const Duration(milliseconds: 500));
}

/// The real recognizer, printing what it heard and the stars for [word].
class PrintingRecognizer implements Recognizer {
  PrintingRecognizer(this.inner, this.app, this.word);
  final Recognizer inner;
  final AppState app;
  final Phrase Function() word;

  /// Stars per answer.
  final stars = <int>[];

  @override
  Future<Recognition> recognize(Float32List audio) async {
    final r = await inner.recognize(audio);
    final w = word();
    final s = scorePhrase(app.comparer, w, r.ipa, app.book.lang).stars;
    stars.add(s);
    debugPrint(
      'IOLOG heard ${w.text}: ${audio.length / 16000}s "${r.ipa}" $s stars',
    );
    return r;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late AppState base;

  setUpAll(() async {
    base = await AppState.load();
  });
  // every test starts without progress; the test app
  // (…phoneme_party.test) has its own storage
  setUp(() async => (await SharedPreferences.getInstance()).clear());

  const step = Duration(milliseconds: 100);

  testWidgets('a whole world by itself on the phone', (t) async {
    final sw = Stopwatch()..start();
    final log = IoLog(() => sw.elapsed);
    final mic = FakeMic(log, () => Child.speaks);
    late final Game game;
    final io = GameIo(
      mic: () => mic,
      speaker: () => LoggedSpeaker(log, TtsSpeaker()),
      replayPlayer: () => LoggedOut(log, 'replay', AudioPlayersOut()),
      soundPlayer: () =>
          LoggedOut(log, 'sfx', AudioPlayersOut(takesFocus: false)),
      random: GameIo.device().random,
    );
    final app = AppState(
      FakeRecognizer(() => game.current.ipa),
      base.comparer,
      base.progress,
      base.book,
      io: io,
    );
    game = await Game.open(t, app, log, step: step);
    try {
      await game.until(
        () => game.dialog.evaluate().isNotEmpty,
        limit: const Duration(minutes: 3),
        reason: 'world-done dialog',
      );
      expect(game.said, [for (final p in game.words) p.text]);
      expect(game.recordings, game.words.length);
      expect(game.replays, game.words.length);
      game.expectClean();
      await game.wait(const Duration(seconds: 5));
      expect(game.recordings, game.words.length);
      expect(game.running.where((i) => i.device != 'sfx'), isEmpty);
    } finally {
      report('world', log);
      await close(game);
    }
  });

  testWidgets('the phone speaks into its own microphone', (t) async {
    final sw = Stopwatch()..start();
    final log = IoLog(() => sw.elapsed);
    late final Game game;
    // "the child": a second TTS voice, not logged as a sound of the app
    final child = TtsSpeaker();
    Timer? say;
    final io = GameIo(
      mic: () => LoggedMic(
        log,
        RecordMic(),
        onStart: () {
          say?.cancel();
          say = Timer(const Duration(milliseconds: 600), () {
            child.speak(game.current.text);
          });
        },
      ),
      speaker: () => LoggedSpeaker(log, TtsSpeaker()),
      replayPlayer: () => LoggedOut(log, 'replay', AudioPlayersOut()),
      soundPlayer: () =>
          LoggedOut(log, 'sfx', AudioPlayersOut(takesFocus: false)),
      random: GameIo.device().random,
    );
    await child.setLanguage(base.book.lang);
    final rec = PrintingRecognizer(base.recognizer, base, () => game.current);
    final app = AppState(rec, base.comparer, base.progress, base.book, io: io);
    game = await Game.open(t, app, log, step: step);
    try {
      // three answers, whatever their stars
      await game.until(
        () => rec.stars.length >= 3,
        limit: const Duration(minutes: 2),
        reason: 'three words heard',
      );
      // a synthetic voice through speaker and mic: not every word gets a
      // star, but some must, or the way from mic to stars is broken
      expect(rec.stars.where((s) => s >= 1), isNotEmpty, reason: '$log');
      game.expectClean();
    } finally {
      say?.cancel();
      await child.stop();
      report('loopback', log);
      await close(game);
    }
  });
}
