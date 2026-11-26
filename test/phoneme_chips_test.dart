// The chips under a word in the worlds: a dot per sound for children, the
// IPA symbols only for a grown-up who switched them on.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/game/play_screen.dart';
import 'package:phoneme_party/game/rules.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';

void main() {
  final cmp = PhonemeComparer.fromJson(
    File('assets/panphon/panphon_features.json').readAsStringSync(),
  );
  final shoe = Phrase.fromJson({
    'p': 'Schuh',
    'e': '👟',
    'ipa': '/ʃuː/',
    'lvl': 1,
  });

  Future<void> show(WidgetTester t, bool symbols) => t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PhonemeChips(
          // the vowel is wrong: one green and one red dot
          result: scorePhrase(cmp, shoe, 'ʃaː', 'de-DE'),
          symbols: symbols,
        ),
      ),
    ),
  );

  testWidgets('for children: one coloured dot per sound, no symbols', (
    t,
  ) async {
    await show(t, false);
    expect(find.byType(Text), findsNothing);
    final dots = t
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.shape == BoxShape.circle)
        .toList();
    expect(dots, hasLength(2));
    expect(dots.map((d) => d.color).toSet(), hasLength(2));
  });

  testWidgets('switched on by a grown-up: the IPA symbols', (t) async {
    await show(t, true);
    expect(find.text('ʃ'), findsOneWidget);
    expect(find.text('uː'), findsOneWidget);
  });
}
