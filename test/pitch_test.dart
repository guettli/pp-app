import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/voice/pitch.dart';
import 'package:phoneme_party/voice/voice_take.dart';

import 'support/sounds.dart';

/// Frames for [audio], fed in [chunk]-byte pieces (odd sizes split samples).
List<VoiceFrame> meter(List<double> audio, {int chunk = 640}) {
  final m = VoiceMeter();
  final bytes = pcm16(audio);
  final out = <VoiceFrame>[];
  for (var i = 0; i < bytes.length; i += chunk) {
    out.addAll(
      m.addPcm16(
        Uint8List.sublistView(bytes, i, math.min(i + chunk, bytes.length)),
      ),
    );
  }
  return out;
}

VoiceTake take(List<VoiceFrame> frames, [VoiceTake? t]) {
  final take = t ?? VoiceTake();
  for (final f in frames) {
    take.add(f);
  }
  return take;
}

void main() {
  group('yinPitch', () {
    for (final hz in [90.0, 150.0, 220.0, 330.0, 520.0, 900.0]) {
      test('finds $hz Hz without octave errors', () {
        final f = Float32List.sublistView(voice(hz, 0.1), 0, 1024);
        expect(yinPitch(f), closeTo(hz, hz * 0.02));
      });
    }

    test('noise has no pitch', () {
      final f = Float32List.sublistView(noise(0.1, amp: 0.3), 0, 1024);
      expect(yinPitch(f), isNull);
    });
  });

  group('VoiceMeter', () {
    test('one frame per 20 ms, voiced only where the voice is', () {
      final audio = [...noise(0.5), ...voice(200, 1), ...noise(0.5)];
      final frames = meter(audio);
      expect(frames.length, closeTo(100, 1));
      final voiced = frames.where((f) => f.voiced).toList();
      // about one second, minus the window filling up at the start
      expect(voiced.length, inInclusiveRange(44, 52));
      for (final f in voiced) {
        expect(f.pitch, closeTo(200, 4));
      }
    });

    test('odd chunk sizes give the same frames', () {
      final audio = [...noise(0.3), ...voice(300, 0.5)];
      final a = meter(audio);
      final b = meter(audio, chunk: 333);
      expect(b.length, a.length);
      for (var i = 0; i < a.length; i++) {
        expect(b[i].voiced, a[i].voiced, reason: 'frame $i');
      }
    });

    test('quiet humming under the background noise is not a voice', () {
      final audio = [
        ...noise(0.3, amp: 0.05),
        ...[
          for (final (i, v) in voice(200, 1, amp: 0.02).indexed)
            v + noise(1, amp: 0.05, seed: 2)[i],
        ],
      ];
      expect(meter(audio).where((f) => f.voiced), isEmpty);
    });
  });

  group('real voices', () {
    for (final hz in [180.0, 260.0, 400.0, 650.0]) {
      test('a shaky, breathy $hz Hz voice: no octave errors, held through', () {
        final t = take(
          meter([...noise(0.4), ...childVoice(hz, 4), ...noise(1)]),
        );
        expect(t.pitch, closeTo(hz, hz * 0.03));
        expect(t.held.inMilliseconds, closeTo(4000, 200));
      });
    }

    test('very breathy: still held, still the right pitch', () {
      final t = take(
        meter([
          ...noise(0.4),
          ...childVoice(300, 4, breath: 0.5, jitter: 0.03),
          ...noise(1),
        ]),
      );
      expect(t.pitch, closeTo(300, 12));
      expect(t.held.inMilliseconds, greaterThan(3500));
    });

    test('every other cycle weaker (a creaky voice): not an octave lower', () {
      const hz = 220.0;
      final f = Float32List(1024);
      for (var i = 0; i < f.length; i++) {
        final cycle = (i * hz / 16000).floor();
        final amp = cycle.isEven ? 0.3 : 0.18;
        f[i] = amp * math.sin(2 * math.pi * hz * i / 16000);
      }
      expect(yinPitch(f), closeTo(hz, 5));
    });

    for (final fundamental in [0.3, 0.15, 0.05]) {
      test('a weak fundamental ($fundamental): not an octave higher', () {
        const hz = 200.0;
        final f = Float32List(1024);
        for (var i = 0; i < f.length; i++) {
          final t = i / 16000;
          f[i] =
              0.3 *
              (fundamental * math.sin(2 * math.pi * hz * t) +
                  math.sin(2 * math.pi * 2 * hz * t) +
                  0.5 * math.sin(2 * math.pi * 3 * hz * t));
        }
        expect(yinPitch(f), closeTo(hz, 5));
      });
    }

    test('a pitch an octave off within one sound is moved back', () {
      final t = VoiceTake();
      for (var i = 0; i < 60; i++) {
        t.add(VoiceFrame(0.2, i % 4 == 3 ? 125 : 250));
      }
      expect(t.pitch, closeTo(250, 1));
      expect(t.livePitch, closeTo(250, 1));
    });

    test('a squeak above 1100 Hz is not taken an octave lower', () {
      final f = Float32List.sublistView(voice(1300, 0.1), 0, 1024);
      expect(yinPitch(f), closeTo(1300, 30));
    });

    test('the child starts right away: the voice is not taken for noise', () {
      final t = take(meter([...voice(250, 4), ...noise(1)]));
      expect(t.started, isTrue);
      expect(t.held.inMilliseconds, closeTo(4000, 250));
    });
  });

  group('VoiceTake', () {
    test('a long "Aaaa" is held for its length', () {
      final t = take(meter([...noise(0.5), ...voice(250, 4), ...noise(1)]));
      expect(t.done, isTrue);
      expect(t.held.inMilliseconds, closeTo(4000, 120));
      expect(t.pitch, closeTo(250, 5));
      expect(holdStars(t.held), 1);
    });

    test('a short wobble is held through, a breath ends it', () {
      final wobble = take(
        meter([
          ...noise(0.3),
          ...voice(250, 2),
          ...noise(0.2),
          ...voice(250, 2),
          ...noise(1),
        ]),
      );
      expect(wobble.held.inMilliseconds, closeTo(4200, 150));

      final breath = take(
        meter([
          ...noise(0.3),
          ...voice(250, 2),
          ...noise(0.6),
          ...voice(250, 2),
          ...noise(1),
        ]),
      );
      expect(breath.held.inMilliseconds, closeTo(2000, 120));
    });

    test('silence: the try ends and nothing was heard', () {
      final t = take(meter(noise(7)));
      expect(t.done, isTrue);
      expect(t.heardNothing, isTrue);
    });

    test('ends by itself at the best there is', () {
      final t = take(meter([...noise(0.3), ...voice(250, 20)]));
      expect(t.done, isTrue);
      expect(t.held, const Duration(seconds: 15));
      expect(holdStars(t.held), 3);
    });
  });

  test('stars', () {
    expect(
      [
        2.9,
        3,
        5,
        8,
      ].map((s) => holdStars(Duration(milliseconds: (s * 1000).round()))),
      [0, 1, 2, 3],
    );
    expect(<double>[-1, -2, -3.5, -5, 2].map(lowStars), [0, 1, 2, 3, 0]);
    expect(<double>[1, 3, 5, 8, -3].map(highStars), [0, 1, 2, 3, 0]);
    expect(semitones(200, 400), closeTo(12, 1e-9));
    expect(median([3.0, 1, 2]), 2);
    expect(median(<double>[]), isNull);
  });
}
