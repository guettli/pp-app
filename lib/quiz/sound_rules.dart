// The sound detective (🔔): "What starts like Maus?" – three pictures, one
// starts with the same sound (Mond), the child says it. Hearing the first
// sound of a word is where reading and writing start.
//
// Only consonants count as first sounds: vowels differ by small shades
// (e / ɛ) a child cannot be asked to hear.
import 'dart:math' as math;

import '../data/phrases.dart';
import '../phonetics/phoneme_distance.dart';
import 'facts.dart';

const _vowels = 'aeiouyæøœɑɒɔəɛɜɪʊʏɐʌɤɯɨʉ';

/// Affricates are one sound (Zahn /ts/, Pferd /pf/, chair /tʃ/, giraffe
/// /dʒ/, zucca /dz/), written with or without a tie bar or zero-width
/// joiner. At the start of a word these letter pairs are always one.
const _affricates = ['ts', 'pf', 'tʃ', 'dʒ', 'dz'];

/// Without length marks, aspiration, palatalisation and other marks:
/// t and tʰ are the same first sound for a child.
String _bare(String sound) => String.fromCharCodes(
  sound.runes.where(
    (c) =>
        !(c >= 0x0300 && c <= 0x036F) && // combining marks
        !(c >= 0x02B0 && c <= 0x02FF), // ʰ ʲ ʷ ː ˑ and other modifiers
  ),
);

/// The first sound of [ipa]: an affricate, else the first phoneme without
/// marks; null if it starts with a vowel.
String? onsetOf(PhonemeComparer comparer, String ipa, String lang) {
  final s = ipa.replaceAll(RegExp('[/\\[\\]ˈˌ.‍‿͡]'), '').trim();
  for (final a in _affricates) {
    if (s.startsWith(a)) return a;
  }
  final (phonemes, _) = comparer.tokenize(s, lang);
  if (phonemes.isEmpty) return null;
  final first = _bare(phonemes.first);
  if (first.isEmpty) return null;
  if (_vowels.contains(String.fromCharCode(first.runes.first))) return null;
  return first;
}

/// The first sound of [p] (the word the app says).
String? firstSound(PhonemeComparer comparer, Phrase p, String lang) =>
    onsetOf(comparer, p.ipa, lang);

/// First sounds this far apart (PanPhon cost 0..1) are clearly different
/// for the ear; closer ones (b / p, m / n, f / θ, l / r) are never offered
/// against each other.
const minOnsetCost = 0.2;

/// The single sounds of an onset: an affricate is two (t + s).
List<String> _parts(String onset) => _affricates.contains(onset)
    ? [onset.substring(0, 1), onset.substring(1)]
    : [onset];

/// Whether a word starting with [sound] (null: a vowel) is clearly not one
/// starting with [onset]: every part of one is far from every part of the
/// other (so ts is not offered against t or s).
bool clearlyOther(
  PhonemeComparer comparer,
  String? sound,
  String onset,
  String lang,
) {
  if (sound == null) return true;
  for (final x in _parts(sound)) {
    for (final y in _parts(onset)) {
      if (comparer.phonemeCost(x, y, lang) < minOnsetCost) return false;
    }
  }
  return true;
}

/// Every name the child may say for [p] starts with [onset] (Möhre must
/// start like Karotte, or the picture is no clear answer).
bool _allStartWith(PhonemeComparer c, Phrase p, String onset, String lang) =>
    p.accepted.every((w) => onsetOf(c, w.ipa, lang) == onset);

/// No name the child may say for [p] starts like [onset].
bool _noneStartsLike(PhonemeComparer c, Phrase p, String onset, String lang) =>
    p.accepted.every(
      (w) => clearlyOther(c, onsetOf(c, w.ipa, lang), onset, lang),
    );

/// One "starts like" question from [pool], or null: a [like] word, the
/// answer with the same first sound, two wrong ones that start clearly
/// differently. Never the same picture twice, never [similar] options
/// (the recogniser must tell them apart), never the [like] word itself.
QuizQuestion? makeSoundQuestion(
  Phrase like,
  List<Phrase> pool,
  PhonemeComparer comparer,
  String lang,
  math.Random rng, {
  Similar? similar,
  Set<String> avoidAnswers = const {},
}) {
  final onset = firstSound(comparer, like, lang);
  if (onset == null) return null;
  bool apart(List<Phrase> chosen, Phrase p) => chosen.every(
    (c) => c.emoji != p.emoji && !(similar?.call(c, p) ?? false),
  );
  final others = [
    for (final p in pool)
      if (p.emoji != like.emoji && p.text != like.text) p,
  ]..shuffle(rng);
  final rights = [
    for (final p in others)
      if (_allStartWith(comparer, p, onset, lang) &&
          !avoidAnswers.contains(p.text) &&
          !(similar?.call(p, like) ?? false))
        p,
  ];
  final wrongs = [
    for (final p in others)
      if (_noneStartsLike(comparer, p, onset, lang)) p,
  ];
  for (final answer in rights) {
    final chosen = [answer];
    for (final w in wrongs) {
      if (chosen.length == 3) break;
      if (apart(chosen, w)) chosen.add(w);
    }
    if (chosen.length == 3) {
      return QuizQuestion(Ask.startsLike(like), chosen..shuffle(rng), answer);
    }
  }
  return null;
}

/// Up to [count] questions; every [like] word and every answer at most
/// once.
List<QuizQuestion> makeSoundRound(
  List<Phrase> pool,
  PhonemeComparer comparer,
  String lang,
  math.Random rng, {
  int count = 8,
  Similar? similar,
}) {
  final out = <QuizQuestion>[];
  final used = <String>{};
  for (final like in [...pool]..shuffle(rng)) {
    if (out.length == count) break;
    if (used.contains(like.text)) continue;
    final q = makeSoundQuestion(
      like,
      pool,
      comparer,
      lang,
      rng,
      similar: similar,
      avoidAnswers: used,
    );
    if (q == null) continue;
    out.add(q);
    used
      ..add(like.text)
      ..add(q.answer.text);
  }
  return out;
}
