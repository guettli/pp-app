// Was it the right sound? "Hold it long" asks for an O; a long A must not
// count. The phone recognizer (ZIPA, like in the worlds) runs once over
// the held sound. It gives one short peak per sound it hears, at the time
// the sound starts: a held "Ooo" is one "o", "Ooo-aaa" is "o" then "a".
// So a sound lasts from its peak to the next one, and only the time of
// the right sound counts.
//
// Close vowels are not told apart: a child's O is often heard as u, an
// E as i.
// What counts is the group: A, O/U, E/I (and M for the English hum).
// (ZIPA on synthetic children's vowels told A from O/U and from E/I, but
// often heard o as u and e as i.)
// Consonants and unclear vowels (ə, y, ø) are not counted for vowels.
import '../phonetics/recognizer.dart';

/// The sound of a recognized phoneme ("a", "o", "u", "i", "e", "m"), or
/// null for anything else. Length marks and diacritics do not matter.
String? soundOf(String symbol) {
  final base = String.fromCharCodes(
    symbol.runes.where(
      (r) => r != 0x2D0 && r != 0x2D1 && (r < 0x300 || r > 0x36F),
    ),
  );
  for (final MapEntry(:key, :value) in _sounds.entries) {
    if (value.contains(base)) return key;
  }
  return null;
}

const _sounds = {
  'a': {'a', 'ɑ', 'ɐ', 'æ', 'ä', 'ʌ', 'ɶ'},
  'o': {'o', 'ɔ', 'ɒ', 'ɵ'},
  'u': {'u', 'ʊ', 'ɯ'},
  'i': {'i', 'ɪ', 'ɨ'},
  'e': {'e', 'ɛ'},
  'm': {'m', 'n', 'ŋ', 'ɱ'},
};

/// The group of a sound: the sounds that count for each other.
String groupOf(String sound) => switch (sound) {
  'o' || 'u' => 'ou',
  'i' || 'e' => 'ei',
  _ => sound,
};

/// How much of a held sound was the right one.
class VowelCheck {
  const VowelCheck(this.share, this.heard);

  /// Part of the time (0..1) the sound of the wanted group was heard.
  final double share;

  /// The wrong sound heard longest ("a"), or null if none.
  final String? heard;

  /// Mostly another sound: the try does not count.
  bool get wrong => share < 0.5;
}

/// Checks [r], the recognition of a held sound, against [want] ("o"). Null
/// if no sound was recognized at all: then the time counts as it is (a
/// child must not lose stars because the recognizer heard nothing).
VowelCheck? checkVowel(Recognition r, String want) {
  final group = groupOf(want);
  final peaks = <(int, String)>[
    for (final p in r.phonemes)
      if (soundOf(p.symbol) case final s?)
        // a hum counts only where a hum is wanted
        if (s != 'm' || group == 'm') (p.start, s),
  ];
  if (peaks.isEmpty) return null;
  final last = r.phonemes.last;
  final end = r.frames > 0 ? r.frames : last.start + last.frames;
  final time = <String, int>{};
  for (final (i, (start, s)) in peaks.indexed) {
    // the first sound also covers the time before its peak
    final from = i == 0 ? 0 : start;
    final to = i + 1 < peaks.length ? peaks[i + 1].$1 : end;
    time[s] = (time[s] ?? 0) + (to - from);
  }
  final total = time.values.fold(0, (a, b) => a + b);
  if (total <= 0) return null;
  var right = 0;
  String? heard;
  var heardTime = 0;
  for (final MapEntry(:key, :value) in time.entries) {
    if (groupOf(key) == group) {
      right += value;
    } else if (value > heardTime) {
      heard = key;
      heardTime = value;
    }
  }
  return VowelCheck(right / total, heard);
}
