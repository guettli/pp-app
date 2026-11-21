// The rounds of the thinking games, made from think_data.dart and the
// pictures of the phrase book.
import 'dart:math' as math;

import '../data/phrases.dart';
import '../quiz/facts.dart';
import 'think_data.dart';

/// One question: what the phone says (one clue, or several said one
/// after the other) and the pictures to tap.
class ThinkQuestion {
  const ThinkQuestion(
    this.clues,
    this.options,
    this.answer, {
    this.scene,
    this.because,
  });

  final List<String> clues;

  /// In the order shown; contains [answer].
  final List<Phrase> options;
  final Phrase answer;

  /// A picture of where we are, shown above the options ("Who lives
  /// here?": 🌊).
  final String? scene;

  /// Said after the right tap: why it is right ("The others are all
  /// animals.").
  final String? because;

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

/// [count] questions of "Odd one out": three pictures of one kind
/// ([oddKinds], from the facts) and one of another kind. Only pictures of
/// exactly one kind take part (a fish is an animal and food).
List<ThinkQuestion> makeOddRound(
  PhraseBook book,
  Facts facts,
  math.Random rng, {
  int count = 6,
}) {
  final code = _code(book.lang);
  final kinds = {
    for (final k in oddKinds.keys)
      if (oddKinds[k]![code] != null) Prop.values.byName(k),
  };
  final byKind = <Prop, List<Phrase>>{for (final k in kinds) k: []};
  for (final p in book.phrases) {
    final f = facts.of(p);
    if (f == null) continue;
    final mine = f.yes.intersection(kinds);
    if (mine.length != 1 || f.unclear.intersection(kinds).isNotEmpty) {
      continue;
    }
    byKind[mine.single]!.add(p);
  }
  bool apart(Prop a, Prop b) =>
      a != b && !oddNotTogether.any((s) => s.containsAll({a.name, b.name}));
  final groups = [
    for (final k in kinds)
      if (byKind[k]!.length >= 3) k,
  ];
  final out = <ThinkQuestion>[];
  final odds = <Phrase>{};
  Prop? last;
  for (var tries = 0; out.length < count && tries < 200; tries++) {
    if (groups.isEmpty) break;
    final kind = groups[rng.nextInt(groups.length)];
    // not the same kind twice in a row while there are others
    if (kind == last && groups.length > 1) continue;
    final others = [
      for (final k in kinds)
        if (apart(kind, k))
          for (final p in byKind[k]!)
            if (!odds.contains(p)) p,
    ];
    if (others.isEmpty) continue;
    final odd = others[rng.nextInt(others.length)];
    final three = ([...byKind[kind]!]..shuffle(rng)).take(3).toList();
    odds.add(odd);
    last = kind;
    out.add(
      ThinkQuestion(
        [oddQuestion[code]!],
        [odd, ...three]..shuffle(rng),
        odd,
        because: oddKinds[kind.name]![code],
      ),
    );
  }
  return out;
}

/// [count] places of "Who lives here?", each with one animal that lives
/// there and [options] - 1 that clearly do not.
List<ThinkQuestion> makeHomeRound(
  PhraseBook book,
  math.Random rng, {
  int count = 6,
  int options = 3,
}) {
  final code = _code(book.lang);
  final out = <ThinkQuestion>[];
  for (final h in [...habitats]..shuffle(rng)) {
    if (out.length == count) break;
    final say = h.say[code];
    if (say == null) continue;
    final yes = [for (final e in h.yes) ?pictureOf(book, e)];
    if (yes.isEmpty) continue;
    final answer = yes[rng.nextInt(yes.length)];
    final lives = {...h.yes, ...h.maybe}.map(bareEmoji).toSet();
    final wrong = [
      for (final e in habitatAnimals)
        if (!lives.contains(bareEmoji(e))) ?pictureOf(book, e),
    ]..shuffle(rng);
    if (wrong.length < options - 1) continue;
    out.add(
      ThinkQuestion(
        [say],
        [answer, ...wrong.take(options - 1)]..shuffle(rng),
        answer,
        scene: h.scene,
      ),
    );
  }
  return out;
}
