// The microphone opens while the phone still says the phrase, because
// opening it takes time: on a Galaxy A80 the first audio came 0.5 s after
// start(), and with the old order (speak, wait, open) 0.8–2.8 s after the
// phone had finished; a child who answers at once lost the first sounds
// (integration_test/latency_test.dart).
//
// The game must never score its own voice, so everything the microphone
// hears up to the end of the phone's voice is dropped: all audio before
// [EchoGate.spoken], then the whole first piece the platform delivers
// after it (it can hold audio recorded before the end: phones buffer
// differently), at least [EchoGate.minSkip] in all, and further until the
// room is quiet (the voice echoes for a moment), [EchoGate.maxSkip] at
// most.
// On the A80 the voice was down at the noise floor 40 ms after speak()
// completed.
import 'dart:math' as math;
import 'dart:typed_data';

class EchoGate {
  EchoGate({
    this.minSkip = const Duration(milliseconds: 60),
    this.maxSkip = const Duration(milliseconds: 300),
  });

  /// Dropped after [spoken] in any case.
  final Duration minSkip;

  /// Dropped after [spoken] at most, even if it does not get quiet (a
  /// child who already speaks, a loud room).
  final Duration maxSkip;

  /// Quiet: this much below the loudest frame heard while the phone
  /// spoke, or below [_silent] (a soft voice, a noisy room).
  static const _quieter = 30.0;
  static const _silent = -50.0;

  static const _frameBytes = 320 * 2; // 20 ms of 16 kHz PCM16

  bool _spoken = false;
  bool _open = false;
  double _peak = -100;
  int _skipped = 0; // bytes dropped after spoken()
  bool _firstAfter = true; // the next chunk is the first after spoken()

  /// RMS of the quiet frame that opened the gate: the room without the
  /// phone (null if the gate opened at [maxSkip]). For the endpointer's
  /// noise level, since a quick child may speak from the first frame on.
  double? quietLevel;
  final _carry = BytesBuilder(copy: false);

  /// Whether audio passes now.
  bool get open => _open;

  bool _clean = false;
  double _quietest = double.infinity;

  /// The phone has finished speaking. [clean]: the microphone started only
  /// after that (a short phrase), so nothing of the voice can be in the
  /// recording; only [minSkip] is dropped (the room's echo), whatever it
  /// sounds like: the child may already be talking.
  void spoken({bool clean = false}) {
    _spoken = true;
    _clean = clean;
    if (clean) _firstAfter = false;
  }

  /// The part of [chunk] to keep (empty while the gate is closed).
  Uint8List add(Uint8List chunk) {
    if (_open) return chunk;
    if (_spoken && _firstAfter) {
      _firstAfter = false;
      _carry.add(chunk);
      final all = _carry.takeBytes();
      final whole = all.length - all.length % _frameBytes;
      _skipped += whole;
      _carry.add(Uint8List.sublistView(all, whole));
      return Uint8List(0);
    }
    _carry.add(chunk);
    final bytes = _carry.takeBytes();
    final data = ByteData.sublistView(bytes);
    var pos = 0;
    while (pos + _frameBytes <= bytes.length) {
      final db = _db(data, pos);
      if (!_spoken) {
        _peak = math.max(_peak, db);
      } else {
        final skippedMs = _skipped * 1000 ~/ (16000 * 2);
        final quiet = db < math.max(_peak - _quieter, _silent);
        final rms = math.pow(10, db / 20).toDouble();
        if (_clean) {
          if (skippedMs >= minSkip.inMilliseconds) {
            _open = true;
            if (_quietest.isFinite) quietLevel = _quietest;
            return Uint8List.sublistView(bytes, pos);
          }
          _quietest = math.min(_quietest, rms);
          _skipped += _frameBytes;
          pos += _frameBytes;
          continue;
        }
        if (skippedMs >= maxSkip.inMilliseconds ||
            (skippedMs >= minSkip.inMilliseconds && quiet)) {
          _open = true;
          if (quiet) quietLevel = rms;
          return Uint8List.sublistView(bytes, pos);
        }
        _skipped += _frameBytes;
      }
      pos += _frameBytes;
    }
    _carry.add(Uint8List.sublistView(bytes, pos));
    return Uint8List(0);
  }

  static double _db(ByteData data, int pos) {
    var sum = 0.0;
    for (var i = 0; i < 320; i++) {
      final v = data.getInt16(pos + i * 2, Endian.little) / 32768;
      sum += v * v;
    }
    return 10 * math.log(math.max(sum / 320, 1e-10)) / math.ln10;
  }
}
