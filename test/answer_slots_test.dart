// The right picture is spread over the places: a child who always taps
// the same spot is not right by chance.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/game/answer_slots.dart';
import 'package:phoneme_party/think/think_rules.dart';

void main() {
  test('every place about equally often, never twice in a row', () {
    for (var seed = 0; seed < 300; seed++) {
      for (final (count, options) in [(6, 3), (6, 4), (8, 4), (3, 3), (7, 2)]) {
        final s = answerSlots(count, options, math.Random(seed));
        expect(s, hasLength(count));
        for (var p = 0; p < options; p++) {
          expect(
            s.where((x) => x == p).length,
            lessThanOrEqualTo((count / options).ceil()),
            reason: '$s',
          );
        }
        for (var i = 1; i < s.length; i++) {
          expect(s[i], isNot(s[i - 1]), reason: '$s');
        }
      }
    }
  });

  test('the answer moves, the others stay', () {
    expect(withAnswerAt(['a', 'b', 'c'], 'a', 2), ['c', 'b', 'a']);
    expect(withAnswerAt(['a', 'b', 'c'], 'b', 1), ['a', 'b', 'c']);
  });

  test('feeling faces: the right face moves round', () {
    for (var seed = 0; seed < 50; seed++) {
      final round = makeFacesRound('de-DE', math.Random(seed));
      final at = [for (final q in round) q.options.indexOf(q.answer)];
      for (var i = 1; i < at.length; i++) {
        expect(at[i], isNot(at[i - 1]), reason: '$at');
      }
    }
  });
}
