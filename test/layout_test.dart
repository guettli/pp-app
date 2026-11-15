// The screens on a small phone (360 x 640 dp), in portrait and landscape,
// also with large text: nothing may overflow.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:phoneme_party/quiz/facts.dart';
import 'package:phoneme_party/quiz/quiz_screen.dart';
import 'package:phoneme_party/ui/home_screen.dart';
import 'package:phoneme_party/ui/word_list_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  late PhonemeComparer comparer;
  late Facts facts;
  late PhraseBook book;
  setUpAll(() {
    comparer = PhonemeComparer.fromJson(
      File('assets/panphon/panphon_features.json').readAsStringSync(),
    );
    facts = Facts.parse(File(Facts.asset).readAsStringSync());
    final raw = File('assets/phrases/de-DE.json').readAsStringSync();
    book = PhraseBook('de-DE', [
      for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        Phrase.fromJson(j),
    ]);
  });

  Future<FakeDevices> show(
    WidgetTester t,
    Widget Function(AppState app) screen, {
    Size size = const Size(360, 640),
    double text = 1,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final progress = await Progress.load();
    final t0 = t.binding.clock.now();
    final dev = FakeDevices(
      IoLog(() => t.binding.clock.now().difference(t0)),
      child: () => Child.silent,
    );
    final app = AppState(
      FakeRecognizer(() => ''),
      comparer,
      progress,
      book,
      io: dev.io,
      facts: facts,
    );
    await t.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(text)),
        child: MaterialApp(home: screen(app)),
      ),
    );
    await t.pump(const Duration(milliseconds: 100));
    return dev;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  for (final (name, size) in [
    ('portrait', const Size(360, 640)),
    ('landscape', const Size(640, 360)),
  ]) {
    testWidgets('home, $name', (t) async {
      await show(t, (app) => HomeScreen(app: app), size: size);
      expect(t.takeException(), isNull);
      await close(t);
    });

    testWidgets('word list, $name', (t) async {
      await show(t, (app) => WordListScreen(app: app), size: size);
      expect(t.takeException(), isNull);
      await close(t);
    });

    testWidgets('quiz, $name', (t) async {
      await show(t, (app) => QuizScreen(app: app), size: size);
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.takeException(), isNull);
      await close(t);
    });
  }

  testWidgets('quiz, large text', (t) async {
    await show(t, (app) => QuizScreen(app: app), text: 1.6);
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(t.takeException(), isNull);
    await close(t);
  });
}
