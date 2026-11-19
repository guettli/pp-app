// Speaking counts like touching: while the child talks to the phone, the
// screen must not dim and go off (a voice game is played without touching).
// Android (MainActivity.kt, channel "de.sharedinbox.pp2/screen") keeps the
// screen on while asked to; releasing it pokes the system's idle timer
// (the window manager's wake lock has ON_AFTER_RELEASE), so the usual
// screen timeout starts from the last word, as from the last touch. Without
// speech the screen goes off as always, even while the mic is open.
import 'dart:async';

import 'package:flutter/services.dart';

class ScreenAwake {
  ScreenAwake._();

  static final instance = ScreenAwake._();

  static const _channel = MethodChannel('de.sharedinbox.pp2/screen');

  /// Kept on at least this long after the last voice (at most twice as
  /// long), then the system's timeout runs.
  static const hold = Duration(seconds: 2);

  bool _on = false;
  bool _again = false;

  /// The child is speaking. Cheap: called for every piece of sound.
  void voice() {
    if (_on) {
      _again = true;
      return;
    }
    _on = true;
    _set(true);
    Timer(hold, _check);
  }

  void _check() {
    if (_again) {
      _again = false;
      Timer(hold, _check);
      return;
    }
    _on = false;
    _set(false);
  }

  static Future<void> _set(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepOn', on);
    } catch (_) {
      // not Android (or no engine): the screen behaves as always
    }
  }
}
