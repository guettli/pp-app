// Synthetic sounds for tests: a voice at a given pitch, background noise.
import 'dart:math' as math;
import 'dart:typed_data';

/// [seconds] of a voice-like sound at [hz]: a few harmonics, getting
/// weaker, so a pitch tracker could pick an octave wrongly.
Float32List voice(double hz, double seconds, {double amp = 0.3}) {
  final n = (seconds * 16000).round();
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = i / 16000;
    var v = 0.0;
    for (var h = 1; h <= 6; h++) {
      v += math.sin(2 * math.pi * hz * h * t) / h;
    }
    out[i] = amp * v / 2;
  }
  return out;
}

Float32List noise(double seconds, {double amp = 0.003, int seed = 1}) {
  final rng = math.Random(seed);
  return Float32List.fromList([
    for (var i = 0; i < (seconds * 16000).round(); i++)
      (rng.nextDouble() - 0.5) * 2 * amp,
  ]);
}

Uint8List pcm16(List<double> samples) {
  final b = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(i * 2, (samples[i].clamp(-1, 1) * 32767).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}
