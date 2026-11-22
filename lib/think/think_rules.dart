// The rounds of the thinking games, made from think_data.dart and the
// pictures of the phrase book.
import 'dart:math' as math;

import '../data/phrases.dart';
import '../quiz/facts.dart';
import 'feelings_data.dart';
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
/// ones are other riddles' things that no clue fits.
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
/// ([oddKinds], from the facts) and one of another kind. A picture takes
/// part only in its one kind (a fish is an animal and food: never). The
/// odd one is clearly not of the three's kind, and the three clearly not
/// of the odd one's (a cow might be food: never three animals and a
/// pizza), and no other property singles one of the four out (never
/// frog, flamingo, shark and a scarf: the flamingo is the only one that
/// flies), so there is exactly one answer.
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
  final factOf = <Phrase, Fact>{};
  for (final p in book.phrases) {
    final f = facts.of(p);
    if (f == null) continue;
    final mine = f.yes.intersection(kinds);
    if (mine.length != 1) continue;
    byKind[mine.single]!.add(p);
    factOf[p] = f;
  }
  bool apart(Prop a, Prop b) =>
      a != b && !oddNotTogether.any((s) => s.containsAll({a.name, b.name}));
  final out = <ThinkQuestion>[];
  final odds = <Phrase>{};
  Prop? last;
  for (var tries = 0; out.length < count && tries < 300; tries++) {
    final kind = kinds.elementAt(rng.nextInt(kinds.length));
    // not the same kind twice in a row
    if (kind == last) continue;
    final others = [
      for (final k in kinds)
        if (apart(kind, k)) k,
    ]..shuffle(rng);
    Phrase? pick;
    List<Phrase>? three;
    for (final ok in others) {
      // the three: of [kind], clearly not of [ok]
      final group = [
        for (final p in byKind[kind]!)
          if (factOf[p]!.truth(ok) == Truth.no) p,
      ];
      if (group.length < 3) continue;
      final cands = [
        for (final p in byKind[ok]!)
          if (!odds.contains(p) && factOf[p]!.truth(kind) == Truth.no) p,
      ];
      if (cands.isEmpty) continue;
      // no second answer: no other property (flies, cold, ...) may single
      // out one of the four (frog, flamingo, shark and a scarf: the
      // flamingo flies)
      for (var i = 0; i < 30; i++) {
        final c = cands[rng.nextInt(cands.length)];
        final g = (group..shuffle(rng)).take(3).toList();
        final four = [
          for (final p in [...g, c]) factOf[p]!,
        ];
        if (singledOut(four, {kind, ok}) != null) continue;
        pick = c;
        three = g;
        break;
      }
      if (pick != null) break;
    }
    if (pick == null || three == null) continue;
    odds.add(pick);
    last = kind;
    out.add(
      ThinkQuestion(
        [
          oddQuestion[code]!,
          // after a wrong tap: what the three have in common
          oddHints[kind.name]![code]!,
        ],
        [pick, ...three]..shuffle(rng),
        pick,
        because: oddKinds[kind.name]![code],
      ),
    );
  }
  return out;
}

/// The property besides [skip] by which one of [four] differs clearly
/// from the three others (all clearly the other way), or null: then only
/// the kind tells the odd one.
Prop? singledOut(List<Fact> four, Set<Prop> skip) {
  for (final p in Prop.values) {
    if (skip.contains(p)) continue;
    for (final x in four) {
      final t = x.truth(p);
      if (t == Truth.unclear) continue;
      final other = t == Truth.yes ? Truth.no : Truth.yes;
      if (four.every((y) => identical(y, x) || y.truth(p) == other)) return p;
    }
  }
  return null;
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

/// The faces of all feelings in [lang], as pictures to tap (one instance
/// each: options are compared by identity).
Map<Feeling, Phrase> feelingFaces(String lang) {
  final names = feelingNames[_code(lang)]!;
  return {
    for (final f in Feeling.values)
      f: Phrase(text: names[f]!, emoji: feelingEmoji[f]!, ipa: '', level: 0),
  };
}

/// [count] stories of "How do I feel?", each with a different feeling as
/// the answer, and [options] - 1 faces that clearly do not fit. After the
/// right face: what helps.
List<ThinkQuestion> makeFeelingsRound(
  String lang,
  math.Random rng, {
  int count = 6,
  int options = 3,
}) {
  final code = _code(lang);
  final faces = feelingFaces(lang);
  final out = <ThinkQuestion>[];
  final answers = <Feeling>{};
  for (final st in [...feelingStories]..shuffle(rng)) {
    if (out.length == count) break;
    final say = st.say[code];
    final help = st.help[code];
    if (say == null || help == null || answers.contains(st.yes)) continue;
    final wrong = [
      for (final f in Feeling.values)
        if (f != st.yes && !st.maybe.contains(f)) faces[f]!,
    ]..shuffle(rng);
    if (wrong.length < options - 1) continue;
    answers.add(st.yes);
    out.add(
      ThinkQuestion(
        ['$say ${feelingQuestion[code]}'],
        [faces[st.yes]!, ...wrong.take(options - 1)]..shuffle(rng),
        faces[st.yes]!,
        because: help,
      ),
    );
  }
  return out;
}

/// [count] questions of "Feeling faces": a feeling is named, [options]
/// faces are shown. Every feeling once while there are enough.
List<ThinkQuestion> makeFacesRound(
  String lang,
  math.Random rng, {
  int count = 6,
  int options = 4,
}) {
  final code = _code(lang);
  final faces = feelingFaces(lang);
  final question = faceQuestion[code]!;
  final order = <Feeling>[];
  while (order.length < count) {
    order.addAll([...Feeling.values]..shuffle(rng));
  }
  return [
    for (final f in order.take(count))
      ThinkQuestion(
        [question.replaceAll('{f}', faces[f]!.text)],
        [
          faces[f]!,
          ...([...Feeling.values]
                ..remove(f)
                ..shuffle(rng))
              .take(options - 1)
              .map((o) => faces[o]!),
        ]..shuffle(rng),
        faces[f]!,
      ),
  ];
}
