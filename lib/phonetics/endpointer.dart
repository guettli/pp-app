import 'dart:math' as math;
import 'dart:typed_data';

/// What [Endpointer] noticed in the audio fed so far.
enum EndpointEvent {
  /// Nothing new.
  none,

  /// Speech has started (reported once).
  speechStarted,

  /// Speech was followed by enough silence: stop recording (reported once).
  speechEnded,

  /// No speech within the timeout: stop recording (reported once).
  noSpeech,
}

/// Energy-based voice activity detection for hands-free recording: decides
/// when the child has finished speaking, so no stop button is needed.
///
/// The first [calibration] of audio is taken as background noise (a child
/// does not answer within 200 ms). A 20 ms frame counts as speech if its RMS
/// is above [minLevel] and [noiseFactor] times the noise level.
class Endpointer {
  Endpointer({
    this.sampleRate = 16000,
    this.calibration = const Duration(milliseconds: 200),
    this.minSpeech = const Duration(milliseconds: 120),
    this.trailingSilence = const Duration(milliseconds: 1000),
    this.noSpeechTimeout = const Duration(seconds: 5),
    this.minLevel = 0.015,
    this.noiseFactor = 3,
  });

  final int sampleRate;
  final Duration calibration;
  final Duration minSpeech;

  /// Pause after speech that ends the recording. Kids pause between words,
  /// so this is generous.
  final Duration trailingSilence;
  final Duration noSpeechTimeout;
  final double minLevel;
  final double noiseFactor;

  int get _frame => sampleRate ~/ 50; // 20 ms
  final _pending = <double>[];
  int? _carryByte;

  int _frames = 0;
  double _noiseSum = 0;
  int _noiseFrames = 0;
  int _speechRun = 0;
  int _silenceRun = 0;
  bool _started = false;
  bool _done = false;

  /// RMS of the last complete frame (for a level meter).
  double level = 0;

  /// Whether speech has been detected.
  bool get heardSpeech => _started;

  /// Whether the recording should stop.
  bool get done => _done;

  double get _noise => _noiseFrames == 0 ? 0 : _noiseSum / _noiseFrames;
  double get threshold => math.max(minLevel, _noise * noiseFactor);

  int _ms(Duration d) => d.inMilliseconds ~/ 20;

  /// Feeds little-endian 16-bit PCM bytes; chunks may split a sample.
  EndpointEvent addPcm16(Uint8List bytes) {
    var start = 0;
    final samples = <double>[];
    if (_carryByte != null && bytes.isNotEmpty) {
      final v = (_carryByte! | (bytes[0] << 8)).toSigned(16);
      samples.add(v / 32768.0);
      _carryByte = null;
      start = 1;
    }
    final view = ByteData.sublistView(bytes);
    var i = start;
    for (; i + 1 < bytes.length; i += 2) {
      samples.add(view.getInt16(i, Endian.little) / 32768.0);
    }
    if (i < bytes.length) _carryByte = bytes[i];
    return add(samples);
  }

  /// Feeds samples in [-1, 1].
  EndpointEvent add(List<double> samples) {
    _pending.addAll(samples);
    var event = EndpointEvent.none;
    var offset = 0;
    while (_pending.length - offset >= _frame) {
      var e = 0.0;
      for (var i = offset; i < offset + _frame; i++) {
        e += _pending[i] * _pending[i];
      }
      offset += _frame;
      final ev = _frameDone(math.sqrt(e / _frame));
      if (ev != EndpointEvent.none) event = ev;
    }
    _pending.removeRange(0, offset);
    return event;
  }

  EndpointEvent _frameDone(double rms) {
    level = rms;
    _frames++;
    if (_done) return EndpointEvent.none;
    if (_frames <= _ms(calibration)) {
      _noiseSum += rms;
      _noiseFrames++;
      return EndpointEvent.none;
    }
    final speech = rms > threshold;
    if (!_started) {
      _speechRun = speech ? _speechRun + 1 : 0;
      if (_speechRun >= _ms(minSpeech)) {
        _started = true;
        return EndpointEvent.speechStarted;
      }
      if (_frames >= _ms(noSpeechTimeout)) {
        _done = true;
        return EndpointEvent.noSpeech;
      }
      return EndpointEvent.none;
    }
    _silenceRun = speech ? 0 : _silenceRun + 1;
    if (_silenceRun >= _ms(trailingSilence)) {
      _done = true;
      return EndpointEvent.speechEnded;
    }
    return EndpointEvent.none;
  }
}
