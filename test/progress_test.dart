import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/game/rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Progress progress;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    progress = await Progress.load();
  });

  PhraseBook book(int n) => PhraseBook(
    'de-DE',
    List.generate(
      n,
      (i) => Phrase(text: 'p$i', emoji: '⭐', ipa: 'a', level: i),
    ),
  );

  test('record keeps the best and returns the previous best', () async {
    expect(await progress.record('de-DE', 'Hund', 2), 0);
    expect(progress.stars('de-DE', 'Hund'), 2);
    expect(await progress.record('de-DE', 'Hund', 1), 2);
    expect(progress.stars('de-DE', 'Hund'), 2, reason: 'worse does not count');
    expect(await progress.record('de-DE', 'Hund', 3), 2);
    expect(progress.stars('de-DE', 'Hund'), 3);
  });

  test('stars are per language', () async {
    await progress.record('de-DE', 'Taxi', 3);
    expect(progress.stars('es-ES', 'Taxi'), 0);
  });

  test('stars survive a restart', () async {
    await progress.record('fr-FR', 'Bonjour', 2);
    expect((await Progress.load()).stars('fr-FR', 'Bonjour'), 2);
  });

  test('worlds: 8 phrases each, the last one may be shorter', () {
    final b = book(18);
    expect(b.worldCount, 3);
    expect(b.world(0).map((p) => p.text), [for (var i = 0; i < 8; i++) 'p$i']);
    expect(b.world(2).length, 2);
  });

  test('a world opens at one star per phrase on average', () async {
    final b = book(16);
    expect(progress.worldOpen(b, 0), isTrue);
    expect(progress.worldOpen(b, 1), isFalse);
    // 7 stars in world 0: not yet
    await progress.record('de-DE', 'p0', 3);
    await progress.record('de-DE', 'p1', 3);
    await progress.record('de-DE', 'p2', 1);
    expect(progress.worldStars(b, 0), 7);
    expect(progress.worldOpen(b, 1), isFalse);
    await progress.record('de-DE', 'p7', 1);
    expect(progress.worldOpen(b, 1), isTrue);
    // stars in a later world do not count for the earlier one
    expect(progress.worldStars(b, 1), 0);
  });

  test('session stars count only the improvement', () {
    expect(starsGained(3, 0), 3);
    expect(starsGained(3, 2), 1);
    expect(starsGained(1, 2), 0);
    expect(starsGained(0, 0), 0);
  });
}
