// Sanity checks over all shipped phrase data. These catch data problems that
// would make a perfectly spoken phrase lose stars.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:phoneme_party/ui/emoji_image.dart';

void main() {
  final cmp = PhonemeComparer.fromJson(
    File('assets/panphon/panphon_features.json').readAsStringSync(),
  );

  for (final lang in languageNames.keys) {
    group(lang, () {
      final phrases =
          (jsonDecode(File('assets/phrases/$lang.json').readAsStringSync())
                  as List)
              .cast<Map<String, dynamic>>()
              .map(Phrase.fromJson)
              .toList();

      test('has phrases sorted by level', () {
        expect(phrases, isNotEmpty);
        for (var i = 1; i < phrases.length; i++) {
          expect(phrases[i].level, greaterThanOrEqualTo(phrases[i - 1].level));
        }
      });

      test('one word per picture, no duplicates', () {
        expect(phrases.map((p) => p.emoji).toSet().length, phrases.length);
        final words = [
          for (final p in phrases) ...p.accepted.map((w) => w.text),
        ];
        expect(words.toSet().length, words.length);
      });

      test('no optional sounds or notes in the IPA', () {
        // "(ə)" etc. cannot be scored: the child would lose points either way
        for (final w in phrases.expand((p) => p.accepted)) {
          expect(w.ipa, isNot(matches(RegExp(r'[()ᵑ]'))), reason: w.text);
        }
      });

      test('every phoneme has PanPhon features', () {
        final unknown = <String, String>{};
        for (final w in phrases.expand((p) => p.accepted)) {
          for (final ph in cmp.tokenize(w.ipa, lang).$1) {
            if (!cmp.isKnown(ph)) unknown.putIfAbsent(ph, () => w.text);
          }
        }
        expect(unknown, isEmpty);
      });

      test('perfect recognition gives 3 stars', () {
        // The recogniser outputs plain phones: no stress, no spaces.
        final failed = <String>[];
        for (final p in phrases) {
          for (final w in p.accepted) {
            final ideal = PhonemeComparer.normalize(
              w.ipa,
              lang,
            ).replaceAll(' ', '');
            // each word on its own, so a broken alternative cannot hide
            // behind a better matching one
            final c = cmp.compare(w.ipa, ideal, lang);
            if (c.stars != 3) failed.add('${w.text} (${c.score})');
          }
        }
        expect(failed, isEmpty);
      });

      test('every picture is bundled', () {
        final missing = phrases
            .map((p) => p.emoji)
            .where((e) => !File('assets/emoji/${emojiKey(e)}.webp').existsSync())
            .toSet();
        expect(missing, isEmpty);
      });
    });
  }
}
