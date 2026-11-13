import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/phonetics/endpointer.dart';

const sr = 16000;

/// [ms] of a 220 Hz tone with peak [amp] (amp 0 = digital silence).
List<double> tone(int ms, double amp) => List.generate(
  sr * ms ~/ 1000,
  (i) => amp * math.sin(2 * math.pi * 220 * i / sr),
);

/// [ms] of deterministic noise with peak [amp].
List<double> noise(int ms, double amp) {
  final r = math.Random(1);
  return List.generate(sr * ms ~/ 1000, (_) => amp * (r.nextDouble() * 2 - 1));
}

/// Feeds [audio] in 100 ms chunks, returns (event, time in ms) pairs.
List<(EndpointEvent, int)> run(Endpointer ep, List<double> audio) {
  final out = <(EndpointEvent, int)>[];
  const chunk = sr ~/ 10;
  for (var i = 0; i < audio.length; i += chunk) {
    final ev = ep.add(audio.sublist(i, math.min(i + chunk, audio.length)));
    if (ev != EndpointEvent.none) out.add((ev, (i + chunk) * 1000 ~/ sr));
  }
  return out;
}

void main() {
  test('speech followed by a pause ends the recording', () {
    final ep = Endpointer();
    final events = run(ep, [
      ...tone(400, 0), // reaction time
      ...tone(800, 0.3), // "Die Box"
      ...tone(1500, 0),
    ]);
    expect(events.map((e) => e.$1), [
      EndpointEvent.speechStarted,
      EndpointEvent.speechEnded,
    ]);
    // ends after 1 s of silence, i.e. at about 400 + 800 + 1000 ms
    expect(events.last.$2, inInclusiveRange(2200, 2300));
    expect(ep.done, isTrue);
    expect(ep.heardSpeech, isTrue);
  });

  test('a short pause between words does not end the recording', () {
    final events = run(Endpointer(), [
      ...tone(300, 0),
      ...tone(300, 0.3), // "Die"
      ...tone(600, 0), // child thinks
      ...tone(400, 0.3), // "Box"
      ...tone(1200, 0),
    ]);
    expect(events.map((e) => e.$1), [
      EndpointEvent.speechStarted,
      EndpointEvent.speechEnded,
    ]);
    expect(events.last.$2, greaterThanOrEqualTo(2600));
  });

  test('silence times out', () {
    final ep = Endpointer();
    final events = run(ep, tone(6000, 0));
    expect(events.single.$1, EndpointEvent.noSpeech);
    expect(events.single.$2, inInclusiveRange(5000, 5100));
    expect(ep.heardSpeech, isFalse);
  });

  test('steady background noise is not speech', () {
    // louder than minLevel, but present from the start (fan, traffic)
    final events = run(Endpointer(), noise(6000, 0.06));
    expect(events.single.$1, EndpointEvent.noSpeech);
  });

  test('speech over background noise is detected', () {
    final events = run(Endpointer(), [
      ...noise(400, 0.06),
      ...[for (final (i, s) in noise(800, 0.06).indexed) s + tone(800, 0.4)[i]],
      ...noise(1500, 0.06),
    ]);
    expect(events.map((e) => e.$1), [
      EndpointEvent.speechStarted,
      EndpointEvent.speechEnded,
    ]);
  });

  test('a click is not speech', () {
    final events = run(Endpointer(), [
      ...tone(400, 0),
      ...tone(60, 0.5), // tap on the phone
      ...tone(5000, 0),
    ]);
    expect(events.single.$1, EndpointEvent.noSpeech);
  });

  test('nothing is reported after the end', () {
    final ep = Endpointer();
    run(ep, [...tone(400, 0), ...tone(500, 0.3), ...tone(1200, 0)]);
    expect(ep.done, isTrue);
    expect(run(ep, tone(1000, 0.3)), isEmpty);
  });

  test('PCM16 chunks may split a sample', () {
    // the same audio fed as whole samples and as odd-sized byte chunks
    final audio = [...tone(400, 0), ...tone(500, 0.3), ...tone(1200, 0)];
    final bytes = ByteData(audio.length * 2);
    for (var i = 0; i < audio.length; i++) {
      bytes.setInt16(i * 2, (audio[i] * 32767).round(), Endian.little);
    }
    final all = bytes.buffer.asUint8List();
    final ep = Endpointer();
    final events = <EndpointEvent>[];
    for (var i = 0; i < all.length; i += 1001) {
      final ev = ep.addPcm16(
        Uint8List.sublistView(all, i, math.min(i + 1001, all.length)),
      );
      if (ev != EndpointEvent.none) events.add(ev);
    }
    expect(events, [EndpointEvent.speechStarted, EndpointEvent.speechEnded]);
    expect(ep.level, lessThan(0.001));
  });

  test('level reflects the last frame', () {
    final ep = Endpointer()..add(tone(100, 0.3));
    expect(ep.level, closeTo(0.3 / math.sqrt2, 0.01));
  });

  test('takes Float32List too', () {
    final ep = Endpointer()..add(Float32List.fromList(tone(100, 0.3)));
    expect(ep.level, greaterThan(0.1));
  });
}
