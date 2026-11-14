import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/game/rules.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';

void main() {
  final cmp = PhonemeComparer.fromJson(
    File('assets/panphon/panphon_features.json').readAsStringSync(),
  );
  final carrot = Phrase.fromJson({
    'p': 'Karotte',
    'e': '🥕',
    'ipa': '/kaˈrɔtə/',
    'lvl': 1,
    'alt': [
      {'p': 'Möhre', 'ipa': '/ˈmøːʁə/'},
    ],
  });

  test('alternatives are parsed', () {
    expect(carrot.accepted.map((w) => w.text), ['Karotte', 'Möhre']);
    expect(carrot.alternatives.single.ipa, '/ˈmøːʁə/');
  });

  test('without alternatives only the word itself is accepted', () {
    final dog = Phrase.fromJson({
      'p': 'Hund',
      'e': '🐶',
      'ipa': '/hʊnt/',
      'lvl': 1,
    });
    expect(dog.accepted.single.text, 'Hund');
  });

  test('the main word and the alternative both get 3 stars', () {
    expect(scorePhrase(cmp, carrot, 'karɔtə', 'de-DE').stars, 3);
    final c = scorePhrase(cmp, carrot, 'møːʁə', 'de-DE');
    expect(c.stars, 3);
    expect(c.target.join(), contains('ʁ')); // aligned against Möhre
  });

  test('a different word gets no stars', () {
    expect(scorePhrase(cmp, carrot, 'hʊnt', 'de-DE').stars, 0);
  });

  test('every one of several alternatives is accepted', () {
    final granny = Phrase.fromJson({
      'p': 'grandma',
      'e': '👵',
      'ipa': '/ˈɡɹænmɑː/',
      'lvl': 1,
      'alt': [
        {'p': 'granny', 'ipa': '/ˈɡɹæni/'},
        {'p': 'nan', 'ipa': '/næn/'},
      ],
    });
    for (final said in ['ɡɹænmɑː', 'ɡɹæni', 'næn']) {
      expect(scorePhrase(cmp, granny, said, 'en-GB').stars, 3, reason: said);
    }
    expect(scorePhrase(cmp, granny, 'ʃuːz', 'en-GB').stars, lessThan(2));
  });
}
