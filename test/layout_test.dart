// The screens on a small phone (360 x 640 dp), in portrait and landscape,
// also with large text: nothing may overflow.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/listen/listen_screen.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:phoneme_party/quiz/facts.dart';
import 'package:phoneme_party/quiz/quiz_screen.dart';
import 'package:phoneme_party/read/read_aloud_screen.dart';
import 'package:phoneme_party/spell/spell_screen.dart';
import 'package:phoneme_party/think/think_screen.dart';
import 'package:phoneme_party/ui/audio_badge.dart';
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
      // every game tile shows what it does with sound
      for (final a in Audio.values) {
        expect(find.byKey(ValueKey('audio-${a.name}')), findsWidgets);
      }
      expect(find.byKey(const ValueKey('audio-none')), findsOneWidget);
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

  for (final (name, size, text) in [
    ('portrait', const Size(360, 640), 1.0),
    ('landscape', const Size(640, 360), 1.0),
    ('large text', const Size(360, 640), 1.6),
    ('landscape, large text', const Size(640, 360), 1.6),
  ]) {
    testWidgets('listen, $name', (t) async {
      await show(
        t,
        (app) => ListenScreen(app: app),
        size: size,
        text: text,
      );
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.takeException(), isNull);
      // the answer shows its word under the picture: tap until it is found
      for (var o = 0; o < 4; o++) {
        await t.tap(find.byKey(ValueKey('listen-option-$o')));
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(t.takeException(), isNull);
      }
      await close(t);
    });

    for (final game in ThinkGame.values) {
      testWidgets('${game.name}, $name', (t) async {
        await show(
          t,
          (app) => ThinkScreen(app: app, game: game),
          size: size,
          text: text,
        );
        for (var i = 0; i < 300; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(t.takeException(), isNull);
        for (var o = 0; o < (game == ThinkGame.needs ? 3 : 4); o++) {
          await t.tap(find.byKey(ValueKey('think-option-$o')));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(t.takeException(), isNull);
        }
        await close(t);
      });
    }

    testWidgets('word to picture, $name', (t) async {
      await show(
        t,
        (app) => ListenScreen(app: app, reading: true),
        size: size,
        text: text,
      );
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.takeException(), isNull);
      // tap until the answer is found (its result state)
      for (var o = 0; o < 4; o++) {
        await t.tap(find.byKey(ValueKey('listen-option-$o')));
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(t.takeException(), isNull);
      }
      await close(t);
    });
  }

  for (final (name, size, text) in [
    ('portrait', const Size(360, 640), 1.0),
    ('landscape', const Size(640, 360), 1.0),
    ('large text', const Size(360, 640), 1.6),
    ('landscape, large text', const Size(640, 360), 1.6),
  ]) {
    testWidgets('read aloud, $name', (t) async {
      await show(
        t,
        (app) => ReadAloudScreen(app: app),
        size: size,
        text: text,
      );
      // the child says nothing: the hint shows, the mic waits
      for (var i = 0; i < 300; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.takeException(), isNull);
      await close(t);
    });

    testWidgets('spell, $name', (t) async {
      await show(
        t,
        (app) => SpellScreen(app: app),
        size: size,
        text: text,
      );
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.takeException(), isNull);
      // every tile once: letters land in the slots, wrong ones shake
      for (var i = 0; i < 9; i++) {
        final tile = find.byKey(ValueKey('spell-tile-$i'));
        if (tile.evaluate().isEmpty) break;
        await t.tap(tile);
        for (var j = 0; j < 4; j++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(t.takeException(), isNull);
      }
      await close(t);
    });
  }

  for (final (name, size, text) in [
    ('portrait', const Size(360, 640), 1.0),
    ('landscape', const Size(640, 360), 1.0),
    ('large text', const Size(360, 640), 1.6),
  ]) {
    testWidgets('sound detective, $name', (t) async {
      await show(
        t,
        (app) => QuizScreen(app: app, sounds: true),
        size: size,
        text: text,
      );
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
