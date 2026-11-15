// Wrappers around the real devices that write to an [IoLog], so a test on a
// phone sees when the real TTS, players and microphone started and ended.
import 'dart:async';
import 'dart:typed_data';

import 'package:phoneme_party/game/game_io.dart';

import 'fakes.dart';

class LoggedMic implements MicSource {
  LoggedMic(this.log, this.inner, {this.onStart});

  final IoLog log;
  final MicSource inner;

  /// Called when recording has started (e.g. to let a "child" speak).
  final void Function()? onStart;
  bool _on = false;

  @override
  Future<bool> hasPermission() => inner.hasPermission();

  @override
  Future<Stream<Uint8List>> start({bool voiceProcessing = true}) async {
    final s = await inner.start(voiceProcessing: voiceProcessing);
    if (!_on) log.on('mic', 'real');
    _on = true;
    onStart?.call();
    return s;
  }

  @override
  Future<void> stop() async {
    await inner.stop();
    if (_on) log.off('mic');
    _on = false;
  }

  @override
  Future<void> dispose() => inner.dispose();
}

class LoggedSpeaker implements Speaker {
  LoggedSpeaker(this.log, this.inner, {this.onDone});

  final IoLog log;
  final Speaker inner;

  /// Called with the text when [speak] completed (e.g. to let a "child"
  /// answer).
  final void Function(String text)? onDone;
  int _id = 0;
  bool _on = false;

  @override
  Future<void> setLanguage(String lang) => inner.setLanguage(lang);

  @override
  Future<void> speak(String text, {double pitch = 1}) async {
    final id = ++_id;
    if (_on) log.off('tts');
    log.on('tts', text);
    _on = true;
    try {
      await inner.speak(text, pitch: pitch);
      onDone?.call(text);
    } finally {
      if (id == _id && _on) {
        log.off('tts');
        _on = false;
      }
    }
  }

  @override
  Future<void> stop() async {
    _id++;
    await inner.stop();
    if (_on) log.off('tts');
    _on = false;
  }
}

class LoggedOut implements SoundOut {
  LoggedOut(this.log, this.name, this.inner) {
    _sub = inner.onComplete.listen((_) {
      if (_on) log.off(name);
      _on = false;
    });
  }

  final IoLog log;
  final String name;
  final SoundOut inner;
  late final StreamSubscription<void> _sub;
  bool _on = false;
  int plays = 0;

  @override
  bool get playsFromMemory => inner.playsFromMemory;

  @override
  Future<void> play(Uint8List wav) async {
    if (_on) log.off(name);
    plays++;
    log.on(name, '${(wav.length - 44) ~/ 32}ms');
    _on = true;
    await inner.play(wav);
  }

  @override
  Future<void> stop() async {
    await inner.stop();
    if (_on) log.off(name);
    _on = false;
  }

  @override
  Stream<void> get onComplete => inner.onComplete;

  @override
  Future<void> dispose() async {
    await _sub.cancel();
    await inner.dispose();
  }
}
