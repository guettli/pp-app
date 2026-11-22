import 'dart:math' as math;

import '../data/phrases.dart';
import '../phonetics/phoneme_distance.dart';

/// The best option must score at least this ...
const minAnswerScore = 0.5;

/// ... have at least this share of exactly the same sounds (the score
/// counts similar sounds too, which is right for stars but lets "Fisch"
/// pass for "Bus") ...
const minAnswerSame = 0.5;

/// ... and score this much more than the second best, or the child is
/// asked once more instead of being marked wrong for a word the phone
/// misheard.
const minAnswerMargin = 0.2;

/// Share of sounds of [c] that are exactly the expected ones.
double sameShare(Comparison c) {
  final longer = math.max(c.target.length, c.actual.length);
  if (longer == 0) return 1;
  return c.alignment.where((p) => p.target == p.actual).length / longer;
}

/// Which of [options] the child said ([ipa] from the recogniser), or null
/// when that is not clear.
Phrase? heardOption(
  PhonemeComparer comparer,
  List<Phrase> options,
  String ipa,
  String lang, {
  Phrase? echo,
}) {
  if (ipa.isEmpty) return null;
  final scored = [
    for (final o in options)
      (o, [for (final w in o.accepted) comparer.compare(w.ipa, ipa, lang)]),
  ];
  double best(List<Comparison> cs) => cs.map((c) => c.score).reduce(math.max);
  scored.sort((a, b) => best(b.$2).compareTo(best(a.$2)));
  final (option, cs) = scored.first;
  final score = best(cs);
  if (score < minAnswerScore) return null;
  if (cs.map(sameShare).reduce(math.max) < minAnswerSame) return null;
  if (scored.length > 1 && score - best(scored[1].$2) < minAnswerMargin) {
    return null;
  }
  // the child said the word of the question back ("What starts like
  // Blatt?" "Blatt!"): no answer, even if it sounds like one (Blitz)
  if (echo != null) {
    final e = best([
      for (final w in echo.accepted) comparer.compare(w.ipa, ipa, lang),
    ]);
    if (e >= score - minAnswerMargin) return null;
  }
  return option;
}

/// Per option: its best score and best share of the same sounds against
/// [ipa] (what [heardOption] decides on; for quiz reports).
List<({String option, double score, double same})> optionScores(
  PhonemeComparer comparer,
  List<Phrase> options,
  String ipa,
  String lang,
) => [
  for (final o in options)
    if (ipa.isEmpty)
      (option: o.text, score: 0.0, same: 0.0)
    else
      () {
        final cs = [
          for (final w in o.accepted) comparer.compare(w.ipa, ipa, lang),
        ];
        return (
          option: o.text,
          score: cs.map((c) => c.score).reduce(math.max),
          same: cs.map(sameShare).reduce(math.max),
        );
      }(),
];

/// Whether [a] and [b] sound so much alike that they must not be options
/// of the same question (any accepted word of one against the other): at
/// least half of the sounds the same (Kuh / Schuh, luna / lupo). Words that
/// only have similar sounds (Bett / Wal) the recogniser tells apart well
/// enough, and [heardOption] asks again when it cannot.
bool soundsSimilar(PhonemeComparer comparer, String lang, Phrase a, Phrase b) {
  bool alike(String x, String y) =>
      sameShare(comparer.compare(x, y, lang)) >= 0.5;

  for (final x in a.accepted) {
    for (final y in b.accepted) {
      if (alike(x.ipa, y.ipa) || alike(y.ipa, x.ipa)) return true;
    }
  }
  return false;
}

/// 0..3 stars for [right] answers of [total].
int quizStars(int right, int total) => total == 0
    ? 0
    : right == total
    ? 3
    : right * 4 >= total * 3
    ? 2
    : right * 2 >= total
    ? 1
    : 0;
