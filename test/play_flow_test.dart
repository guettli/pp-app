// The whole play screen with fake devices: what happens after the child has
// spoken, without anyone tapping, and when the child or the phone gets in
// the way. The fake clock runs the timers, so a world takes a second.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/game/play_screen.dart';
import 'package:phoneme_party/game/rules.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

late PhonemeComparer comparer;
late PhraseBook book;

/// IPA the fake recognizer answers for a word said badly.
const mumble = 'ŋŋ';

class Game {
  Game(this.t, this.dev, this.nav);
  final WidgetTester t;
  final FakeDevices dev;
  final GlobalKey<NavigatorState> nav;

  IoLog get log => dev.log;
  List<Phrase> get words => book.world(0);

  /// Phrases the phone said (not the praise), in order.
  List<String> get said {
    final texts = {for (final p in words) p.text};
    return [
      for (final s in log.started('tts'))
        if (texts.contains(s)) s,
    ];
  }

  /// Everything the TTS said that is not a phrase: the praise.
  List<String> get praise {
    final texts = {for (final p in words) p.text};
    return [
      for (final s in log.started('tts'))
        if (!texts.contains(s)) s,
    ];
  }

  int get recordings => log.started('mic').length;

  /// The word the phone said last, which the child is answering.
  Phrase get current {
    final texts = said;
    return words.firstWhere((p) => p.text == texts.last);
  }

  Finder get dialog => find.byType(AlertDialog);
  bool showsWord(int n) =>
      find.textContaining('·  $n/${words.length}').evaluate().isNotEmpty;

  Future<void> wait(Duration d) async {
    const step = Duration(milliseconds: 50);
    for (var e = Duration.zero; e < d; e += step) {
      await t.pump(step);
    }
  }

  /// Pumps until [done] (or fails after [limit] of fake time).
  Future<void> until(
    bool Function() done, {
    Duration limit = const Duration(seconds: 30),
    String? reason,
  }) async {
    const step = Duration(milliseconds: 50);
    for (var e = Duration.zero; e < limit; e += step) {
      if (done()) return;
      await t.pump(step);
    }
    fail('timed out: ${reason ?? ''}\n$log');
  }

  Future<void> tap(String tooltip) async {
    await t.tap(find.byTooltip(tooltip));
    await t.pump();
  }

  Future<void> lifecycle(AppLifecycleState s) async {
    t.binding.handleAppLifecycleStateChanged(s);
    await t.pump();
  }

  /// Nothing may ever be audible while the microphone records.
  void expectNothingRecorded() =>
      expect(log.soundsWhileRecording(), isEmpty, reason: '$log');
}

Future<Game> start(
  WidgetTester t, {
  String Function(Game g)? answer,
  Child Function()? child,
  bool canReplay = true,
  bool permission = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final progress = await Progress.load();
  final t0 = t.binding.clock.now();
  final log = IoLog(() => t.binding.clock.now().difference(t0));
  final dev = FakeDevices(log, child: child, canReplay: canReplay);
  dev.mic.permission = permission;
  late final Game game;
  final rec = FakeRecognizer(
    () => answer == null ? game.current.ipa : answer(game),
  );
  final app = AppState(rec, comparer, progress, book, io: dev.io);
  final nav = GlobalKey<NavigatorState>();
  await t.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold()));
  nav.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => PlayScreen(app: app, world: 0)),
  );
  game = Game(t, dev, nav);
  await t.pump();
  await t.pump();
  return game;
}

