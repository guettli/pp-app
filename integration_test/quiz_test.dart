// The quiz on a real phone: real TTS, real microphone, real recogniser.
// "The child" is a second TTS voice that says the right answer through the
// loudspeaker when the microphone opens, not logged as a sound of the
// game. Nothing is recorded; only what was understood is printed.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/game/game_io.dart';
import 'package:phoneme_party/quiz/facts.dart';
import 'package:phoneme_party/quiz/quiz_lines.dart';
import 'package:phoneme_party/quiz/quiz_rules.dart';
import 'package:phoneme_party/quiz/quiz_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';
import '../test/support/logged.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late AppState base;
  setUpAll(() async => base = await AppState.load());
  setUp(() async => (await SharedPreferences.getInstance()).clear());

  testWidgets('the quiz, answered through the real microphone', (t) async {
    final book = base.book;
    final lines = QuizLines.of(book.lang);
    final round = makeRound(
      [for (var w = 0; w < 3; w++) ...book.world(w)],
      base.facts,
      math.Random(3),
      count: 3,
      similar: (a, b) => soundsSimilar(base.comparer, book.lang, a, b),
    );
    expect(round, hasLength(3));
    final sw = Stopwatch()..start();
    final log = IoLog(() => sw.elapsed);

    /// The answer to the question the phone asked last.
    String? answer() {
      for (final s in log.started('tts').reversed) {
        for (final q in round) {
          if (s == lines.ask(q)) return q.answer.text;
        }
      }
      return null;
    }

    final child = TtsSpeaker();
    await child.setLanguage(book.lang);
    Timer? say;
    final io = GameIo(
      mic: () => LoggedMic(
        log,
        RecordMic(),
        onStart: () {
          say?.cancel();
          say = Timer(const Duration(milliseconds: 600), () {
            final a = answer();
            if (a != null) child.speak(a);
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
      base.recognizer,
      base.comparer,
      base.progress,
      book,
      io: io,
      facts: base.facts,
    );
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold()));
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => QuizScreen(app: app, round: round),
      ),
    );
    try {
      const step = Duration(milliseconds: 100);
      final dialog = find.byType(AlertDialog);
      for (var e = Duration.zero; dialog.evaluate().isEmpty; e += step) {
        if (e > const Duration(minutes: 3)) fail('timed out\n$log');
        await t.pump(step);
      }
      final stars = base.progress.quizBest(book.lang);
      final misses = log
          .started('tts')
          .where((s) => s.startsWith(lines.answerIs('').split(':').first))
          .length;
      debugPrint(
        'IOLOG quiz $round: $stars stars, $misses wrong, '
        '${log.started('mic').length} recordings',
      );
      // a synthetic voice through speaker and mic: most must be understood
      expect(misses, lessThanOrEqualTo(1), reason: '$log');
      expect(log.soundsWhileRecording(), isEmpty, reason: '$log');
    } finally {
      say?.cancel();
      await child.stop();
      for (final e in log.events) {
        debugPrint('IOLOG quiz $e');
      }
      nav.currentState!.popUntil((r) => r.isFirst);
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.pumpWidget(const SizedBox());
    }
  });
}
