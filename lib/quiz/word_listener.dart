// The microphone part of the quiz: listen until the child has said a word
// (hands-free, like the word game), and make sure the mic is off again
// however the try ends (done, tap, error, stream end, app paused, screen
// closed). The audio stays in memory for the recogniser only.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../game/game_io.dart';
import '../phonetics/endpointer.dart';
import '../phonetics/recognizer.dart';

/// What [WordListener.listen] heard.
class Heard {
  const Heard(this.speech, this.audio);

  /// Whether the endpointer heard someone speak.
  final bool speech;

  /// Prepared for the recogniser.
  final Float32List audio;
}

class WordListener {
  WordListener(this.mic, {this.noSpeech = const Duration(seconds: 7)});

  final MicSource mic;

  /// The child has to think first: longer than in the word game.
  final Duration noSpeech;
  StreamSubscription<Uint8List>? _sub;
  Completer<Heard?>? _done;
  Endpointer? _ep;
  Timer? _limit;
  Future<void>? _starting;
  final _buffer = BytesBuilder(copy: false);

  bool get listening => _done != null;

  /// RMS of the last 20 ms, for a level meter.
  double get level => _ep?.level ?? 0;

  /// Records until the child has finished speaking ([limit] at most) and
  /// returns it, or null when cancelled. [onChunk] is called for every
  /// piece of sound (for a live display).
  Future<Heard?> listen({
    Duration limit = const Duration(seconds: 12),
    VoidCallback? onChunk,
  }) async {
    await cancel();
    final gen = _gen;
    // A start cancelled meanwhile stops the mic when it is up; that must
    // happen before this start, or it would stop the new recording.
    await _starting;
    // cancelled while waiting (app paused): do not open the mic
    if (gen != _gen) return null;
    final done = _done = Completer<Heard?>();
    final starting = Completer<void>();
    _starting = starting.future;
    final ep = _ep = Endpointer(noSpeechTimeout: noSpeech);
    _buffer.clear();
    try {
      final Stream<Uint8List> stream;
      try {
        stream = await mic.start();
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
          _buffer.add(chunk);
          ep.addPcm16(chunk);
          onChunk?.call();
          if (ep.done) _finishHeard(done);
        },
        onError: (Object e, StackTrace st) {
          debugPrint('recording failed: $e\n$st');
          _finishHeard(done);
        },
        onDone: () => _finishHeard(done),
      );
      // also when the stream stalls
      _limit = Timer(limit, () => _finishHeard(done));
    } catch (e, st) {
      debugPrint('recording failed to start: $e\n$st');
      await _finish(done, null);
    }
    return done.future;
  }

  /// Ends the try now and keeps what was heard (the child tapped).
  Future<void> stopNow() async {
    final c = _done;
    if (c != null) await _finishHeard(c);
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

  Future<void> _finishHeard(Completer<Heard?> c) async {
    if (_done != c) return;
    final speech = _ep?.heardSpeech ?? false;
    // taken before the mic stops, so a late chunk cannot change it
    final bytes = _buffer.takeBytes();
    await _finish(c, Heard(speech, prepareForRecognition(pcm16ToFloat(bytes))));
  }

  /// The mic goes off before anyone hears about the result, so nothing
  /// the game plays next can be recorded.
  Future<void> _finish(Completer<Heard?> c, Heard? result) async {
    if (_done != c) return;
    _done = null;
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
