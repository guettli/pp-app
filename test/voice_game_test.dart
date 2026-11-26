// The voice games with fake devices on the fake clock: the child's
// "voice" is a synthetic sound at a chosen pitch and length.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/ui/intros.dart';
import 'package:phoneme_party/app_state.dart';
import 'package:phoneme_party/data/phrases.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';
import 'package:phoneme_party/voice/voice_lines.dart';
import 'package:phoneme_party/voice/voice_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/sounds.dart';

late PhonemeComparer comparer;
late PhraseBook book;

/// What the child does on each try, in order (the last one repeats).
typedef Tries = List<List<double>>;

/// [seconds] of "Aaaa" at [hz], after a short pause.
List<double> aaa(double hz, double seconds) => [
  ...noise(0.4),
  ...voice(hz, seconds),
  ...noise(2),
];

class VoiceRun {
  VoiceRun(this.t, this.dev, this.progress, this.nav);
  final WidgetTester t;
  final FakeDevices dev;
  final Progress progress;
  final GlobalKey<NavigatorState> nav;

  IoLog get log => dev.log;
  int get tries => log.started('mic').length;
  List<String> get said => log.started('tts');
  Finder get dialog => find.byType(AlertDialog);

  Future<void> wait(Duration d) async {
    const step = Duration(milliseconds: 50);
    for (var e = Duration.zero; e < d; e += step) {
      await t.pump(step);
    }
  }

  Future<void> until(
    bool Function() done, {
    Duration limit = const Duration(seconds: 60),
    String? reason,
  }) async {
    const step = Duration(milliseconds: 50);
    for (var e = Duration.zero; e < limit; e += step) {
      if (done()) return;
      await t.pump(step);
    }
    fail('timed out: ${reason ?? ''}\n$log');
  }

  List<IoInterval> get running => [
    for (final i in log.intervals())
      if (i.to == null) i,
  ];

  void expectClean() {
    expect(log.soundsWhileRecording(), isEmpty, reason: '$log');
    expect(log.problems, isEmpty, reason: '$log');
  }
}

