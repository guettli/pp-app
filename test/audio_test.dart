import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/game/rules.dart';
import 'package:phoneme_party/phonetics/recognizer.dart';

void main() {
  group('pcm16ToFloat', () {
    test('little endian, full range', () {
      final b = ByteData(6)
        ..setInt16(0, 0, Endian.little)
        ..setInt16(2, 32767, Endian.little)
        ..setInt16(4, -32768, Endian.little);
      final f = pcm16ToFloat(b.buffer.asUint8List());
      expect(f[0], 0);
      expect(f[1], closeTo(1, 1e-4));
      expect(f[2], -1);
    });

    test('ignores a trailing odd byte', () {
      expect(pcm16ToFloat(Uint8List(5)).length, 2);
    });
  });

  group('trimSilence', () {
    // 1 s silence, 0.5 s tone, 1 s silence at 16 kHz
    Float32List clip() {
      final a = Float32List(40000);
      for (var i = 16000; i < 24000; i++) {
        a[i] = i.isEven ? 0.3 : -0.3;
      }
      return a;
    }

    test('cuts silence and keeps 150 ms margin', () {
      final t = trimSilence(clip());
      expect(t.length, 8000 + 2 * 2400);
      expect(t[2400], isNot(0));
      expect(t[2399], 0);
    });

    test('margin is clamped at the edges', () {
      final a = Float32List(16000)..fillRange(0, 16000, 0.3);
      expect(trimSilence(a).length, 16000);
    });

    test('pure silence is returned unchanged', () {
      final a = Float32List(8000);
      expect(trimSilence(a).length, 8000);
    });

    test('quiet noise below the threshold counts as silence', () {
      final a = clip();
      for (var i = 0; i < 16000; i++) {
        a[i] = i.isEven ? 0.01 : -0.01;
      }
      expect(trimSilence(a).length, 8000 + 2 * 2400);
    });
  });

  group('normalizePeak', () {
    test('quiet speech is boosted to the peak', () {
      final n = normalizePeak(Float32List.fromList([0.1, -0.05, 0.02]));
      expect(n[0], closeTo(0.5, 1e-6));
      expect(n[1], closeTo(-0.25, 1e-6));
    });

    test('loud audio is left alone', () {
      final a = Float32List.fromList([0.9, -0.5]);
      expect(identical(normalizePeak(a), a), isTrue);
    });

    test('the gain is capped, silence stays silence', () {
      expect(
        normalizePeak(Float32List.fromList([0.001]))[0],
        closeTo(0.03, 1e-6),
      );
      expect(normalizePeak(Float32List(10)).every((s) => s == 0), isTrue);
    });
  });

  test('quiet speech keeps its soft beginning', () {
    // 1 s silence, 300 ms soft onset (below trimSilence's threshold),
    // 500 ms speech, 1 s silence
    final a = Float32List(44800);
    for (var i = 16000; i < 28800; i++) {
      a[i] = (i.isEven ? 1 : -1) * (i < 20800 ? 0.015 : 0.05);
    }
    expect(trimSilence(a).length, 8000 + 2 * 2400); // onset lost
    expect(prepareForRecognition(a).length, 12800 + 2 * 2400);
  });

  group('recordingLimit', () {
    test('short phrases get 6 s (reaction time + speaking)', () {
      expect(recordingLimit('Hund'), const Duration(seconds: 6));
    });
    test('long phrases get more, at most 12 s', () {
      final long = recordingLimit('Kann ich die Rechnung haben?');
      expect(long, greaterThan(const Duration(seconds: 7)));
      expect(recordingLimit('a' * 500), const Duration(seconds: 12));
    });
  });
}
