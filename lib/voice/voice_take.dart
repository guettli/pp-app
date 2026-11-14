// One try in a voice game: the child makes a sound (a long "Aaaa", or
// "Aaa" low like a bear / high like a mouse). Fed with VoiceFrames, it
// knows when the sound started and ended, how long it was held, and its
// pitch. Pure Dart, so the rules are tested without a microphone.
import 'pitch.dart';

class VoiceTake {
  VoiceTake({
    this.minStart = const Duration(milliseconds: 120),
    this.maxGap = const Duration(milliseconds: 400),
    this.noStart = const Duration(seconds: 6),
    this.maxHeld = const Duration(seconds: 15),
  });

  /// Voiced this long without a break: the sound has started.
  final Duration minStart;

  /// A break longer than this ends the sound (breath, stop). Shorter ones
  /// (a wobble, a quiet moment) are held through.
  final Duration maxGap;

  /// Nothing started within this time: the try is over.
  final Duration noStart;

  /// Held this long: done, the best there is.
  final Duration maxHeld;

  static const frame = Duration(milliseconds: 20);

  int _frames = 0;
  int _run = 0;
  int _gap = 0;
  int? _start;
  int? _lastVoiced;
  bool _done = false;
  final _pitches = <double>[];
  final _recent = <double>[];

  bool get started => _start != null;
  bool get done => _done;

  /// Nothing was voiced at all.
  bool get heardNothing => _done && !started;

  /// From the start of the sound to its last voiced frame.
  Duration get held =>
      started ? frame * (_lastVoiced! - _start! + 1) : Duration.zero;

  /// Median pitch of the whole sound so far (Hz).
  double? get pitch => median(_pitches);

  /// Pitch of the last few voiced frames, for a live display (Hz).
  double? get livePitch => median(_recent);

  /// Feeds the next 20 ms frame.
  void add(VoiceFrame f) {
    if (_done) return;
    _frames++;
    final i = _frames - 1;
    if (f.voiced) {
      _run++;
      _gap = 0;
      if (!started && _run * 20 >= minStart.inMilliseconds) {
        _start = i - _run + 1;
      }
      if (started) {
        _lastVoiced = i;
        _pitches.add(f.pitch!);
        _recent.add(f.pitch!);
        if (_recent.length > 5) _recent.removeAt(0);
      }
    } else {
      _run = 0;
      if (started) {
        _gap++;
        if (_gap * 20 > maxGap.inMilliseconds) _done = true;
      } else if (_frames * 20 >= noStart.inMilliseconds) {
        _done = true;
      }
    }
    if (held >= maxHeld) _done = true;
  }

  /// Ends the try now (time limit, tap, app paused).
  void finish() => _done = true;
}

/// Stars for holding a sound: 3 s, 5 s, 8 s. Children of 5 to 8 hold a
/// vowel for about 8 to 12 s at most.
int holdStars(Duration held) {
  final s = held.inMilliseconds / 1000;
  if (s >= 8) return 3;
  if (s >= 5) return 2;
  if (s >= 3) return 1;
  return 0;
}

/// Stars for speaking lower than the own voice by [semitones] (negative
/// when lower). The low range is narrower than the high one.
int lowStars(double semitones) {
  final down = -semitones;
  if (down >= 5) return 3;
  if (down >= 3) return 2;
  if (down >= 1.5) return 1;
  return 0;
}

/// Stars for speaking higher than the own voice by [semitones].
int highStars(double semitones) {
  if (semitones >= 7) return 3;
  if (semitones >= 4) return 2;
  if (semitones >= 2) return 1;
  return 0;
}
