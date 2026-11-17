// What everybody knows about the things in the pictures (assets/facts/
// facts.tsv), and the quiz questions made from it: "What can fly? Tree,
// bird or house?". The child answers by saying the word.
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../data/phrases.dart';

/// A property a thing has or not; the same in every language.
enum Prop {
  animal,
  flies,
  swims,
  walks,
  talks,
  eat,
  drink,
  wear,
  plant,
  wheels,
  music,
  shines,
  cold,
  body,
  number,
}

/// Whether a thing has a [Prop]. Only [no] things are offered as wrong
/// answers; [unclear] ones (can a chicken fly?) are never asked about.
enum Truth { yes, no, unclear }

class Fact {
  const Fact({
    required this.emoji,
    this.sizeCm,
    this.weightKg,
    this.yes = const {},
    this.unclear = const {},
  });

  final String emoji;

  /// Rough size and weight, null where it makes no sense (a number, a
  /// body part, the sun).
  final double? sizeCm;
  final double? weightKg;
  final Set<Prop> yes;
  final Set<Prop> unclear;

  Truth truth(Prop p) => yes.contains(p)
      ? Truth.yes
      : unclear.contains(p)
      ? Truth.unclear
      : Truth.no;
}

class Facts {
  Facts(this.byEmoji);

  final Map<String, Fact> byEmoji;

  Fact? of(Phrase p) => byEmoji[p.emoji];

  static const asset = 'assets/facts/facts.tsv';

  static Future<Facts> load() async =>
      Facts.parse(await rootBundle.loadString(asset));

  /// See the header of assets/facts/facts.tsv.
  factory Facts.parse(String tsv) {
    double? num(String s) => s == '-' ? null : double.parse(s);
    Set<Prop> props(String s) => {
      for (final name in s.split(' '))
        if (name.isNotEmpty && name != '-') Prop.values.byName(name),
    };
    final facts = <String, Fact>{};
    for (final (i, line) in tsv.split('\n').indexed) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final f = line.split('\t');
      if (f.length != 6) {
        throw FormatException('facts.tsv line ${i + 1}: 6 columns expected');
      }
      final yes = props(f[4]), unclear = props(f[5]);
      if (yes.intersection(unclear).isNotEmpty) {
        throw FormatException('facts.tsv line ${i + 1}: yes and unclear');
      }
      facts[f[0]] = Fact(
        emoji: f[0],
        sizeCm: num(f[2]),
        weightKg: num(f[3]),
        yes: yes,
        unclear: unclear,
      );
    }
    return Facts(facts);
  }
}

/// Which thing is the most ...: compared by size or weight.
enum Extreme { biggest, smallest, heaviest, lightest }

/// What the phone asks: a [Prop] ("What can fly?") or an [Extreme]
/// ("What is the biggest?").
class Ask {
  const Ask.prop(Prop this.prop) : extreme = null;
  const Ask.extreme(Extreme this.extreme) : prop = null;

  final Prop? prop;
  final Extreme? extreme;

  static final all = [
    for (final p in Prop.values) Ask.prop(p),
    for (final e in Extreme.values) Ask.extreme(e),
  ];

  @override
  bool operator ==(Object other) =>
      other is Ask && other.prop == prop && other.extreme == extreme;

  @override
  int get hashCode => Object.hash(prop, extreme);

  @override
  String toString() => (prop ?? extreme)!.name;
}

class QuizQuestion {
  const QuizQuestion(this.ask, this.options, this.answer);

  final Ask ask;

  /// In the order the phone says them; contains [answer].
  final List<Phrase> options;
  final Phrase answer;

  @override
  String toString() =>
      '$ask: ${options.map((o) => o.text).join(', ')} -> ${answer.text}';
}

/// Things compared by size must differ at least this much, so nobody
/// has to think about whether a dog or a chair is bigger.
const sizeRatio = 4.0;

/// Weight is harder to judge than size: mouse (20 g), ring (10 g) and
/// scarf (200 g) all feel light to a child. So the answer must be at
/// least twenty times heavier (or lighter) than both others.
const weightRatio = 20.0;

/// [sounds similar]: two options must not be confused by the recogniser
/// (or the child), e.g. "Bär" and "Bett".
typedef Similar = bool Function(Phrase a, Phrase b);

/// One question about [ask] from [pool], or null when the pool has no
/// clear answer plus two clear wrong ones.
QuizQuestion? makeQuestion(
  Ask ask,
  List<Phrase> pool,
  Facts facts,
  math.Random rng, {
  Similar? similar,
  Set<String> avoidAnswers = const {},
}) {
  bool apart(List<Phrase> chosen, Phrase p) => chosen.every(
    (c) => c.emoji != p.emoji && !(similar?.call(c, p) ?? false),
  );
  final known = [
    for (final p in pool)
      if (facts.of(p) != null) p,
  ]..shuffle(rng);

  final prop = ask.prop;
  if (prop != null) {
    bool has(Phrase p, Truth t) => facts.of(p)!.truth(prop) == t;
    final rights = known.where((p) => has(p, Truth.yes)).toList();
    final wrongs = known.where((p) => has(p, Truth.no)).toList();
    // a different answer than last time, if there is one
    rights.sort(
      (a, b) =>
          (avoidAnswers.contains(a.text) ? 1 : 0) -
          (avoidAnswers.contains(b.text) ? 1 : 0),
    );
    for (final answer in rights) {
      final chosen = [answer];
      for (final w in wrongs) {
        if (chosen.length == 3) break;
        if (apart(chosen, w)) chosen.add(w);
      }
      if (chosen.length == 3) {
        return QuizQuestion(ask, chosen..shuffle(rng), answer);
      }
    }
    return null;
  }

  final extreme = ask.extreme!;
  final bySize = extreme == Extreme.biggest || extreme == Extreme.smallest;
  final most = extreme == Extreme.biggest || extreme == Extreme.heaviest;
  final ratio = bySize ? sizeRatio : weightRatio;
  double? value(Phrase p) =>
      bySize ? facts.of(p)!.sizeCm : facts.of(p)!.weightKg;
  final measured = known.where((p) => value(p) != null).toList();
  // random tries: the answer must beat both others by [ratio]
  for (var t = 0; t < 60 && measured.length >= 3; t++) {
    final chosen = <Phrase>[];
    for (final p in measured..shuffle(rng)) {
      if (chosen.length == 3) break;
      if (apart(chosen, p)) chosen.add(p);
    }
    if (chosen.length < 3) return null;
    chosen.sort((a, b) => value(a)!.compareTo(value(b)!));
    final answer = most ? chosen[2] : chosen[0];
    if (avoidAnswers.contains(answer.text) && t < 30) continue;
    final next = value(chosen[1])!; // the middle one
    final ok = most
        ? value(answer)! >= next * ratio
        : value(answer)! * ratio <= next;
    if (ok) return QuizQuestion(ask, chosen..shuffle(rng), answer);
  }
  return null;
}

/// Up to [count] questions, each [Ask] at most once, never the same
/// answer twice.
List<QuizQuestion> makeRound(
  List<Phrase> pool,
  Facts facts,
  math.Random rng, {
  int count = 8,
  Similar? similar,
}) {
  final out = <QuizQuestion>[];
  final answers = <String>{};
  final asks = [...Ask.all]..shuffle(rng);
  for (final ask in asks) {
    if (out.length == count) break;
    final q = makeQuestion(
      ask,
      pool,
      facts,
      rng,
      similar: similar,
      avoidAnswers: answers,
    );
    if (q == null || answers.contains(q.answer.text)) continue;
    out.add(q);
    answers.add(q.answer.text);
  }
  return out;
}
