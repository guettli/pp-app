// Was the held sound the right one? (hold_vowel.dart)
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/phonetics/ctc_decoder.dart';
import 'package:phoneme_party/phonetics/recognizer.dart';
import 'package:phoneme_party/voice/hold_vowel.dart';
import 'package:phoneme_party/voice/voice_lines.dart';

/// Peaks ([symbol], [start] frame) in [frames] model frames.
Recognition heard(List<(String, int)> peaks, int frames) => Recognition([
  for (final (s, start) in peaks) DecodedPhoneme(s, 0.9, 1, start: start),
], frames: frames);

void main() {
  test('the sound of a phoneme, without length marks', () {
    expect(soundOf('a'), 'a');
    expect(soundOf('aː'), 'a');
    expect(soundOf('ɑ'), 'a');
    expect(soundOf('ɔ'), 'o');
    expect(soundOf('ʊ'), 'u');
    expect(soundOf('ɪ'), 'i');
    expect(soundOf('ɛ'), 'e');
    expect(soundOf('m'), 'm');
    expect(soundOf('ə'), isNull);
    expect(soundOf('b'), isNull);
    expect(soundOf('ː'), isNull);
  });

  test('a long O, heard as o: all of it counts', () {
    final c = checkVowel(heard([('o', 3)], 100), 'o')!;
    expect(c.share, 1);
    expect(c.wrong, isFalse);
  });

  test('a long A instead of the O: does not count', () {
    final c = checkVowel(heard([('aː', 2)], 100), 'o')!;
    expect(c.share, 0);
    expect(c.wrong, isTrue);
    expect(c.heard, 'a');
  });

  test('O, then A: only the O part counts', () {
    // o from the start, a from frame 70 of 100
    final c = checkVowel(heard([('o', 2), ('a', 70)], 100), 'o')!;
    expect(c.share, closeTo(0.7, 1e-9));
    expect(c.wrong, isFalse);
    expect(c.heard, 'a');
    // mostly A: wrong
    final w = checkVowel(heard([('o', 2), ('a', 30)], 100), 'o')!;
    expect(w.share, closeTo(0.3, 1e-9));
    expect(w.wrong, isTrue);
  });

  test('close vowels count for each other: O/U, E/I', () {
    expect(checkVowel(heard([('u', 1)], 50), 'o')!.share, 1);
    expect(checkVowel(heard([('ɔ', 1)], 50), 'u')!.share, 1);
    expect(checkVowel(heard([('i', 1)], 50), 'e')!.share, 1);
    expect(checkVowel(heard([('ɛ', 1)], 50), 'i')!.share, 1);
    // but not across groups
    expect(checkVowel(heard([('e', 1)], 50), 'o')!.wrong, isTrue);
    expect(checkVowel(heard([('u', 1)], 50), 'a')!.wrong, isTrue);
  });

  test('consonants and unclear sounds are not counted', () {
    final c = checkVowel(
      heard([('b', 1), ('o', 5), ('z', 20), ('ə', 30), ('m', 40)], 100),
      'o',
    )!;
    expect(c.share, 1);
  });

  test('a hum counts where a hum is wanted', () {
    expect(checkVowel(heard([('m', 1)], 50), 'm')!.share, 1);
    final c = checkVowel(heard([('a', 1)], 50), 'm')!;
    expect(c.wrong, isTrue);
    expect(c.heard, 'a');
  });

  test('nothing clear heard: no verdict, the time counts', () {
    expect(checkVowel(heard([], 50), 'o'), isNull);
    expect(checkVowel(heard([('b', 1), ('ə', 9)], 50), 'o'), isNull);
  });

  test('without the frame count: up to the last peak', () {
    final c = checkVowel(heard([('o', 0), ('a', 6)], 0), 'o')!;
    // o: 0..6, a: 6..7
    expect(c.share, closeTo(6 / 7, 1e-9));
  });

  test('every sound to hold is one the check knows, in every language', () {
    for (final lang in ['de-DE', 'en-GB', 'fr-FR', 'it-IT', 'es-ES']) {
      final lines = VoiceLines.of(lang);
      for (final s in lines.sounds) {
        expect(
          ['a', 'o', 'u', 'i', 'e', 'm'],
          contains(s.sound),
          reason: s.shown,
        );
        // the wrong-sound line names both sounds
        final other = lines.sounds.firstWhere(
          (o) => groupOf(o.sound) != groupOf(s.sound),
        );
        final line = lines.holdWrong(s, other.sound);
        expect(line, contains(other.said), reason: lang);
        expect(line, contains(s.said), reason: lang);
      }
    }
  });
}
