import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/game/screen_awake.dart';
import 'package:phoneme_party/quiz/word_listener.dart';
import 'package:phoneme_party/voice/voice_listener.dart';
import 'package:phoneme_party/voice/voice_take.dart';

import 'support/fakes.dart';
import 'support/sounds.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('speaking keeps the screen on until shortly after the last voice', () {
    final calls = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('de.sharedinbox.pp2/screen'),
          (call) async {
            expect(call.method, 'keepOn');
            calls.add(call.arguments as bool);
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('de.sharedinbox.pp2/screen'),
            null,
          ),
    );
    fakeAsync((async) {
      final s = ScreenAwake.instance;
      s.voice();
      async.flushMicrotasks();
      expect(calls, [true]);
      // talking on for 3 s, a piece every 100 ms: asked only once
      for (var i = 0; i < 30; i++) {
        async.elapse(const Duration(milliseconds: 100));
        s.voice();
      }
      expect(calls, [true]);
      async.elapse(ScreenAwake.hold - const Duration(milliseconds: 100));
      expect(calls, [true], reason: 'still within the hold');
      async.elapse(ScreenAwake.hold);
      expect(calls, [true, false], reason: 'the usual timeout runs again');
    });
  });

  test('the word listener reports speech, not silence', () {
    fakeAsync((async) {
      final log = IoLog(() => async.elapsed);
      final mic = FakeMic(log, () => Child.silent);
      final l = WordListener(mic);
      l.listen();
      async.elapse(const Duration(seconds: 12));
      expect(mic.voices, 0, reason: 'nobody spoke');
      mic.script = () => [...noise(0.3), ...voice(250, 1), ...noise(2)];
      l.listen();
      async.elapse(const Duration(seconds: 5));
      expect(mic.voices, greaterThan(0));
    });
  });

  test('the voice listener reports a held sound, not silence', () {
    fakeAsync((async) {
      final log = IoLog(() => async.elapsed);
      final mic = FakeMic(log, () => Child.silent);
      final l = VoiceListener(mic);
      l.listen(VoiceTake());
      async.elapse(const Duration(seconds: 10));
      expect(mic.voices, 0, reason: 'nobody sang');
      mic.script = () => [...noise(0.3), ...voice(250, 2), ...noise(1)];
      l.listen(VoiceTake());
      async.elapse(const Duration(seconds: 5));
      expect(mic.voices, greaterThan(0));
    });
  });
}
