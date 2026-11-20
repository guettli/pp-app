// The rounds of the thinking games, made from think_data.dart and the
// pictures of the phrase book.
import 'dart:math' as math;

import '../data/phrases.dart';
import 'think_data.dart';

/// One question: what the phone says (one clue, or several said one
/// after the other) and the pictures to tap.
class ThinkQuestion {
  const ThinkQuestion(this.clues, this.options, this.answer);

  final List<String> clues;

  /// In the order shown; contains [answer].
  final List<Phrase> options;
  final Phrase answer;

  @override
  String toString() =>
      '${clues.last}: ${options.map((o) => o.emoji).join(' ')} -> '
      '${answer.emoji}';
}

/// Emoji without the variation selector (☂ and ☂️ are the same picture).
String bareEmoji(String e) => e.replaceAll('️', '');

/// The book's picture for [emoji], or null.
Phrase? pictureOf(PhraseBook book, String emoji) {
  final bare = bareEmoji(emoji);
  for (final p in book.phrases) {
    if (bareEmoji(p.emoji) == bare) return p;
  }
  return null;
}

String _code(String lang) => lang.split('-').first;

/// [count] problems of "What do I need?", each with one picture that
/// solves it and [options] - 1 that clearly do not.
List<ThinkQuestion> makeNeedsRound(
  PhraseBook book,
  math.Random rng, {
  int count = 6,
  int options = 3,
}) {
  final code = _code(book.lang);
  final pool = {
    for (final n in needs) ...n.yes.map(bareEmoji),
    ...needExtras.map(bareEmoji),
  };
  final out = <ThinkQuestion>[];
  final answers = <String>{};
  for (final need in [...needs]..shuffle(rng)) {
    if (out.length == count) break;
    final say = need.say[code];
    if (say == null) continue;
    final yes = [
      for (final e in need.yes)
        if (!answers.contains(bareEmoji(e)) && pictureOf(book, e) != null) e,
    ];
    if (yes.isEmpty) continue;
    final answer = pictureOf(book, yes[rng.nextInt(yes.length)])!;
    final helps = {...need.yes, ...need.maybe}.map(bareEmoji).toSet();
    final wrong = [
      for (final e in pool)
        if (!helps.contains(e) && pictureOf(book, e) != null)
          pictureOf(book, e)!,
    ]..shuffle(rng);
    if (wrong.length < options - 1) continue;
    answers.add(bareEmoji(answer.emoji));
    out.add(
      ThinkQuestion(
        ['$say ${needQuestion[code]}'],
        [answer, ...wrong.take(options - 1)]..shuffle(rng),
        answer,
      ),
    );
  }
  return out;
}

/// [count] riddles of "Who am I?" with [options] pictures each; the wrong
/// ones are other riddles' things the last clue does not fit.
List<ThinkQuestion> makeRiddleRound(
  PhraseBook book,
  math.Random rng, {
  int count = 6,
  int options = 4,
}) {
  final code = _code(book.lang);
  bool alike(Riddle a, Riddle b) =>
      a.alike.map(bareEmoji).contains(bareEmoji(b.emoji)) ||
      b.alike.map(bareEmoji).contains(bareEmoji(a.emoji));
  final out = <ThinkQuestion>[];
  for (final r in [...riddles]..shuffle(rng)) {
    if (out.length == count) break;
    final clues = r.clues[code];
    final answer = pictureOf(book, r.emoji);
    if (clues == null || answer == null) continue;
    final wrong = [
      for (final o in riddles)
        if (o != r && !alike(r, o) && pictureOf(book, o.emoji) != null)
          pictureOf(book, o.emoji)!,
    ]..shuffle(rng);
    if (wrong.length < options - 1) continue;
    out.add(
      ThinkQuestion(
        clues,
        [answer, ...wrong.take(options - 1)]..shuffle(rng),
        answer,
      ),
    );
  }
  return out;
}
