import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/game/voice_effects.dart';

Float32List sine(double hz, int n, {double amp = 0.1}) => Float32List.fromList([
  for (var i = 0; i < n; i++) amp * math.sin(2 * math.pi * hz * i / 16000),
]);

double peakOf(Float32List a) => a.fold(0.0, (m, v) => math.max(m, v.abs()));

/// Zero crossings per second, a simple pitch estimate.
double crossingsPerSecond(Float32List a, double seconds) {
  var n = 0;
  for (var i = 1; i < a.length; i++) {
    if ((a[i - 1] < 0) != (a[i] < 0)) n++;
  }
  return n / seconds;
}

void main() {
  test('mouse is higher and shorter, bear lower and longer', () {
    final a = sine(200, 16000);
    final mouse = applyVoiceEffect(VoiceEffect.mouse, a);
    final bear = applyVoiceEffect(VoiceEffect.bear, a);
    expect(mouse.length, 10000);
    expect(bear.length, closeTo(22857, 1));
    // the same 200 Hz tone, played in less / more time
    expect(crossingsPerSecond(mouse, mouse.length / 16000), closeTo(640, 10));
    expect(crossingsPerSecond(bear, bear.length / 16000), closeTo(280, 10));
  });

  test('robot multiplies with a 50 Hz sine', () {
    // a constant input shows the modulator itself
    final a = Float32List.fromList(List.filled(1600, 0.5));
    final robot = applyVoiceEffect(VoiceEffect.robot, a);
    expect(robot.length, a.length);
    for (final i in [0, 40, 80, 123, 160, 1000]) {
      expect(
        robot[i],
        closeTo(0.8 * math.sin(2 * math.pi * 50 * i / 16000), 1e-4),
      );
    }
  });

  test('the recording itself is not changed', () {
    for (final e in VoiceEffect.values) {
      final a = sine(300, 1600, amp: 0.02);
      final copy = Float32List.fromList(a);
      applyVoiceEffect(e, a);
      expect(a, copy);
    }
  });

  test('a quiet recording is played back loud, silence stays silent', () {
    for (final e in VoiceEffect.values) {
      expect(
        peakOf(applyVoiceEffect(e, sine(300, 1600, amp: 0.02))),
        closeTo(0.8, 0.01),
      );
      final silent = applyVoiceEffect(e, Float32List(1600));
      expect(peakOf(silent), 0);
      expect(applyVoiceEffect(e, Float32List(0)), isEmpty);
    }
  });

  test('effects take turns', () {
    expect(VoiceEffect.mouse.next, VoiceEffect.bear);
    expect(VoiceEffect.robot.next, VoiceEffect.mouse);
  });

  test('wav header and samples', () {
    final wav = wavBytes(Float32List.fromList([0, 1, -1, 2]));
    final b = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 16)), 'WAVEfmt ');
    expect(b.getUint32(4, Endian.little), wav.length - 8);
    expect(b.getUint32(24, Endian.little), 16000);
    expect(b.getUint32(40, Endian.little), 8);
    expect(
      [for (var i = 0; i < 4; i++) b.getInt16(44 + 2 * i, Endian.little)],
      [0, 32767, -32767, 32767],
    ); // clipped, not wrapped
  });
}
