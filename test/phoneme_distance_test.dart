import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';

void main() {
  final cmp = PhonemeComparer.fromJson(
    File('assets/panphon/panphon_features.json').readAsStringSync(),
  );
  double sim(String t, String a, [String lang = 'de-DE']) =>
      cmp.compare(t, a, lang).similarity;

  // --- adopted from guettli/pp tests/similarity.test.js -------------------

  test('identical strings are 100% similar', () {
    expect(sim('moːnt', 'moːnt'), 1.0);
  });

  test('"mund" is closer to "Mond" than "muda"', () {
    expect(sim('moːnt', 'mʊnt'), greaterThan(sim('moːnt', 'muːda')));
  });

  test('single vowel change keeps high similarity', () {
    expect(sim('moːnt', 'muːnt'), greaterThanOrEqualTo(0.7));
  });

  group('German equivalences', () {
    for (final (t, a) in [
      ('hamɐ', 'hamər'), // vocalised r
      ('bətə', 'bɛtɛ'), // schwa variants
      ('ʁot', 'rot'), // uvular vs alveolar r
      ('zun', 'sun'), // regional s voicing (deliberately lenient)
      ('dɐ̯', 'dr'),
      ('hamɐ', 'hamɛʁ'),
      ('deːɐ̯ hamstɐ', 'deːr hamstər'),
    ]) {
      test('$t ≈ $a', () => expect(sim(t, a), 1.0));
    }
  });

  // pp also tested its plain Levenshtein metric; the app does not use one.

  // --- new: regressions for issues found while porting --------------------

  test('German rules do not leak into other languages', () {
    expect(sim('ʁot', 'rot', 'en-GB'), lessThan(1.0));
    expect(sim('zuː', 'suː', 'fr-FR'), lessThan(1.0));
  });

  test('zero-width joiner in en-GB IPA is ignored', () {
    // phrases-en-GB.yaml writes affricates as "t‍ʃ" (with U+200D)
    expect(sim('/ði ˈɑːt‍ʃəɹi./', 'ðiɑːtʃəɹi', 'en-GB'), 1.0);
  });

  test('g is a known phoneme and close to k', () {
    // ASCII g (model output) and IPA ɡ (phrase files) are the same sound
    expect(sim('ɡaʊ', 'gaʊ'), 1.0);
    expect(cmp.phonemeCost('ɡ', 'k', 'de-DE'), lessThan(0.15));
  });

  test('combining diacritics stay with their phoneme', () {
    final (p, _) = cmp.tokenize('/pɛ̃/', 'fr-FR');
    expect(p, ['p', 'ɛ̃']);
    expect(sim('/pɛ̃/', 'pɛ', 'fr-FR'), greaterThan(0.8));
  });

  test('length mark is part of the vowel', () {
    final (p, _) = cmp.tokenize('muːt', 'de-DE');
    expect(p, ['m', 'uː', 't']);
  });

  test('word index survives insertions', () {
    // extra phoneme at the start must not shift the word of later phonemes
    final r = cmp.compare('diː maʊ̯s', 'adiːmaʊs', 'de-DE');
    final m = r.alignment.firstWhere((a) => a.target == 'm');
    expect(m.word, 1);
    expect(r.alignment.first.target, isNull);
  });

  test('empty input', () {
    expect(sim('', ''), 1.0);
    expect(sim('haʊs', ''), 0.0); // pp gave 0.5 for silence
  });

  test('stars thresholds', () {
    expect(cmp.compare('moːnt', 'moːnt', 'de-DE').stars, 3);
    expect(cmp.compare('moːnt', 'xyz', 'de-DE').stars, 0);
    expect(cmp.compare('haʊs', '', 'de-DE').stars, 0);
  });

  test('a different phrase gets at most one star', () {
    // pp's feature similarity gives ~0.8 here, i.e. 2-3 stars
    expect(
      cmp.compare('diː kuː muːt', 'deːɐ̯hʊnt', 'de-DE').stars,
      lessThan(2),
    );
    expect(cmp.compare('deːɐ̯ fʊks', 'diːʁoːzə', 'de-DE').stars, 0);
  });

  // --- real recognitions from pp's test recordings ------------------------

  group('pp recordings', () {
    final rows =
        (jsonDecode(File('test/fixtures/pp_recordings.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>();
    // "Der Bus" was recognised as "ðeɪhɑɹpoʊz" (clearly wrong); pp scored it
    // 0.78. "Der Junge" -> "deaɪtɕuŋə" is half right and not asserted.
    for (final r in rows) {
      final c = cmp.compare(
        r['target'] as String,
        r['recognized'] as String,
        r['lang'] as String,
      );
      final name = '${r['phrase']}: score ${c.score.toStringAsFixed(2)}';
      switch (r['phrase']) {
        case 'Der Bus':
          test('$name (misrecognised) gets at most 1 star', () {
            expect(c.stars, lessThanOrEqualTo(1));
          });
        case 'Der Junge':
          break;
        default:
          test('$name (correct) gets at least 2 stars', () {
            expect(c.score, greaterThanOrEqualTo(0.75));
          });
      }
    }
  });
}