void main() {
  setUpAll(() {
    comparer = PhonemeComparer.fromJson(
      File('assets/panphon/panphon_features.json').readAsStringSync(),
    );
    final raw = File('assets/phrases/de-DE.json').readAsStringSync();
    book = PhraseBook('de-DE', [
      for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        Phrase.fromJson(j),
    ]);
  });

  test('the fake answers score as intended', () {
    final w = book.world(0);
    for (final p in w) {
      expect(scorePhrase(comparer, p, p.ipa, 'de-DE').stars, 3, reason: p.text);
      expect(
        scorePhrase(comparer, p, mumble, 'de-DE').stars,
        0,
        reason: p.text,
      );
    }
  });

  testWidgets('a whole world goes by itself, nothing is recorded but the '
      'child', (t) async {
    final g = await start(t);
    await g.until(
      () => g.dialog.evaluate().isNotEmpty,
      limit: const Duration(minutes: 3),
      reason: 'world-done dialog',
    );
    expect(g.said, [for (final p in g.words) p.text]);
    expect(g.recordings, g.words.length);
    expect(g.dev.player.plays, g.words.length, reason: 'one replay per word');
    // praise for every word, and never the same twice in a row
    final praise = g.praise;
    expect(praise.length, greaterThanOrEqualTo(g.words.length));
    for (var i = 1; i < praise.length; i++) {
      expect(praise[i], isNot(praise[i - 1]));
    }
    g.expectNothingRecorded();

    // the round is over: nothing starts behind the dialog
    final mics = g.recordings, players = g.dev.player.plays;
    await g.wait(const Duration(seconds: 20));
    expect(g.recordings, mics);
    expect(g.dev.player.plays, players);
    expect(g.dialog, findsOneWidget);
    expect(g.log.intervals().where((i) => i.to == null), isEmpty);
  });

  testWidgets('0 stars: one more try, then on to the next word', (t) async {
    final g = await start(t, answer: (_) => mumble);
    await g.until(() => g.recordings == 2, reason: 'retry');
    expect(g.said, [g.words[0].text, g.words[0].text]);
    expect(g.showsWord(1), isTrue);
    await g.until(() => g.recordings == 3, reason: 'next word');
    expect(g.said.last, g.words[1].text);
    expect(g.showsWord(2), isTrue);
    g.expectNothingRecorded();
  });

  testWidgets('nothing heard: waits for a tap', (t) async {
    final g = await start(t, child: () => Child.silent);
    await g.until(
      () => g.recordings == 1 && g.log.intervals('mic').single.to != null,
    );
    await g.wait(const Duration(milliseconds: 500));
    expect(find.byType(SnackBar), findsOneWidget);
    await g.wait(const Duration(seconds: 15));
    expect(g.recordings, 1);
    expect(g.dev.player.plays, 0);
    await g.tap('Speak');
    await g.until(() => g.recordings == 2);
    expect(g.said, [g.words[0].text, g.words[0].text]);
  });

  testWidgets('no microphone permission: nothing is said or recorded', (
    t,
  ) async {
    final g = await start(t, permission: false);
    await g.wait(const Duration(milliseconds: 500));
    expect(find.byType(SnackBar), findsOneWidget);
    await g.wait(const Duration(seconds: 10));
    expect(g.recordings, 0);
    expect(g.said, isEmpty);
  });

  testWidgets('background during the praise: everything stops, and it goes '
      'on when the app is back', (t) async {
    final g = await start(t);
    await g.until(() => g.praise.isNotEmpty, reason: 'praise');
    await g.lifecycle(AppLifecycleState.paused);
    expect(g.log.intervals().where((i) => i.to == null), isEmpty);
    await g.wait(const Duration(seconds: 20));
    expect(g.recordings, 1);
    expect(g.log.intervals().where((i) => i.to == null), isEmpty);
    await g.lifecycle(AppLifecycleState.resumed);
    await g.until(() => g.recordings == 2, reason: 'next word after resume');
    expect(g.said.last, g.words[1].text);
    g.expectNothingRecorded();
  });

  testWidgets('background while listening: the recording is dropped', (
    t,
  ) async {
    final g = await start(t);
    await g.until(() => g.dev.mic.recording);
    await g.lifecycle(AppLifecycleState.paused);
    expect(g.dev.mic.recording, isFalse);
    await g.wait(const Duration(seconds: 20));
    expect(g.recordings, 1);
    expect(g.praise, isEmpty);
    await g.lifecycle(AppLifecycleState.resumed);
    await g.wait(const Duration(seconds: 5));
    expect(g.recordings, 1, reason: 'waits for a tap');
  });

  testWidgets('Next during the praise skips the rest at once', (t) async {
    final g = await start(t);
    await g.until(() => g.praise.isNotEmpty);
    final said = g.praise.last;
    await g.tap('Next');
    expect(
      g.log.intervals('tts').lastWhere((i) => i.what == said).to,
      isNotNull,
      reason: 'the praise stops at once',
    );
    await g.until(() => g.recordings == 2);
    expect(g.dev.player.plays, 0, reason: 'no replay of the old word');
    expect(g.said, [g.words[0].text, g.words[1].text]);
    g.expectNothingRecorded();
  });

  testWidgets('listen again during the replay, then it goes on', (t) async {
    final g = await start(t);
    await g.until(() => g.dev.player.plays == 1);
    await g.tap('Listen');
    expect(g.log.intervals('replay').last.to, isNotNull);
    await g.until(() => g.said.length == 2);
    expect(g.said, [g.words[0].text, g.words[0].text]);
    await g.until(() => g.recordings == 2, reason: 'goes on afterwards');
    expect(g.said.last, g.words[1].text);
    g.expectNothingRecorded();
  });

  testWidgets('funny voice tapped again: plays once more, then goes on', (
    t,
  ) async {
    final g = await start(t);
    await g.until(() => g.dev.player.plays == 1);
    await g.until(() => g.log.intervals('replay').last.to != null);
    await g.tap('Funny voice');
    expect(g.dev.player.plays, 2);
    await g.until(() => g.recordings == 2);
    expect(g.said.last, g.words[1].text);
    g.expectNothingRecorded();
  });

  testWidgets('a stuck TTS engine does not stop the game', (t) async {
    final g = await start(t);
    g.dev.speaker.hang = true;
    await g.until(() => g.recordings == 2, limit: const Duration(minutes: 1));
    g.expectNothingRecorded();
  });

  testWidgets('without replay (iOS) it still goes on', (t) async {
    final g = await start(t, canReplay: false);
    await g.until(() => g.recordings == 3);
    expect(g.dev.player.plays, 0);
    expect(find.byTooltip('Funny voice'), findsNothing);
    g.expectNothingRecorded();
  });

  testWidgets('closing the screen stops everything', (t) async {
    final g = await start(t);
    await g.until(() => g.praise.isNotEmpty);
    g.nav.currentState!.pop();
    await g.wait(const Duration(seconds: 1));
    expect(g.log.intervals().where((i) => i.to == null), isEmpty);
    await g.wait(const Duration(seconds: 20));
    expect(g.recordings, 1);
    expect(t.takeException(), isNull);
  });
}
