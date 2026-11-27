// Where the right picture goes in a round. A plain shuffle per question
// puts it in the same place several times in a row now and then (in one
// round of "What do I need?" first 5 of 6 times): a young child who taps
// the same spot again and again is then right without listening.
import 'dart:math' as math;

/// The answer's place for each of [count] questions with [options]
/// places: every place equally often (one more at most), in a random
/// order, never the same place twice in a row.
List<int> answerSlots(int count, int options, math.Random rng) {
  final slots = <int>[];
  while (slots.length < count) {
    final cycle = [for (var i = 0; i < options; i++) i]..shuffle(rng);
    // the end of one cycle and the start of the next: not the same
    if (slots.isNotEmpty && options > 1 && cycle.first == slots.last) {
      final j = 1 + rng.nextInt(options - 1);
      cycle[0] = cycle[j];
      cycle[j] = slots.last;
    }
    slots.addAll(cycle);
  }
  return slots.take(count).toList();
}

/// [options] with [answer] moved to [slot] (it trades places with the
/// one there; the others keep their random order).
List<T> withAnswerAt<T>(List<T> options, T answer, int slot) {
  final o = [...options];
  final i = o.indexOf(answer);
  final j = slot % o.length;
  o[i] = o[j];
  o[j] = answer;
  return o;
}
