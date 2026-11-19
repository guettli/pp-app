// The microphone part of the voice games, in one place: start, feed a
// VoiceTake, and make sure the mic is off again however the try ends
// (done, tap, error, stream end, app paused, screen closed). Audio is only
// analysed, never kept.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../game/game_io.dart';
import 'pitch.dart';
import 'voice_take.dart';

class VoiceListener {
  VoiceListener(this.mic);

  final MicSource mic;
  StreamSubscription<Uint8List>? _sub;
  Completer<VoiceTake?>? _done;
  VoiceTake? _take;
  Timer? _limit;
  Future<void>? _starting;

  bool get listening => _done != null;

  /// Records until [take] is done and returns it, or null when cancelled.
  /// [onFrame] is called for every 20 ms of sound (for a live display).
  Future<VoiceTake?> listen(
    VoiceTake take, {
    void Function(VoiceTake take, VoiceFrame frame)? onFrame,
  }) async {
    await cancel();
    final gen = _gen;
    // A start cancelled meanwhile stops the mic when it is up; that must
    // happen before this start, or it would stop the new recording.
    await _starting;
    // cancelled while waiting (app paused): do not open the mic
    if (gen != _gen) return null;
    final done = _done = Completer<VoiceTake?>();
    final starting = Completer<void>();
    _starting = starting.future;
    _take = take;
    final meter = VoiceMeter();
    try {
      final Stream<Uint8List> stream;
      try {
        stream = await mic.start(voiceProcessing: false);
        if (_done != done) {
          // cancelled while the mic was starting
          await _quietly(mic.stop);
          return null;
        }
      } finally {
        starting.complete();
      }
      _sub = stream.listen(
        (chunk) {
          for (final f in meter.addPcm16(chunk)) {
            take.add(f);
            onFrame?.call(take, f);
          }
          if (take.started) mic.heardVoice();
          if (take.done) _finish(done, take);
        },
        onError: (Object e, StackTrace st) {
          debugPrint('voice recording failed: $e\n$st');
          take.finish();
          _finish(done, take);
        },
        onDone: () {
          take.finish();
          _finish(done, take);
        },
      );
      // if the stream stalls, the take never ends by itself
      _limit = Timer(
        take.noStart + take.maxHeld + const Duration(seconds: 2),
        () {
          take.finish();
          _finish(done, take);
        },
      );
    } catch (e, st) {
      debugPrint('voice recording failed to start: $e\n$st');
      await _finish(done, null);
    }
    return done.future;
  }

  /// Ends the try now and keeps what was heard (the child tapped).
  Future<void> stopNow() async {
    final c = _done;
    final t = _take;
    if (c == null) return;
    t?.finish();
    await _finish(c, t);
  }

  /// Incremented by every [cancel], also when nothing is listening yet.
  int _gen = 0;

  /// Ends the try and drops it (app paused, screen closed).
  Future<void> cancel() async {
    _gen++;
    final c = _done;
    if (c != null) await _finish(c, null);
  }

  Future<void> dispose() async {
    await cancel();
    await _quietly(mic.dispose);
  }

  /// The mic goes off before anyone hears about the result, so nothing
  /// the game plays next can be recorded.
  Future<void> _finish(Completer<VoiceTake?> c, VoiceTake? result) async {
    if (_done != c) return;
    _done = null;
    _take = null;
    _limit?.cancel();
    _limit = null;
    final sub = _sub;
    _sub = null;
    await _quietly(() async => sub?.cancel());
    await _quietly(mic.stop);
    if (!c.isCompleted) c.complete(result);
  }

  static Future<void> _quietly(Future<void> Function() f) async {
    try {
      await f();
    } catch (e, st) {
      debugPrint('mic clean-up failed: $e\n$st');
    }
  }
}
