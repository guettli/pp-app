// The voice games on a real phone: real TTS (also low and high), real
// microphone without noise suppression, real pitch tracking. "The child"
// is a synthetic voice played through the loudspeaker by a third player,
// not logged as a sound of the game. Nothing is recorded; only numbers are
// printed.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/game/game_io.dart';
import 'package:phoneme_party/game/voice_effects.dart';
import 'package:phoneme_party/voice/voice_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';
import '../test/support/logged.dart';
import '../test/support/sounds.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late AppState base;
  setUpAll(() async => base = await AppState.load());
  setUp(() async => (await SharedPreferences.getInstance()).clear());

  /// Opens [game]; each time the mic opens, the phone plays the next of
  /// [voices] ([hz], [seconds]) after a moment.
  Future<(IoLog, GlobalKey<NavigatorState>, SoundOut)> open(
    WidgetTester t,
    VoiceGame game,
    List<(double, double)> voices,
  ) async {
    final sw = Stopwatch()..start();
    final log = IoLog(() => sw.elapsed);
    final child = AudioPlayersOut(takesFocus: false);
    var n = 0;
    Timer? say;
    final io = GameIo(
      mic: () => LoggedMic(
        log,
        RecordMic(),
        onStart: () {
          final (hz, s) = voices[(n++).clamp(0, voices.length - 1)];
          say?.cancel();
          say = Timer(const Duration(milliseconds: 500), () {
            child.play(wavBytes(voice(hz, s, amp: 0.5)));
          });
        },
      ),
      speaker: () => LoggedSpeaker(log, TtsSpeaker()),
      replayPlayer: () => LoggedOut(log, 'replay', AudioPlayersOut()),
      soundPlayer: () =>
          LoggedOut(log, 'sfx', AudioPlayersOut(takesFocus: false)),
      random: GameIo.device().random,
    );
    final app = AppState(
      FakeRecognizer(() => ''),
      base.comparer,
      base.progress,
      base.book,
      io: io,
    );
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold()));
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => VoiceGameScreen(app: app, game: game),
      ),
    );
    return (log, nav, child);
  }

  Future<void> until(
    WidgetTester t,
    bool Function() done,
    Duration limit,
    IoLog log,
  ) async {
    const step = Duration(milliseconds: 100);
    for (var e = Duration.zero; e < limit; e += step) {
      if (done()) return;
      await t.pump(step);
    }
    fail('timed out\n$log');
  }

  Future<void> close(
    WidgetTester t,
    GlobalKey<NavigatorState> nav,
    SoundOut child,
  ) async {
    nav.currentState!.popUntil((r) => r.isFirst);
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await child.dispose();
    await t.pumpWidget(const SizedBox());
  }

  testWidgets('hold it long, heard through the real microphone', (t) async {
    final (log, nav, child) = await open(t, VoiceGame.hold, [(220, 5)]);
    try {
      final best = base.progress;
      await until(
        t,
        () => best.holdBest(base.book.lang, 'A') > Duration.zero,
        const Duration(seconds: 40),
        log,
      );
      final held = best.holdBest(base.book.lang, 'A');
      debugPrint('IOLOG voice held A for ${held.inMilliseconds} ms of 5000');
      // the loudspeaker's start and end, and the room, take a little
      expect(held.inMilliseconds, inInclusiveRange(4000, 5600));
      expect(log.soundsWhileRecording(), isEmpty, reason: '$log');
    } finally {
      for (final e in log.events) {
        debugPrint('IOLOG hold $e');
      }
      await close(t, nav, child);
    }
  });

  testWidgets('low and high, heard through the real microphone', (t) async {
    final (log, nav, child) = await open(t, VoiceGame.pitch, [
      (230, 1.5),
      (160, 1.5), // 6.3 semitones lower
      (420, 1.5), // 10.4 semitones higher
    ]);
    try {
      final p = base.progress;
      await until(
        t,
        () => p.pitchBest(low: false) > 0,
        const Duration(seconds: 60),
        log,
      );
      final low = p.pitchBest(low: true), high = p.pitchBest(low: false);
      debugPrint(
        'IOLOG voice low ${low.toStringAsFixed(1)} high '
        '${high.toStringAsFixed(1)} semitones (6.3 / 10.4 played)',
      );
      expect(low, closeTo(6.3, 1));
      expect(high, closeTo(10.4, 1));
      expect(log.soundsWhileRecording(), isEmpty, reason: '$log');
    } finally {
      for (final e in log.events) {
        debugPrint('IOLOG pitch $e');
      }
      await close(t, nav, child);
    }
  });
}
