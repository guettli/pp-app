import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/game/feedback.dart';

double peakOf(List<double> a) => a.fold(0.0, (m, v) => math.max(m, v.abs()));

void main() {
  test('praise exists for every study language and star count', () {
    for (final lang in studyLanguages) {
      final all = praise[lang.split('-').first];
      expect(all, isNotNull, reason: lang);
      expect(all!.length, 4);
      for (final list in all) {
        expect(list.length, greaterThanOrEqualTo(3), reason: lang);
        expect(list.toSet().length, list.length, reason: '$lang duplicates');
      }
    }
  });

  test('the same praise never comes twice in a row, and all are used', () {
    final rng = math.Random(1);
    String? last;
    final seen = <String>{};
    for (var i = 0; i < 300; i++) {
      final p = pickPraise('de-DE', 3, rng, avoid: last);
      expect(p, isNot(last));
      expect(praise['de']![3], contains(p));
      seen.add(p);
      last = p;
    }
    expect(seen, praise['de']![3].toSet());
  });

  test('no "try again" when the game moves on', () {
    final rng = math.Random(3);
    for (final lang in studyLanguages) {
      final code = lang.split('-').first;
      expect(movingOn[code], isNotNull, reason: lang);
      for (var i = 0; i < 20; i++) {
        final p = pickPraise(lang, 0, rng, onward: true);
        expect(movingOn[code], contains(p));
        expect(praise[code]![0], isNot(contains(p)));
      }
    }
    // onward only matters for 0 stars
    expect(
      praise['de']![3],
      contains(pickPraise('de-DE', 3, rng, onward: true)),
    );
  });

  test('unknown languages fall back to English', () {
    expect(praise['en']![2], contains(pickPraise('xx', 2, math.Random(0))));
  });

  test('one more try after 0 stars, then the game moves on', () {
    expect(afterResult(0, 1), AfterResult.retry);
    expect(afterResult(0, 2), AfterResult.next);
    expect(afterResult(0, 3), AfterResult.next);
    for (final stars in [1, 2, 3]) {
      expect(afterResult(stars, 1), AfterResult.next);
    }
  });

  test('melodies are short, not too loud and vary', () {
    final rng = math.Random(2);
    for (var stars = 0; stars <= 3; stars++) {
      final sounds = <String>{};
      for (var i = 0; i < 20; i++) {
        final j = jingle(stars, rng);
        expect(j.length / 16000, inInclusiveRange(0.3, 1.5));
        expect(peakOf(j), closeTo(0.5, 1e-6));
        expect(j.any((v) => v.isNaN), isFalse);
        sounds.add('${j.length}-${j[400].toStringAsFixed(4)}');
      }
      expect(sounds.length, greaterThan(3), reason: '$stars stars');
    }
    for (final s in [pling(rng), fanfare(rng)]) {
      expect(peakOf(s), closeTo(0.5, 1e-6));
      expect(s.any((v) => v.isNaN), isFalse);
    }
    expect(pling(rng).length / 16000, closeTo(0.3, 0.01));
    expect(fanfare(rng).length / 16000, inInclusiveRange(1, 2));
    // no click: every melody ends in silence
    for (var stars = 0; stars <= 3; stars++) {
      expect(jingle(stars, rng).last.abs(), lessThan(1e-3));
    }
  });
}
