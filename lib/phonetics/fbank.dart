// Kaldi-style log-mel filterbank, matching Lhotse's `Fbank(FbankConfig())`
// (torchaudio-compatible mel scale), which is what ZIPA was trained with.
//
// Ported from guettli/pp wasm/kaldi-fbank/fbank-standalone.zig and verified
// against features computed by Lhotse itself (test/fbank_test.dart).
import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 16000;
const int numMelBins = 80;
const int _frameLength = 400; // 25 ms
const int _frameShift = 160; // 10 ms
const int _fftSize = 512;
const double _lowFreq = 20.0;
const double _highFreq = sampleRate / 2 - 400.0; // 7600 Hz
const double _preemph = 0.97;
const double _melFloor = 1.1920929e-07; // float32 eps, as in Lhotse

/// Computes log-mel features for 16 kHz mono audio in [-1, 1].
///
/// Returns a flat row-major array of shape (frames, 80).
Float32List extractFbank(Float32List audio) {
  final numSamples = audio.length;
  final numFrames = (numSamples + _frameShift ~/ 2) ~/ _frameShift;
  if (numSamples == 0 || numFrames == 0) return Float32List(0);

  // Reflect padding (snip_edges=False).
  const padLeft = (_frameLength - _frameShift) ~/ 2;
  final needed = (numFrames - 1) * _frameShift + _frameLength;
  final padRight = math.max(0, needed - numSamples - padLeft);
  final padded = Float64List(numSamples + padLeft + padRight);
  for (var i = 0; i < padLeft; i++) {
    padded[i] = audio[math.min(padLeft - 1 - i, numSamples - 1)];
  }
  for (var i = 0; i < numSamples; i++) {
    padded[padLeft + i] = audio[i];
  }
  for (var i = 0; i < padRight; i++) {
    padded[padLeft + numSamples + i] = audio[math.max(0, numSamples - 1 - i)];
  }

  final out = Float32List(numFrames * numMelBins);
  final frame = Float64List(_frameLength);
  final re = Float64List(_fftSize);
  final im = Float64List(_fftSize);
  final power = Float64List(_fftSize ~/ 2 + 1);

  for (var t = 0; t < numFrames; t++) {
    final start = t * _frameShift;
    var mean = 0.0;
    for (var i = 0; i < _frameLength; i++) {
      final idx = start + i;
      frame[i] = idx < padded.length ? padded[idx] : 0.0;
      mean += frame[i];
    }
    mean /= _frameLength;
    for (var i = 0; i < _frameLength; i++) {
      frame[i] -= mean;
    }
    for (var i = _frameLength - 1; i > 0; i--) {
      frame[i] -= _preemph * frame[i - 1];
    }
    frame[0] *= 1.0 - _preemph;

    for (var i = 0; i < _fftSize; i++) {
      re[i] = i < _frameLength ? frame[i] * _window[i] : 0.0;
      im[i] = 0.0;
    }
    _fft(re, im);
    for (var k = 0; k < power.length; k++) {
      power[k] = re[k] * re[k] + im[k] * im[k];
    }

    for (var m = 0; m < numMelBins; m++) {
      final f = _filters[m];
      var e = 0.0;
      for (var j = f.first; j < f.first + f.weights.length; j++) {
        e += f.weights[j - f.first] * power[j];
      }
      out[t * numMelBins + m] = math.log(math.max(e, _melFloor));
    }
  }
  return out;
}

// Povey window: hann(N, periodic=False) ^ 0.85
final Float64List _window = () {
  final w = Float64List(_frameLength);
  final a = 2 * math.pi / (_frameLength - 1);
  for (var i = 0; i < _frameLength; i++) {
    w[i] = math.pow(0.5 - 0.5 * math.cos(a * i), 0.85).toDouble();
  }
  return w;
}();

class _MelFilter {
  _MelFilter(this.first, this.weights);
  final int first;
  final Float64List weights;
}

double _mel(double hz) => 1127.0 * math.log(1.0 + hz / 700.0);

// Triangular filters in mel space; the Nyquist bin always has weight 0.
final List<_MelFilter> _filters = () {
  final binWidth = sampleRate / _fftSize;
  final melLow = _mel(_lowFreq);
  final melHigh = _mel(_highFreq);
  final delta = (melHigh - melLow) / (numMelBins + 1);
  final filters = <_MelFilter>[];
  for (var m = 0; m < numMelBins; m++) {
    final left = melLow + m * delta;
    final center = left + delta;
    final right = center + delta;
    final w = <double>[];
    var first = -1;
    for (var j = 0; j < _fftSize ~/ 2; j++) {
      final mj = _mel(binWidth * j);
      final v = math.max(
        0.0,
        math.min(
          (mj - left) / (center - left),
          (right - mj) / (right - center),
        ),
      );
      if (v > 0) {
        if (first < 0) first = j;
        // fill gaps (cannot happen for a triangle, kept for safety)
        while (first + w.length < j) {
          w.add(0);
        }
        w.add(v);
      }
    }
    filters.add(_MelFilter(math.max(first, 0), Float64List.fromList(w)));
  }
  return filters;
}();

// In-place radix-2 FFT.
void _fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len;
    final wr = math.cos(ang), wi = math.sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final a = i + k, b = a + len ~/ 2;
        final vr = re[b] * cr - im[b] * ci;
        final vi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - vr;
        im[b] = im[a] - vi;
        re[a] += vr;
        im[a] += vi;
        final ncr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = ncr;
      }
    }
  }
}
