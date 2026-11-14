import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/voice/voice_listener.dart';
import 'package:phoneme_party/voice/voice_take.dart';

import 'support/fakes.dart';
import 'support/sounds.dart';

void main() {
  test('a start cancelled while slow does not stop the next recording', () {
    fakeAsync((async) {
      final log = IoLog(() => async.elapsed);
      final mic = FakeMic(log, () => Child.silent)
        ..script = () => [...noise(0.3), ...voice(250, 3), ...noise(1)];
      final l = VoiceListener(mic);
      VoiceTake? first = VoiceTake(), second;
      mic.startup = const Duration(milliseconds: 500);
      l.listen(first).then((t) => first = t);
      async.elapse(const Duration(milliseconds: 100));
      // the child taps again while the first start is still slow
      mic.startup = const Duration(milliseconds: 50);
      l.cancel();
      l.listen(VoiceTake()).then((t) => second = t);
      async.elapse(const Duration(milliseconds: 1500));
      expect(first, isNull, reason: 'cancelled');
      expect(mic.recording, isTrue, reason: 'the second one still records');
      async.elapse(const Duration(seconds: 5));
      expect(second?.held.inMilliseconds, closeTo(3000, 150));
      expect(mic.recording, isFalse);
    });
  });
}
