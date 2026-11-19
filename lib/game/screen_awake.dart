// Speaking counts like touching: while the child talks to the phone, the
// screen must not dim and go off (a voice game is played without touching).
// Android (MainActivity.kt, channel "de.sharedinbox.pp2/screen") keeps the
// screen on while asked to; releasing it pokes the system's idle timer
// (the window manager's wake lock has ON_AFTER_RELEASE), so the usual
// screen timeout starts again when the child's recording is over, as after
// a touch. One difference: that poke does not change the lights, so the
// screen goes off at the end without dimming first. Without speech the
// screen goes off as always, even while the mic is open.
import 'dart:async';

import 'package:flutter/services.dart';

class ScreenAwake {
  /// [keepOn] tells the phone (tests pass their own).
  ScreenAwake({Future<void> Function(bool on)? keepOn})
    : _keepOn = keepOn ?? _platform;

  static final instance = ScreenAwake();

  static const _channel = MethodChannel('de.sharedinbox.pp2/screen');

  final Future<void> Function(bool on) _keepOn;

  /// Kept on at least this long after the last voice (at most twice as
  /// long), then the system's timeout runs.
  static const hold = Duration(seconds: 2);

  bool _on = false;
  bool _again = false;

  /// The child is speaking (until the recording ends). Cheap: called for
  /// every piece of sound.
  void voice() {
    if (_on) {
      _again = true;
      return;
    }
    _on = true;
    _keepOn(true);
    Timer(hold, _check);
  }

  void _check() {
    if (_again) {
      _again = false;
      Timer(hold, _check);
      return;
    }
    _on = false;
    _keepOn(false);
  }

  static Future<void> _platform(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepOn', on);
    } catch (_) {
      // not Android (or no engine): the screen behaves as always
    }
  }
}
