// "Listen closely": the phone says a word, the child taps its picture
// among four. No microphone, no reading.
import 'dart:math' as math;

import '../data/phrases.dart';

/// One question: the word that is said and the pictures to choose from
/// (the answer among them, in random order).
class ListenQuestion {
  const ListenQuestion(this.answer, this.options);

  final Phrase answer;
  final List<Phrase> options;

  @override
  String toString() =>
      '${answer.text}: ${options.map((o) => o.text).join(', ')}';
}

/// How alike two words sound, 0..1 (higher: easier to confuse).
typedef Closeness = double Function(Phrase a, Phrase b);

/// Whether [a] and [b] must not be options of the same question: the same
/// picture, or a word that is said the same (one accepted word of [a] is
/// also one of [b], or both sound exactly alike).
bool sameForTheEar(Phrase a, Phrase b) {
  if (a.emoji == b.emoji) return true;
  String norm(String ipa) => ipa.replaceAll(RegExp(r'[/\[\]ˈˌ.\s]'), '');
  for (final x in a.accepted) {
    for (final y in b.accepted) {
      if (x.text.toLowerCase() == y.text.toLowerCase()) return true;
      if (norm(x.ipa) == norm(y.ipa)) return true;
    }
  }
  return false;
}

/// Words this close (see [Closeness]) sound the same to a child.
const sameSound = 0.95;

/// [count] questions with [options] pictures each, answers from [pool]
/// (no answer twice). The first half gets random wrong pictures; in the
/// second half one wrong picture is the word from [pool] that sounds most
/// like the answer (Maus / Haus), so the round gets harder.
List<ListenQuestion> makeListenRound(
  List<Phrase> pool,
  math.Random rng, {
  required Closeness closeness,
  int count = 8,
  int options = 4,
}) {
  final answers = [...pool]..shuffle(rng);
  final round = <ListenQuestion>[];
  for (final answer in answers) {
    if (round.length == count) break;
    // scored once per word (the comparison is not free on a cheap phone)
    final close = <Phrase, double>{
      for (final p in pool)
        if (p != answer && !sameForTheEar(p, answer)) p: closeness(p, answer),
    };
    // written differently but said the same: not a fair wrong picture
    close.removeWhere((_, c) => c >= sameSound);
    final others = close.keys.toList();
    if (others.length < options - 1) continue;
    final chosen = <Phrase>[];
    if (round.length >= count ~/ 2) {
      chosen.add(others.reduce((a, b) => close[b]! > close[a]! ? b : a));
    }
    others.shuffle(rng);
    for (final p in others) {
      if (chosen.length == options - 1) break;
      if (chosen.any((c) => c == p || sameForTheEar(c, p))) continue;
      chosen.add(p);
    }
    if (chosen.length < options - 1) continue;
    round.add(ListenQuestion(answer, [answer, ...chosen]..shuffle(rng)));
  }
  return round;
}
