import 'dart:math' as math;

import '../data/phrases.dart';
import '../game/rules.dart';
import '../phonetics/phoneme_distance.dart';

/// The best option must score at least this ...
const minAnswerScore = 0.4;

/// ... and this much more than the second best, or the child is asked once
/// more instead of being marked wrong for a word the phone misheard.
const minAnswerMargin = 0.15;

/// Which of [options] the child said ([ipa] from the recogniser), or null
/// when that is not clear.
Phrase? heardOption(
  PhonemeComparer comparer,
  List<Phrase> options,
  String ipa,
  String lang,
) {
  if (ipa.isEmpty) return null;
  final scored = [
    for (final o in options) (o, scorePhrase(comparer, o, ipa, lang).score),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  final (best, score) = scored.first;
  if (score < minAnswerScore) return null;
  if (scored.length > 1 && score - scored[1].$2 < minAnswerMargin) {
    return null;
  }
  return best;
}

/// Whether [a] and [b] sound so much alike that they must not be options
/// of the same question (any accepted word of one against the other): at
/// least half of the sounds the same (Kuh / Schuh, luna / lupo). Words that
/// only have similar sounds (Bett / Wal) the recogniser tells apart well
/// enough, and [heardOption] asks again when it cannot.
bool soundsSimilar(PhonemeComparer comparer, String lang, Phrase a, Phrase b) {
  bool alike(String x, String y) {
    final c = comparer.compare(x, y, lang);
    final same = c.alignment.where((p) => p.target == p.actual).length;
    final longer = math.max(c.target.length, c.actual.length);
    return longer == 0 || same * 2 >= longer;
  }

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
