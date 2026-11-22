// The screens on a small phone (360 x 640 dp), in portrait and landscape,
// also with large text: nothing may overflow.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/net/feedback.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/game/play_screen.dart';
import 'package:phoneme_party/listen/listen_screen.dart';
import 'package:phoneme_party/memory/memory_rules.dart';
import 'package:phoneme_party/memory/memory_screen.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:phoneme_party/quiz/facts.dart';
import 'package:phoneme_party/quiz/quiz_screen.dart';
import 'package:phoneme_party/read/read_aloud_screen.dart';
import 'package:phoneme_party/spell/spell_screen.dart';
import 'package:phoneme_party/think/think_screen.dart';
import 'package:phoneme_party/ui/emoji_image.dart';
import 'package:phoneme_party/ui/home_screen.dart';
import 'package:phoneme_party/ui/round_parts.dart';
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
    Map<String, Object> prefs = const {},
    bool feedback = false,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
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
      feedback: feedback
          ? FeedbackOutbox(await SharedPreferences.getInstance(), _NoSend())
          : null,
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

  for (final (name, size, text) in [
    ('portrait', const Size(360, 640), 1.0),
    ('landscape', const Size(640, 360), 1.0),
    ('large text', const Size(360, 640), 1.6),
    ('landscape, large text', const Size(640, 360), 1.6),
  ]) {
    testWidgets('round end: the hare jumps, then all is still, $name', (
      t,
    ) async {
      await show(
        t,
        (app) => Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showRoundEnd(
                  context,
                  stars: 3,
                  right: 8,
                  total: 8,
                  record: true,
                ),
                child: const Text('end'),
              ),
            ),
          ),
        ),
        size: size,
        text: text,
      );
      await t.tap(find.text('end'));
      // mid-jump too: nothing may overflow
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull);
      }
      expect(find.byKey(const ValueKey('cheer-hare')), findsOneWidget);
      // the OK button is in view
      expect(find.text('Great').hitTestable(), findsOneWidget);
      // with a ✓ a child understands without reading
      expect(find.byIcon(Icons.check_rounded).hitTestable(), findsOneWidget);
      // once, not forever: pumpAndSettle ends
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('8 / 8'), findsOneWidget);
      await close(t);
    });
  }

  for (final switchLanguage in [false, true]) {
    testWidgets('a world that just opened sparkles until it is tapped '
        '${switchLanguage ? '(or the language changes)' : ''}', (t) async {
      late AppState app;
      await show(t, (a) {
        app = a;
        return HomeScreen(app: a);
      });
      expect(find.byKey(const ValueKey('world-new-1')), findsNothing);
      await t.tap(find.text('0/24'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      // the child plays world 1 well: world 2 opens
      for (final p in app.book.world(0)) {
        await app.progress.record(app.book.lang, p.text, 3);
      }
      Navigator.of(t.element(find.byType(PlayScreen))).pop();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('world-new-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('world-new-0')), findsNothing);
      expect(t.takeException(), isNull);
      if (switchLanguage) {
        // new in German, not in English: no ✨ there
        await t.tap(find.byTooltip('Which language do you practise?'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'the language sheet fits');
        await t.tap(find.text('English'));
        await t.pumpAndSettle();
        expect(app.book.lang, 'en-GB');
      } else {
        // tapped: seen, no ✨ any more
        await t.tap(find.text('0/24'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        Navigator.of(t.element(find.byType(PlayScreen))).pop();
        await t.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('world-new-1')), findsNothing);
      await close(t);
    });
  }

  testWidgets('the tiles show the stars of the best rounds', (t) async {
    await show(
      t,
      (app) => HomeScreen(app: app),
      prefs: {'needs|de-DE': 2, 'listen|de-DE': 3},
    );
    // thinking: five games with stars, 2 of 15
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('group-think')),
        matching: find.text('2/15'),
      ),
      findsOneWidget,
    );
    // speaking: the voice games have no stars
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('group-speak')),
        matching: find.textContaining('/'),
      ),
      findsNothing,
    );
    await t.tap(find.byKey(const ValueKey('group-think')));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('game-think-0')),
        matching: find.byKey(const ValueKey('stars-2')),
      ),
      findsOneWidget,
    );
    await close(t);
  });

  for (final (name, size) in [
    ('portrait', const Size(360, 640)),
    ('landscape', const Size(640, 360)),
  ]) {
    testWidgets('home, $name', (t) async {
      await show(t, (app) => HomeScreen(app: app), size: size);
      expect(t.takeException(), isNull);
      for (final g in ['hear', 'read', 'speak', 'think', 'memory', 'feel']) {
        expect(find.byKey(ValueKey('group-$g')), findsOneWidget);
      }
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

  testWidgets('quiz with large text on a small phone: pictures stay big', (
    t,
  ) async {
    await show(t, (app) => QuizScreen(app: app), text: 1.6);
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(t.takeException(), isNull);
    final pics = find.byWidgetPredicate((w) => w is EmojiImage && w.size > 1);
    // the question picture aside: the three answers, each still a picture
    // a child can see (it once shrank to a few dp)
    // on screen (after any FittedBox scaling)
    final sizes = [
      for (final e in pics.evaluate())
        () {
          final box = e.renderObject! as RenderBox;
          final a = box.localToGlobal(Offset.zero);
          final b = box.localToGlobal(box.size.bottomRight(Offset.zero));
          return b.dx - a.dx;
        }(),
    ];
    sizes.sort();
    expect(
      sizes.reversed.take(3).every((w) => w > 60),
      isTrue,
      reason: '$sizes',
    );
    await close(t);
  });

  testWidgets('quiz on a tall phone: two pictures and one below, big', (
    t,
  ) async {
    await show(
      t,
      (app) => QuizScreen(app: app),
      size: const Size(393, 829), // about the A80
    );
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(t.takeException(), isNull);
    expect(find.byType(Wrap), findsOneWidget);
    // a picture much bigger than in one row (a third of the width, 80 %)
    final pics = find.descendant(
      of: find.byType(Wrap),
      matching: find.byType(EmojiImage),
    );
    expect(pics, findsNWidgets(3));
    expect(
      t.getSize(pics.first).width,
      greaterThan((393 - 64) / 3 * 0.8 * 1.3),
    );
    await close(t);
  });

  for (final (name, size, text) in [
    ('portrait', const Size(360, 640), 1.0),
    ('landscape', const Size(640, 360), 1.0),
    ('large text', const Size(360, 640), 1.6),
    ('landscape, large text', const Size(640, 360), 1.6),
  ]) {
    testWidgets('game groups, $name', (t) async {
      await show(
        t,
        (app) => HomeScreen(app: app),
        size: size,
        text: text,
      );
      expect(t.takeException(), isNull);
      var games = 0;
      for (final g in ['hear', 'read', 'speak', 'think', 'memory', 'feel']) {
        // landscape: the lower groups are below the fold
        await t.ensureVisible(find.byKey(ValueKey('group-$g')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(ValueKey('group-$g')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: g);
        final tiles = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('game-$g-'),
        );
        expect(tiles, findsWidgets, reason: g);
        games += tiles.evaluate().length;
        // every game shows what it does with sound
        final badges = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('audio-'),
        );
        expect(badges.evaluate().length, tiles.evaluate().length, reason: g);
        await t.pageBack();
        await t.pumpAndSettle();
      }
      expect(games, 17);
      await close(t);
    });

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

    testWidgets('🐞 and its dialog, $name', (t) async {
      await show(
        t,
        (app) => ThinkScreen(
          app: app,
          game: ThinkGame.riddle,
          info: () async => {'app': '1.0', 'phone': 'Test Phone 12'},
        ),
        size: size,
        text: text,
        prefs: {'settings|quizReports': true},
        feedback: true,
      );
      for (var i = 0; i < 300; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('think-report')));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(t.takeException(), isNull);
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
        final n = switch (game) {
          ThinkGame.needs || ThinkGame.home || ThinkGame.feelings => 3,
          ThinkGame.riddle || ThinkGame.odd || ThinkGame.faces => 4,
        };
        for (var o = 0; o < n; o++) {
          await t.tap(find.byKey(ValueKey('think-option-$o')));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(t.takeException(), isNull);
        }
        await close(t);
      });
    }

    for (final game in MemoryGame.values) {
      testWidgets('memory ${game.name}, $name', (t) async {
        await show(
          t,
          (app) => MemoryScreen(app: app, game: game),
          size: size,
          text: text,
        );
        // intro, show (or say), hide: every phase must fit
        for (var i = 0; i < 600; i++) {
          await t.pump(const Duration(milliseconds: 50));
          expect(t.takeException(), isNull, reason: 'at ${i * 50} ms');
        }
        expect(find.byKey(const ValueKey('memory-option-0')), findsOneWidget);
        for (var o = 0; o < memoryOptions(game); o++) {
          final f = find.byKey(ValueKey('memory-option-$o'));
          if (f.evaluate().isEmpty) break;
          await t.tap(f);
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(t.takeException(), isNull);
        }
        await close(t);
      });
    }

    testWidgets('what is missing on a tiny landscape phone, $name', (t) async {
      await show(
        t,
        (app) => MemoryScreen(app: app, game: MemoryGame.missing),
        size: const Size(568, 320),
        text: text,
      );
      for (var i = 0; i < 600; i++) {
        await t.pump(const Duration(milliseconds: 50));
        expect(t.takeException(), isNull, reason: 'at ${i * 50} ms');
      }
      expect(find.byKey(const ValueKey('memory-gap')), findsOneWidget);
      await close(t);
    });

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

class _NoSend implements FeedbackTransport {
  @override
  Future<SendResult> send(Map<String, dynamic> json) async => SendResult.later;
}
