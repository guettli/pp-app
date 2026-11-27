// Every picture the screens use has its Fluent image: without one, a
// phone shows its own font's emoji instead, in another style (or an
// empty box on old phones). 🙂 in "Low and high" was missing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/ui/emoji_image.dart';

/// Emoji strings in lib/ that are not shown as a picture.
const notPictures = {
  // the language flags: Fluent has none (🇮🇹 is a word's picture); the
  // phone's own flags are fine
  '🇩🇪', '🇬🇧', '🇫🇷', '🇪🇸',
  // Rommé: card suits, drawn as text
  '♣', '♥', '♠', '♦', '★',
};

bool _emoji(int r) =>
    r >= 0x1F000 || (r >= 0x2600 && r <= 0x27BF) || r == 0x2B50 || r == 0x2B55;

void main() {
  test('every emoji in lib/ has its picture in assets/emoji', () {
    final have = {
      for (final f in Directory('assets/emoji').listSync())
        f.uri.pathSegments.last.replaceAll('.webp', ''),
    };
    // memory_rules.dart: families of look-alikes, also ones not in the
    // word list (never shown)
    final lookAlikes = RegExp(r"const lookAlike = \[[^;]*\];");
    final literal = RegExp(r"'([^'\\\n]{1,16})'");
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync().replaceAll(lookAlikes, '');
      for (final m in literal.allMatches(src)) {
        final s = m[1]!;
        final core = s.runes.where((r) => r != 0xFE0F && r != 0x200D);
        if (core.isEmpty || !core.every(_emoji)) continue;
        if (notPictures.contains(s) || have.contains(emojiKey(s))) continue;
        missing.add('$s (${f.path})');
      }
    }
    expect(missing, isEmpty);
  });
}
