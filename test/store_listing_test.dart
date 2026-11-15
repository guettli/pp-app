// The Play Store listing (fastlane/metadata/android/<locale>/): every
// language has all three texts, within Google's limits.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const limits = {
    'title.txt': 30,
    'short_description.txt': 80,
    'full_description.txt': 4000,
  };
  const locales = ['en-US', 'de-DE', 'fr-FR', 'it-IT', 'es-ES'];

  for (final locale in locales) {
    for (final MapEntry(key: file, value: max) in limits.entries) {
      test('$locale/$file is at most $max characters', () {
        final f = File('fastlane/metadata/android/$locale/$file');
        final text = f.readAsStringSync().trim();
        expect(text, isNotEmpty);
        expect(text.runes.length, lessThanOrEqualTo(max));
        if (file != 'full_description.txt') {
          expect(text, isNot(contains('\n')), reason: 'one line');
        }
      });
    }
  }

  test('no other locales', () {
    final dirs =
        Directory('fastlane/metadata/android')
            .listSync()
            .whereType<Directory>()
            .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
            .toSet();
    expect(dirs, locales.toSet());
  });
}
