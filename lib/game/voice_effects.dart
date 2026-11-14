// Funny playback of the child's own recording: hearing yourself as a mouse,
// a bear or a robot makes kids want to speak again. Pure Dart, in memory
// only: the recording is never written to disk.
import 'dart:math' as math;
import 'dart:typed_data';

enum VoiceEffect {
  /// Higher and faster.
  mouse('🐭'),

  /// Lower and slower.
  bear('🐻'),

  /// Metallic (ring modulation).
  robot('🤖');

  const VoiceEffect(this.emoji);

  final String emoji;

  VoiceEffect get next => values[(index + 1) % values.length];
}

/// Returns [audio] (mono, -1..1) changed by [effect] and scaled to a peak
/// of [peak], so a quiet child is heard well.
Float32List applyVoiceEffect(
  VoiceEffect effect,
  Float32List audio, {
  int sampleRate = 16000,
  double peak = 0.8,
}) {
  final out = switch (effect) {
    VoiceEffect.mouse => resample(audio, 1.6),
    VoiceEffect.bear => resample(audio, 0.7),
    VoiceEffect.robot => ringModulate(audio, 50, sampleRate),
  };
  return scaleToPeak(out, peak);
}

/// Plays [audio] [factor] times as fast (pitch changes with it), using
/// linear interpolation.
Float32List resample(Float32List audio, double factor) {
  if (audio.isEmpty) return Float32List(0);
  final n = math.max(1, (audio.length / factor).floor());
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final pos = i * factor;
    final j = pos.floor();
    if (j + 1 >= audio.length) {
      out[i] = audio[audio.length - 1];
    } else {
      final f = pos - j;
      out[i] = audio[j] * (1 - f) + audio[j + 1] * f;
    }
  }
  return out;
}

/// Multiplies [audio] with a sine of [hz]: the classic robot voice.
Float32List ringModulate(Float32List audio, double hz, int sampleRate) {
  final out = Float32List(audio.length);
  final w = 2 * math.pi * hz / sampleRate;
  for (var i = 0; i < audio.length; i++) {
    out[i] = audio[i] * math.sin(w * i);
  }
  return out;
}

/// Scales [audio] so its largest absolute sample is [peak]; silence stays
/// silence.
Float32List scaleToPeak(Float32List audio, double peak) {
  var max = 0.0;
  for (final v in audio) {
    if (v.abs() > max) max = v.abs();
  }
  if (max < 1e-6) return audio;
  final g = peak / max;
  return Float32List.fromList([for (final v in audio) v * g]);
}

/// A 16-bit mono WAV file of [audio] (-1..1), for the audio player.
Uint8List wavBytes(Float32List audio, {int sampleRate = 16000}) {
  final data = audio.length * 2;
  final b = ByteData(44 + data);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  b.setUint32(4, 36 + data, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // fmt chunk size
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 2, Endian.little); // bytes per second
  b.setUint16(32, 2, Endian.little); // block align
  b.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  b.setUint32(40, data, Endian.little);
  for (var i = 0; i < audio.length; i++) {
    final v = (audio[i].clamp(-1.0, 1.0) * 32767).round();
    b.setInt16(44 + 2 * i, v, Endian.little);
  }
  return b.buffer.asUint8List();
}
