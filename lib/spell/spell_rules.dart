// "Letter puzzle": the child spells a word it sees and hears by tapping
// letter tiles in order.
import 'dart:math' as math;

import 'package:flutter/widgets.dart' show StringCharacters;

import '../data/phrases.dart';

/// The letters of [word] as the child sees them: grapheme clusters, so
/// "ä", "é" or "ñ" stay one tile even when stored as letter + accent.
List<String> lettersOf(String word) => word.characters.toList();

/// Only letters (any script, with accents); no spaces, hyphens or
/// apostrophes, which would be odd tiles.
final _lettersOnly = RegExp(r'^[\p{L}\p{M}]+$', unicode: true);

/// Whether [p] can be spelled in the puzzle: one word of [minLetters] to
/// [maxLetters] letters (the first accepted word, the one the app says).
bool spellable(Phrase p, {int minLetters = 2, int maxLetters = 7}) {
  if (!_lettersOnly.hasMatch(p.text)) return false;
  final n = lettersOf(p.text).length;
  return n >= minLetters && n <= maxLetters;
}

/// One puzzle: the word, its letters in order and the shuffled tiles (its
/// letters plus a few extra ones that are not in the word).
class SpellPuzzle {
  const SpellPuzzle(this.phrase, this.letters, this.tiles);

  final Phrase phrase;
  final List<String> letters;
  final List<String> tiles;

  @override
  String toString() => '${phrase.text}: ${tiles.join(' ')}';
}

/// Two letters are the same tile for the child: "H" and "h" (the first
/// letter of a German noun is a capital; the tile shows it as written).
bool sameLetter(String a, String b) => a.toLowerCase() == b.toLowerCase();

/// The letter without its accent: "é" -> "e", "ñ" -> "n", "ä" -> "a"
/// (lowercase). Letters of their own like "ß" or "œ" stay as they are.
String baseLetter(String l) {
  final lower = l.toLowerCase();
  return _bases[lower] ?? lower;
}

const _accents = {
  'a': 'àáâäãåā',
  'c': 'ç',
  'e': 'èéêëē',
  'i': 'ìíîïī',
  'n': 'ñ',
  'o': 'òóôöõō',
  'u': 'ùúûüū',
  'y': 'ÿý',
};
final _bases = {
  for (final e in _accents.entries)
    for (final r in e.value.runes) String.fromCharCode(r): e.key,
};

/// Too alike to be an extra tile next to each other: the same letter, or
/// the same letter with another accent (o / ó, a / ä): small on a cheap
/// screen, and said the same.
bool looksAlike(String a, String b) => baseLetter(a) == baseLetter(b);

/// [count] puzzles from the spellable words of [pool], short words first.
/// Extra tiles: none for the first two words, then one, from the third
/// on two; taken from [alphabet] (lowercase letters of the language),
/// never a letter of the word or one that [looksAlike] it.
List<SpellPuzzle> makeSpellRound(
  List<Phrase> pool,
  List<String> alphabet,
  math.Random rng, {
  int count = 6,
}) {
  final words = [
    for (final p in pool)
      if (spellable(p)) p,
  ]..shuffle(rng);
  final picked = words.take(count).toList()
    ..sort(
      (a, b) => lettersOf(a.text).length.compareTo(lettersOf(b.text).length),
    );
  return [
    for (final (i, p) in picked.indexed)
      () {
        final letters = lettersOf(p.text);
        final extra = i < 2 ? 0 : (i < 4 ? 1 : 2);
        final others = [
          for (final a in alphabet)
            if (!letters.any((l) => looksAlike(l, a))) a,
        ]..shuffle(rng);
        final tiles = [...letters, ...others.take(extra)]..shuffle(rng);
        return SpellPuzzle(p, letters, tiles);
      }(),
  ];
}

/// The lowercase letters used in [phrases] (the alphabet of a language,
/// with its accents), sorted.
List<String> alphabetOf(Iterable<Phrase> phrases) {
  final set = <String>{};
  for (final p in phrases) {
    if (!_lettersOnly.hasMatch(p.text)) continue;
    for (final l in lettersOf(p.text)) {
      set.add(l.toLowerCase());
    }
  }
  return set.toList()..sort();
}
