import '../data/phrases.dart';
import '../phonetics/phoneme_distance.dart';

/// Hard cap for one recording of [text]. Normally the endpointer stops
/// earlier (child finished); the cap includes the child's reaction time
/// after the phone has said the phrase. Kids speak slowly, and a cut-off
/// tail would count as missing sounds, so long phrases get more time.
Duration recordingLimit(String text) {
  final ms = 4000 + 120 * text.runes.length;
  return Duration(milliseconds: ms.clamp(6000, 12000));
}

/// Stars to add to the session total: only the improvement over the best
/// result so far ([previousBest]), never negative.
int starsGained(int stars, int previousBest) =>
    stars > previousBest ? stars - previousBest : 0;

/// Scores [recognized] against every accepted word of [phrase] and returns
/// the best match, so a child saying "Möhre" for 🥕 is not marked wrong.
Comparison scorePhrase(
  PhonemeComparer comparer,
  Phrase phrase,
  String recognized,
  String lang,
) {
  Comparison? best;
  for (final w in phrase.accepted) {
    final c = comparer.compare(w.ipa, recognized, lang);
    if (best == null || c.score > best.score) best = c;
  }
  return best!;
}
