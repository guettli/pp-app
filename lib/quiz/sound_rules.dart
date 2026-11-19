// The sound detective (🔔): "What starts like Maus?" – three pictures, one
// starts the same way (Mond), the child says it. Hearing how a word starts
// is where reading and writing start.
//
// "The same way" is the whole consonant group before the first vowel (the
// onset): Stuhl /ʃt/ starts like Stern, not like Spinne /ʃp/ or Schuh /ʃ/,
// although all begin with /ʃ/. Words starting with a vowel are left out:
// vowels differ by small shades (e / ɛ) a child cannot be asked to hear.
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
/// t and tʰ are the same sound for a child.
String _bare(String sound) => String.fromCharCodes(
  sound.runes.where(
    (c) =>
        !(c >= 0x0300 && c <= 0x036F) && // combining marks
        !(c >= 0x02B0 && c <= 0x02FF), // ʰ ʲ ʷ ː ˑ and other modifiers
  ),
);

bool _isVowel(String sound) =>
    sound.isNotEmpty &&
    _vowels.contains(String.fromCharCode(sound.runes.first));

/// The consonants of [ipa] before its first vowel, an affricate as one
/// sound (Stuhl: [ʃ, t], Zwerg: [ts, v], Maus: [m]); null if it starts
/// with a vowel.
List<String>? onsetSounds(PhonemeComparer comparer, String ipa, String lang) {
  final s = ipa.replaceAll(RegExp('[/\\[\\]ˈˌ.‍‿͡]'), '').trim();
  final (phonemes, words) = comparer.tokenize(s, lang);
  final sounds = [
    for (var i = 0; i < phonemes.length && words[i] == 0; i++)
      _bare(phonemes[i]),
  ]..removeWhere((x) => x.isEmpty);
  final out = <String>[];
  for (var i = 0; i < sounds.length; i++) {
    if (_isVowel(sounds[i])) break;
    if (i + 1 < sounds.length &&
        _affricates.contains(sounds[i] + sounds[i + 1])) {
      out.add(sounds[i] + sounds[i + 1]);
      i++;
    } else {
      out.add(sounds[i]);
    }
  }
  return out.isEmpty ? null : out;
}

/// The onset of [ipa] as one string ("ʃt", "m"), null for a vowel start.
String? onsetOf(PhonemeComparer comparer, String ipa, String lang) =>
    onsetSounds(comparer, ipa, lang)?.join();

/// The onset of [p] (the word the app says).
String? firstSound(PhonemeComparer comparer, Phrase p, String lang) =>
    onsetOf(comparer, p.ipa, lang);

/// First sounds this far apart (PanPhon cost 0..1) are clearly different
/// for the ear; closer ones (b / p, m / n, f / θ, l / r) are never offered
/// against each other.
const minOnsetCost = 0.2;

/// The single sounds of a sound: an affricate is two (t + s).
List<String> _parts(String sound) => _affricates.contains(sound)
    ? [sound.substring(0, 1), sound.substring(1)]
    : [sound];

/// Whether a word with the onset [sounds] (null: a vowel start) clearly
/// does not start like one with [onset]: their first sounds are far apart,
/// every part of one from every part of the other (so ts is not offered
/// against t or s, Schuh /ʃ/ not against Stuhl /ʃt/).
bool clearlyOther(
  PhonemeComparer comparer,
  List<String>? sounds,
  List<String> onset,
  String lang,
) {
  if (sounds == null) return true;
  for (final x in _parts(sounds.first)) {
    for (final y in _parts(onset.first)) {
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
bool _noneStartsLike(
  PhonemeComparer c,
  Phrase p,
  List<String> onset,
  String lang,
) => p.accepted.every(
  (w) => clearlyOther(c, onsetSounds(c, w.ipa, lang), onset, lang),
);

/// One "starts like" question from [pool], or null: a [like] word, the
/// answer with the same onset, two wrong ones whose first sound is clearly
/// different. Never the same picture twice, never [similar] options
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
  final sounds = onsetSounds(comparer, like.ipa, lang);
  if (sounds == null) return null;
  final onset = sounds.join();
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
      if (_noneStartsLike(comparer, p, sounds, lang)) p,
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
