// Drives a play screen and reads what happened from an [IoLog]; shared by
// the widget tests (fake clock) and the tests on a phone (real time).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/game/play_screen.dart';

import 'fakes.dart';

class Game {
  Game._(this.t, this.log, this.words, this.nav, this.step);

  /// Opens world [world] of [app], like the home screen does.
  static Future<Game> open(
    WidgetTester t,
    AppState app,
    IoLog log, {
    int world = 0,
    Duration step = const Duration(milliseconds: 50),
  }) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold()));
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => PlayScreen(app: app, world: world),
      ),
    );
    await t.pump();
    await t.pump();
    return Game._(t, log, app.book.world(world), nav, step);
  }

  final WidgetTester t;
  final IoLog log;
  final List<Phrase> words;
  final GlobalKey<NavigatorState> nav;

  /// How far each pump moves the clock.
  final Duration step;

  late final _texts = {for (final p in words) p.text};

  /// Phrases the phone said (not the praise), in order.
  List<String> get said => [
    for (final s in log.started('tts'))
      if (_texts.contains(s)) s,
  ];

  /// Everything the TTS said that is not a phrase: the praise.
  List<String> get praise => [
    for (final s in log.started('tts'))
      if (!_texts.contains(s)) s,
  ];

  int get recordings => log.started('mic').length;
  int get replays => log.started('replay').length;

  /// The word the phone said last, which the child is answering.
  Phrase get current => words.firstWhere((p) => p.text == said.last);

  Finder get dialog => find.byType(AlertDialog);
  bool showsWord(int n) =>
      find.textContaining('·  $n/${words.length}').evaluate().isNotEmpty;

  /// Devices that are still on.
  List<IoInterval> get running => [
    for (final i in log.intervals())
      if (i.to == null) i,
  ];

  Future<void> wait(Duration d) async {
    for (var e = Duration.zero; e < d; e += step) {
      await t.pump(step);
    }
  }

  /// Pumps until [done] (or fails after [limit]).
  Future<void> until(
    bool Function() done, {
    Duration limit = const Duration(seconds: 30),
    String? reason,
  }) async {
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

  /// Nothing may ever be audible while the microphone records, and no
  /// device call may have been lost.
  void expectClean() {
    expect(log.soundsWhileRecording(), isEmpty, reason: '$log');
    expect(log.problems, isEmpty, reason: '$log');
  }
}
