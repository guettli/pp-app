// Audio helpers without Flutter dependencies (also used by tool/tts_check).
import 'dart:typed_data';

/// Converts little-endian 16-bit PCM bytes to floats in [-1, 1].
Float32List pcm16ToFloat(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final view = ByteData.sublistView(bytes);
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Cuts leading/trailing silence (keeps 150 ms margin) so the model sees
/// mostly speech. Returns the input unchanged if no speech is found.
Float32List trimSilence(Float32List audio, {double threshold = 0.02}) {
  const win = 320; // 20 ms
  int? first, last;
  for (var s = 0; s + win <= audio.length; s += win) {
    var e = 0.0;
    for (var i = s; i < s + win; i++) {
      e += audio[i] * audio[i];
    }
    if (e / win > threshold * threshold) {
      first ??= s;
      last = s + win;
    }
  }
  if (first == null) return audio;
  const margin = 2400;
  final a = (first - margin).clamp(0, audio.length);
  final b = (last! + margin).clamp(0, audio.length);
  return Float32List.sublistView(audio, a, b);
}