Future<VoiceRun> open(
  WidgetTester t,
  VoiceGame game,
  Tries tries, {
  void Function(FakeDevices dev)? prepare,
  String Function()? recognized,
  FakeQuizReports? reports,
}) async {
  SharedPreferences.setMockInitialValues({});
  final progress = await Progress.load();
  if (reports != null) await progress.setQuizReports(true);
  final t0 = t.binding.clock.now();
  final log = IoLog(() => t.binding.clock.now().difference(t0));
  final dev = FakeDevices(log);
  var n = 0;
  dev.mic.script = () => tries[(n++).clamp(0, tries.length - 1)];
  prepare?.call(dev);
  // what the recognizer hears in a held sound ('': nothing clear)
  final rec = FakeRecognizer(recognized ?? () => '');
  final app = AppState(
    rec,
    comparer,
    progress,
    book,
    io: dev.io,
    quizReports: reports,
  );
  final nav = GlobalKey<NavigatorState>();
  await t.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold()));
  nav.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => VoiceGameScreen(app: app, game: game),
    ),
  );
  await t.pump();
  await t.pump();
  return VoiceRun(t, dev, progress, nav);
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
  final lines = VoiceLines.of('de-DE');

  testWidgets('hold it long: every sound by itself, the best is kept', (
    t,
  ) async {
    final r = await open(t, VoiceGame.hold, [aaa(250, 5.5)]);
    await r.until(
      () => r.dialog.evaluate().isNotEmpty,
      limit: const Duration(minutes: 3),
    );
    final sounds = lines.sounds;
    expect(r.tries, sounds.length);
    for (final s in sounds) {
      expect(r.said, contains(lines.holdSay(s)));
      expect(
        r.progress.holdBest('de-DE', s.shown).inMilliseconds,
        closeTo(5500, 150),
      );
    }
    // the first time is always a record
    expect(r.said.where((s) => s.endsWith(lines.record)), hasLength(5));
    // without noise suppression, which would fade a steady vowel out
    expect(r.dev.mic.voiceProcessing, isFalse);
    r.expectClean();
    await r.wait(const Duration(seconds: 10));
    expect(r.tries, sounds.length);
    expect(r.dialog, findsOneWidget);
    expect(r.running, isEmpty);
  });

  testWidgets('hold it long: another sound than asked for does not count', (
    t,
  ) async {
    // the child always says O; the first sound is A
    final r = await open(t, VoiceGame.hold, [
      aaa(250, 5.5),
    ], recognized: () => 'oː');
    final a = lines.sounds[0], o = lines.sounds[1];
    await r.until(() => r.tries == 3, reason: 'A twice, then O');
    expect(r.said, contains(lines.holdWrong(a, 'o')));
    expect(lines.holdWrong(a, 'o'), 'Das klang wie O, nicht wie A.');
    expect(r.said.where((s) => s == lines.holdSay(a)), hasLength(2));
    expect(r.progress.holdBest('de-DE', a.shown), Duration.zero);
    await r.until(() => r.tries == 4, reason: 'then U');
    // the O was right
    expect(
      r.progress.holdBest('de-DE', o.shown).inMilliseconds,
      closeTo(5500, 150),
    );
    r.expectClean();
  });

  testWidgets('hold it long: 🐞 sends the sound with what was heard', (
    t,
  ) async {
    final reports = FakeQuizReports();
    final r = await open(
      t,
      VoiceGame.hold,
      [aaa(250, 5.5)],
      recognized: () => 'oː',
      reports: reports,
    );
    final a = lines.sounds[0];
    final bug = find.byTooltip('Send to the developer');
    expect(bug, findsOneWidget);
    await r.until(() => r.said.contains(lines.holdWrong(a, 'o')));
    await t.tap(bug);
    await t.pump();
    await t.tap(find.text('Send'));
    await r.wait(const Duration(seconds: 1));
    final sent = reports.sent.single;
    expect(sent.question, 'hold: A');
    expect(sent.answer, 'A');
    final tr = sent.tries.single;
    expect(tr.heard, 'oː');
    expect(tr.said, 'o'); // heard instead of the A
    expect(tr.scores.single.score, 0);
    // the held sound, with a little before and after
    expect(tr.pcm.length, greaterThan(5 * 32000));
    expect(tr.pcm.length, lessThan(7 * 32000));
    // the game waits: no new try while the dialog was open, nor after
    expect(r.running.where((i) => i.device == 'mic'), isEmpty);
    r.expectClean();
  });

  testWidgets('hold it long: reports off, no 🐞', (t) async {
    final r = await open(t, VoiceGame.hold, [aaa(250, 3.5)]);
    await r.until(() => r.tries == 1);
    expect(find.byTooltip('Send to the developer'), findsNothing);
    r.expectClean();
  });

  testWidgets('hold it long: only the time of the right sound counts', (
    t,
  ) async {
    // A for two thirds of the time, then O
    final r = await open(t, VoiceGame.hold, [
      aaa(250, 5.4),
    ], recognized: () => 'aao');
    await r.until(() => r.tries == 2, reason: 'the next sound');
    expect(
      r.progress.holdBest('de-DE', lines.sounds[0].shown).inMilliseconds,
      closeTo(3600, 150),
    );
    r.expectClean();
  });

  testWidgets('hold it long: too short gets one more try', (t) async {
    final r = await open(t, VoiceGame.hold, [aaa(250, 1.5), aaa(250, 3.5)]);
    await r.until(() => r.tries == 3, reason: 'retry, then the next sound');
    final first = lines.holdSay(lines.sounds[0]);
    expect(r.said.where((s) => s == first), hasLength(2));
    expect(r.said.last, lines.holdSay(lines.sounds[1]));
    expect(
      r.progress.holdBest('de-DE', lines.sounds[0].shown).inMilliseconds,
      closeTo(3500, 150),
    );
    // the first, too short try is no record to cheer about
    final cheer = r.said.indexWhere((s) => s.contains(lines.record));
    final retry = r.said.indexOf(first, r.said.indexOf(first) + 1);
    // ... the 3.5 s one is
    expect(cheer, greaterThan(retry), reason: '${r.said}');
    r.expectClean();
  });

  testWidgets('low and high: the own voice, then the bear, then the mouse', (
    t,
  ) async {
    final r = await open(t, VoiceGame.pitch, [
      aaa(240, 1.5), // own voice
      aaa(170, 1.5), // 6 semitones lower
      aaa(450, 1.5), // 11 semitones higher
    ]);
    await r.until(() => r.dialog.evaluate().isNotEmpty);
    expect(r.tries, 3);
    expect(r.said.take(1), [lines.pitchNormal]);
    expect(r.said, containsAllInOrder([lines.pitchLow, lines.pitchHigh]));
    // the phone shows how: low, then high
    final instr = [
      for (final (i, s) in r.said.indexed)
        if ([lines.pitchNormal, lines.pitchLow, lines.pitchHigh].contains(s))
          r.dev.speaker.pitches[i],
    ];
    expect(instr, [1, lessThan(1), greaterThan(1)]);
    expect(r.progress.pitchBest(low: true), closeTo(6, 0.3));
    expect(r.progress.pitchBest(low: false), closeTo(11, 0.3));
    r.expectClean();
    await r.wait(const Duration(seconds: 3)); // the fanfare
  });

  testWidgets('low and high: not low enough, one more try', (t) async {
    final r = await open(t, VoiceGame.pitch, [
      aaa(240, 1.5),
      aaa(235, 1.5), // hardly lower
      aaa(180, 1.5), // 5 semitones lower
      aaa(400, 1.5),
    ]);
    await r.until(() => r.dialog.evaluate().isNotEmpty);
    expect(r.tries, 4);
    expect(r.said.where((s) => s == lines.pitchLow), hasLength(2));
    expect(r.progress.pitchBest(low: true), closeTo(5, 0.3));
    r.expectClean();
    await r.wait(const Duration(seconds: 3)); // the fanfare
  });

  testWidgets('silence: says nothing was heard and waits', (t) async {
    final r = await open(t, VoiceGame.hold, [noise(10)]);
    // the first time it asks again by itself, then waits for a tap
    await r.until(() => r.tries == 2 && !r.dev.mic.recording);
    await r.wait(const Duration(milliseconds: 500));
    await r.until(() => find.byType(SnackBar).evaluate().isNotEmpty);
    expect(
      r.said.where((s) => s == notHeardLine('de-DE', again: true)),
      hasLength(1),
    );
    expect(r.said.last, notHeardLine('de-DE', again: false));
    await r.wait(const Duration(seconds: 20));
    expect(r.tries, 2);
    r.expectClean();
  });

  testWidgets('the child taps to finish: what was held counts', (t) async {
    final r = await open(t, VoiceGame.hold, [aaa(250, 12)]);
    await r.until(() => r.dev.mic.recording);
    await r.wait(const Duration(seconds: 4));
    await t.tap(find.byTooltip('Your turn!'));
    await t.pump();
    expect(r.dev.mic.recording, isFalse);
    await r.until(() => r.said.length >= 2);
    expect(
      r.progress.holdBest('de-DE', lines.sounds[0].shown).inMilliseconds,
      closeTo(3600, 300),
    );
    r.expectClean();
  });

  testWidgets('background while holding: the mic goes off, nothing counts', (
    t,
  ) async {
    final r = await open(t, VoiceGame.hold, [aaa(250, 8)]);
    await r.until(() => r.dev.mic.recording);
    await r.wait(const Duration(seconds: 3));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(r.dev.mic.recording, isFalse);
    await r.wait(const Duration(seconds: 20));
    expect(r.tries, 1);
    expect(r.progress.holdBest('de-DE', lines.sounds[0].shown), Duration.zero);
    expect(r.running, isEmpty);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await r.wait(const Duration(seconds: 5));
    expect(r.tries, 1, reason: 'waits for a tap');
  });

  testWidgets('the child starts right away, without a pause', (t) async {
    final r = await open(t, VoiceGame.hold, [
      [...voice(250, 4), ...noise(2)],
    ]);
    await r.until(() => r.said.length >= 2, reason: 'praise');
    expect(
      r.progress.holdBest('de-DE', lines.sounds[0].shown).inMilliseconds,
      closeTo(4000, 300),
    );
    r.expectClean();
  });

  testWidgets('a tap after a too short sound: that sound once more', (t) async {
    final r = await open(t, VoiceGame.hold, [aaa(250, 1), aaa(250, 4)]);
    await r.until(() => r.said.length >= 2, reason: 'result');
    await t.tap(find.byTooltip('Speak'));
    await t.pump();
    await r.until(() => r.tries == 2);
    final first = lines.holdSay(lines.sounds[0]);
    expect(r.said.where((s) => s == first), hasLength(2));
    r.expectClean();
  });

  testWidgets('back on the final dialog: it stays, and opens only once', (
    t,
  ) async {
    final r = await open(t, VoiceGame.pitch, [
      aaa(240, 1.5),
      aaa(170, 1.5),
      aaa(450, 1.5),
    ]);
    await r.until(() => r.dialog.evaluate().isNotEmpty);
    await t.binding.handlePopRoute();
    await t.pump();
    expect(r.dialog, findsOneWidget);
    await t.tap(find.byTooltip('Speak'), warnIfMissed: false);
    await r.wait(const Duration(seconds: 5));
    expect(r.dialog, findsOneWidget);
    expect(r.tries, 3);
  });

  testWidgets('own voice too short: once more, then a typical voice', (
    t,
  ) async {
    final r = await open(t, VoiceGame.pitch, [
      aaa(240, 0.25),
      aaa(240, 0.25),
      aaa(180, 1.5), // the bear
      aaa(450, 1.5),
    ]);
    await r.until(() => r.dialog.evaluate().isNotEmpty);
    expect(r.said.where((s) => s == lines.pitchNormal), hasLength(2));
    // 180 Hz against a typical child (260 Hz): 6.4 semitones lower
    expect(r.progress.pitchBest(low: true), closeTo(6.4, 0.3));
    r.expectClean();
    await r.wait(const Duration(seconds: 3)); // the fanfare
  });

  testWidgets('background while the phone speaks: the mic never opens', (
    t,
  ) async {
    final r = await open(t, VoiceGame.hold, [aaa(250, 4)]);
    await r.until(() => r.dev.speaker.speaking);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    await r.wait(const Duration(seconds: 10));
    expect(r.tries, 0);
    expect(r.running, isEmpty);
  });

  testWidgets('background while the mic starts: it goes off again', (t) async {
    final r = await open(t, VoiceGame.hold, [aaa(250, 4)]);
    r.dev.mic.startup = const Duration(milliseconds: 300);
    await r.until(() => r.log.started('tts').isNotEmpty);
    await r.until(() => !r.dev.speaker.speaking);
    await r.wait(const Duration(milliseconds: 400)); // inside the start
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    await r.wait(const Duration(seconds: 2));
    expect(r.dev.mic.recording, isFalse);
    expect(r.running, isEmpty);
  });

  testWidgets('the permission check fails: a message, no dead screen', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final r = await open(
      t,
      VoiceGame.hold,
      [aaa(250, 4)],
      prepare: (dev) {
        dev.mic.permissionThrows = true;
      },
    );
    await r.wait(const Duration(milliseconds: 500));
    expect(find.byType(SnackBar), findsOneWidget);
    r.dev.mic.permissionThrows = false;
    await t.tap(find.byTooltip('Speak'));
    await r.until(() => r.tries == 1, reason: 'works after a tap');
  });

  testWidgets('closing the screen while holding stops the mic', (t) async {
    final r = await open(t, VoiceGame.hold, [aaa(250, 8)]);
    await r.until(() => r.dev.mic.recording);
    r.nav.currentState!.pop();
    await r.wait(const Duration(seconds: 1));
    expect(r.dev.mic.recording, isFalse);
    await r.wait(const Duration(seconds: 20));
    expect(r.running, isEmpty);
    expect(r.tries, 1);
  });
}
