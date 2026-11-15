// How late does the microphone open after the phone has spoken? Measured
// on a real phone (tool/device_test.sh integration_test/latency_test.dart),
// printed as IOLOG lines; nothing is asserted, nothing is stored.
//
// 1. Mic opened before speak(): the recording shows when the TTS voice
//    really ends (loudness), compared with when speak() completes.
// 2. Mic opened after speak() completes (the old flow): how long until
//    the first audio arrives.
// 3. Mic started together with speak() (the flow now, see
//    lib/phonetics/echo_gate.dart): the TTS must take as long and be as
//    loud as before.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phoneme_party/game/game_io.dart';

/// Loudness (dB) per 20 ms of 16 kHz PCM16, with each frame's arrival time.
class _Tape {
  final sw = Stopwatch()..start();
  final frames = <(int ms, double db)>[];
  final _carry = BytesBuilder();
  int firstChunkMs = -1;

  void add(Uint8List chunk) {
    final now = sw.elapsedMilliseconds;
    if (firstChunkMs < 0) firstChunkMs = now;
    _carry.add(chunk);
    final bytes = _carry.takeBytes();
    const frame = 320 * 2; // 20 ms
    final whole = bytes.length - bytes.length % frame;
    final data = ByteData.sublistView(bytes);
    final n = whole ~/ frame;
    for (var f = 0; f < n; f++) {
      var sum = 0.0;
      for (var i = 0; i < 320; i++) {
        final v = data.getInt16(f * frame + i * 2, Endian.little) / 32768;
        sum += v * v;
      }
      final db = 10 * math.log(math.max(sum / 320, 1e-10)) / math.ln10;
      // frames of one chunk arrived together: spread them back in time
      frames.add((now - (n - 1 - f) * 20, db));
    }
    _carry.add(bytes.sublist(whole));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const words = ['Elefant', 'Hund', 'Schmetterling'];

  testWidgets('mic latency around the TTS', (t) async {
    await t.runAsync(() async {
      final tts = TtsSpeaker();
      await tts.setLanguage('de-DE');
      for (final word in words) {
        // 1. mic open during the whole phrase
        final mic = RecordMic();
        final tape = _Tape();
        final startCall = tape.sw.elapsedMilliseconds;
        final stream = await mic.start();
        final started = tape.sw.elapsedMilliseconds;
        final sub = stream.listen(tape.add);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final speakAt = tape.sw.elapsedMilliseconds;
        await tts.speak(word);
        final doneAt = tape.sw.elapsedMilliseconds;
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        await mic.stop();
        await sub.cancel();
        await mic.dispose();

        final quiet = tape.frames
            .where((f) => f.$1 < speakAt)
            .map((f) => f.$2)
            .fold<double>(0, (a, b) => a + b);
        final before = tape.frames.where((f) => f.$1 < speakAt).length;
        final floor = before == 0 ? -60.0 : quiet / before;
        final loud = tape.frames.where((f) => f.$2 > floor + 15).toList();
        final peak = tape.frames.map((f) => f.$2).fold(-100.0, math.max);
        final voiceStart = loud.isEmpty ? -1 : loud.first.$1;
        final voiceEnd = loud.isEmpty ? -1 : loud.last.$1 + 20;
        debugPrint(
          'IOLOG latency $word: mic start() ${started - startCall} ms, '
          'first audio ${tape.firstChunkMs - startCall} ms after start(); '
          'floor ${floor.toStringAsFixed(0)} dB, peak '
          '${peak.toStringAsFixed(0)} dB; voice ${voiceStart - speakAt}..'
          '${voiceEnd - speakAt} ms after speak(), speak() done '
          '${doneAt - speakAt} ms => done ${doneAt - voiceEnd} ms after '
          'the voice ended',
        );
        final profile = [
          for (final f in tape.frames)
            if (f.$1 >= voiceEnd - 300 && f.$1 <= doneAt + 300)
              '${f.$1 - doneAt}:${f.$2.toStringAsFixed(0)}',
        ].join(' ');
        debugPrint('IOLOG latency $word profile (ms vs done:dB) $profile');

        // 2. the old flow: speak, wait 250 ms, then open the mic
        final mic2 = RecordMic();
        final tape2 = _Tape();
        final s2 = tape2.sw.elapsedMilliseconds;
        await tts.speak(word);
        final d2 = tape2.sw.elapsedMilliseconds;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final open = tape2.sw.elapsedMilliseconds;
        final stream2 = await mic2.start();
        final sub2 = stream2.listen(tape2.add);
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await mic2.stop();
        await sub2.cancel();
        await mic2.dispose();
        debugPrint(
          'IOLOG latency $word old flow: speak() took ${d2 - s2} ms, '
          'start() called ${open - d2} ms after done, first audio '
          '${tape2.firstChunkMs - d2} ms after done',
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // 3. the new flow: start() and speak() at the same time; the TTS
        // must sound as before (as long, as loud)
        final mic3 = RecordMic();
        final tape3 = _Tape();
        final s3 = tape3.sw.elapsedMilliseconds;
        final opening = mic3.start();
        await tts.speak(word);
        final d3 = tape3.sw.elapsedMilliseconds;
        final sub3 = (await opening).listen(tape3.add);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await mic3.stop();
        await sub3.cancel();
        await mic3.dispose();
        final during = tape3.frames.where((f) => f.$1 <= d3);
        final peak3 = during.map((f) => f.$2).fold(-100.0, math.max);
        final after = tape3.frames.where((f) => f.$1 > d3 + 60);
        final tail = after.map((f) => f.$2).fold(-100.0, math.max);
        debugPrint(
          'IOLOG latency $word new flow: speak() took ${d3 - s3} ms '
          '(old flow ${d2 - s2} ms), first audio ${tape3.firstChunkMs - s3} '
          'ms after speak(), TTS peak ${peak3.toStringAsFixed(0)} dB '
          '(mic open before: ${peak.toStringAsFixed(0)} dB), loudest '
          'after done+60ms ${tail.toStringAsFixed(0)} dB',
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      await tts.stop();
    });
  });
}
