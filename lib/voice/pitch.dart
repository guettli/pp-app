// Pitch and voicing of the child's voice, frame by frame, for the voice
// games (hold a sound long, speak low or high). No model: YIN
// (de Cheveigné & Kawahara 2002) on 16 kHz PCM, fast enough for live use.
import 'dart:math' as math;
import 'dart:typed_data';

/// One 20 ms step of the microphone signal.
class VoiceFrame {
  const VoiceFrame(this.rms, this.pitch);

  /// Loudness (RMS of the samples in [-1, 1]).
  final double rms;

  /// Fundamental frequency in Hz, or null if the sound is not voiced
  /// (silence, noise, "sss").
  final double? pitch;

  bool get voiced => pitch != null;
}

/// YIN pitch estimate of [frame] (mono, [sampleRate]), or null if no clear
/// period between [minHz] and [maxHz] is found.
double? yinPitch(
  Float32List frame, {
  int sampleRate = 16000,
  double minHz = 70,
  double maxHz = 1100,
  double threshold = 0.15,
}) {
  final maxTau = (sampleRate / minHz).floor();
  final minTau = (sampleRate / maxHz).floor().clamp(2, maxTau);
  final w = frame.length - maxTau - 1;
  if (w < maxTau ~/ 2) return null;
  // difference function and its cumulative mean normalisation
  final d = Float64List(maxTau + 2);
  for (var tau = 1; tau <= maxTau + 1; tau++) {
    var sum = 0.0;
    for (var i = 0; i < w; i++) {
      final x = frame[i] - frame[i + tau];
      sum += x * x;
    }
    d[tau] = sum;
  }
  var running = 0.0;
  final cmnd = Float64List(maxTau + 2)..[0] = 1;
  for (var tau = 1; tau <= maxTau + 1; tau++) {
    running += d[tau];
    cmnd[tau] = running == 0 ? 1 : d[tau] * tau / running;
  }
  // the first dip below the threshold, followed down to its minimum
  for (var tau = minTau; tau <= maxTau; tau++) {
    if (cmnd[tau] < threshold) {
      while (tau + 1 <= maxTau && cmnd[tau + 1] < cmnd[tau]) {
        tau++;
      }
      // parabolic interpolation around the minimum
      final a = cmnd[tau - 1], b = cmnd[tau], c = cmnd[tau + 1];
      final den = a - 2 * b + c;
      final shift = den == 0 ? 0.0 : (0.5 * (a - c) / den).clamp(-1.0, 1.0);
      return sampleRate / (tau + shift);
    }
  }
  return null;
}

/// Turns a stream of 16-bit PCM chunks into [VoiceFrame]s every 20 ms,
/// analysing the last 64 ms (enough periods for a low voice).
///
/// A frame is voiced only if it is loud enough: above [minLevel] and
/// [noiseFactor] times the background measured in the first [calibration].
class VoiceMeter {
  VoiceMeter({
    this.sampleRate = 16000,
    this.calibration = const Duration(milliseconds: 200),
    this.minLevel = 0.01,
    this.noiseFactor = 3,
  });

  final int sampleRate;
  final Duration calibration;
  final double minLevel;
  final double noiseFactor;

  int get _hop => sampleRate ~/ 50;
  int get _window => sampleRate * 64 ~/ 1000;

  final _samples = <double>[];

  /// Samples not yet covered by a frame (at the end of [_samples]).
  int _fresh = 0;
  int? _carry;
  int _frames = 0;
  double _noiseSum = 0;
  int _noiseFrames = 0;

  double get _noise => _noiseFrames == 0 ? 0 : _noiseSum / _noiseFrames;
  double get threshold => math.max(minLevel, _noise * noiseFactor);

  /// Feeds little-endian 16-bit PCM; returns the frames completed by it.
  /// Chunks may split a sample.
  List<VoiceFrame> addPcm16(Uint8List bytes) {
    final samples = <double>[];
    var i = 0;
    if (_carry != null && bytes.isNotEmpty) {
      samples.add((_carry! | (bytes[0] << 8)).toSigned(16) / 32768.0);
      _carry = null;
      i = 1;
    }
    final view = ByteData.sublistView(bytes);
    for (; i + 1 < bytes.length; i += 2) {
      samples.add(view.getInt16(i, Endian.little) / 32768.0);
    }
    if (i < bytes.length) _carry = bytes[i];
    return add(samples);
  }

  /// Feeds samples in [-1, 1]; returns the frames completed by them.
  List<VoiceFrame> add(List<double> samples) {
    _samples.addAll(samples);
    _fresh += samples.length;
    final out = <VoiceFrame>[];
    while (_fresh >= _hop) {
      _fresh -= _hop;
      out.add(_frame(_samples.length - _fresh));
    }
    // keep one window (plus what is not analysed yet)
    final keep = _window + _fresh;
    if (_samples.length > keep) _samples.removeRange(0, _samples.length - keep);
    return out;
  }

  /// The frame ending at sample [end] of [_samples].
  VoiceFrame _frame(int end) {
    _frames++;
    var e = 0.0;
    for (var i = end - _hop; i < end; i++) {
      e += _samples[i] * _samples[i];
    }
    final rms = math.sqrt(e / _hop);
    if (_frames <= calibration.inMilliseconds ~/ 20) {
      _noiseSum += rms;
      _noiseFrames++;
      return VoiceFrame(rms, null);
    }
    if (rms < threshold || end < _window) return VoiceFrame(rms, null);
    final frame = Float32List.fromList(_samples.sublist(end - _window, end));
    return VoiceFrame(rms, yinPitch(frame, sampleRate: sampleRate));
  }
}

/// Semitones from [from] to [to] (positive: higher).
double semitones(double from, double to) => 12 * math.log(to / from) / math.ln2;

/// Median of [xs] (null if empty).
double? median(Iterable<double> xs) {
  final l = xs.toList()..sort();
  if (l.isEmpty) return null;
  final m = l.length ~/ 2;
  return l.length.isOdd ? l[m] : (l[m - 1] + l[m]) / 2;
}
