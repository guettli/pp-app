import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/phonetics/echo_gate.dart';

/// [ms] of 16 kHz PCM16 at [amp] (a 220 Hz tone; 0 = faint noise).
Uint8List pcm(int ms, double amp) {
  final n = ms * 16;
  final b = ByteData(n * 2);
  final rng = math.Random(ms);
  for (var i = 0; i < n; i++) {
    final v = amp == 0
        ? (rng.nextDouble() - 0.5) * 0.001
        : amp * math.sin(2 * math.pi * 220 * i / 16000);
    b.setInt16(i * 2, (v * 32767).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

int ms(Uint8List b) => b.length ~/ 32;

void main() {
  test('drops everything while the phone speaks', () {
    final g = EchoGate();
    expect(g.add(pcm(400, 0.5)), isEmpty);
    expect(g.add(pcm(100, 0)), isEmpty, reason: 'not spoken() yet');
    expect(g.open, isFalse);
  });

  test('opens minSkip after spoken() when it is quiet', () {
    final g = EchoGate()..add(pcm(400, 0.5));
    g.spoken();
    expect(g.add(pcm(20, 0)), isEmpty, reason: 'the first chunk after');
    final kept = g.add(pcm(200, 0));
    expect(g.open, isTrue);
    expect(ms(kept), 200 - 40);
    // from now on everything passes, as it is
    final next = pcm(30, 0.3);
    expect(identical(g.add(next), next), isTrue);
  });

  test('the voice still arriving after spoken() is dropped too', () {
    final g = EchoGate()..add(pcm(400, 0.5));
    g.spoken();
    expect(g.add(pcm(20, 0)), isEmpty, reason: 'the first chunk after');
    expect(g.add(pcm(120, 0.5)), isEmpty, reason: 'still the phone');
    final kept = g.add(pcm(100, 0));
    expect(ms(kept), 100);
    expect(g.quietLevel, lessThan(0.001));
  });

  test('the whole first chunk after spoken() is dropped, even if quiet in '
      'parts (a phone with big buffers)', () {
    final g = EchoGate()..add(pcm(100, 0.5));
    g.spoken();
    // 200 ms delivered at once: recorded before the end, quiet in between
    final late = BytesBuilder()
      ..add(pcm(80, 0.5))
      ..add(pcm(40, 0))
      ..add(pcm(80, 0.5));
    expect(g.add(late.takeBytes()), isEmpty);
    expect(ms(g.add(pcm(100, 0))), 100);
  });

  test('opens after maxSkip even if it never gets quiet', () {
    final g = EchoGate()..add(pcm(400, 0.5));
    g.spoken();
    g.add(pcm(20, 0.5));
    final kept = g.add(pcm(500, 0.5));
    expect(ms(kept), 500 - 280);
    expect(g.quietLevel, isNull);
  });

  test('without a TTS voice it opens at minSkip', () {
    final g = EchoGate()..add(pcm(200, 0));
    g.spoken();
    g.add(pcm(20, 0));
    expect(ms(g.add(pcm(100, 0))), 60);
  });

  test('chunks that do not end on a frame are joined', () {
    final g = EchoGate()..add(pcm(400, 0.5));
    g.spoken();
    final quiet = pcm(200, 0);
    var kept = 0;
    for (var i = 0; i < quiet.length; i += 333) {
      kept += g
          .add(Uint8List.sublistView(quiet, i, math.min(i + 333, quiet.length)))
          .length;
    }
    expect(kept, quiet.length - 60 * 32);
  });

  test('clean (the mic came up after the phrase): only minSkip is dropped, '
      'even if the child already talks', () {
    final g = EchoGate()..spoken(clean: true);
    expect(g.add(pcm(40, 0)), isEmpty);
    final kept = g.add(pcm(200, 0.3));
    expect(ms(kept), 180);
    expect(g.quietLevel, lessThan(0.001), reason: 'the quiet frames before');
  });
}
