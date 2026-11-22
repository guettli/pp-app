// 🐞 recording reports, in every game that listens to words or sounds: the
// quiz, the worlds, read aloud, hold it long. They send what the child
// said (the recording) with what the app heard, so the recognition can be
// improved. Off unless a grown-up switched them on behind the parent gate
// (feedback screen); then a 🐞 button sends the last tries, after asking
// (the dialog can play them first). Memory only: nothing is kept on the
// phone, and a report that cannot be sent now is not sent.
//
// The service takes them as quiz reports (lib/net/quiz_report.dart): the
// question says which game ("Welt 2: Hase"), the options the asked word(s)
// with their IPA.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../game/game_io.dart';
import '../net/feedback.dart';
import '../net/quiz_report.dart';
import 'emoji_image.dart';
import 'round_button.dart';
import 'strings.dart';

/// What a report says about the asked thing (besides the tries).
typedef ReportTopic = ({
  String question,
  String asked,
  List<({String text, List<String> ipa})> options,
  String answer,
});

/// The report state of one game screen.
class RecordingReports {
  RecordingReports(this.app, {Future<Map<String, String>> Function()? info})
    : info = info ?? app.io.info;

  final AppState app;
  final Future<Map<String, String>> Function() info;

  /// The tries kept (the last two of [of]), memory only.
  List<QuizTry> get tries => _tries;
  List<QuizTry> _tries = const [];

  /// What the kept tries were at (a question, a word, a sound).
  Object? get of => _of;
  Object? _of;

  /// The dialog is open (or about to): one at a time, and a recording may
  /// only play while it is open.
  bool asking = false;
  bool sending = false;
  bool sent = false;

  /// Plays a recording in the dialog; created when first needed.
  SoundOut? _replay;

  /// A grown-up switched reports on (and the app can send them).
  bool get on => app.quizReports != null && app.progress.quizReports;

  bool get canSend => _tries.isNotEmpty && !sending && !sent && !asking;

  /// Keeps [t], a try at [of] (compared with ==): the last two of it (the
  /// service takes two). A try at something else starts anew.
  void keep(Object of, QuizTry t) {
    if (!on) return;
    if (_of != of) {
      _tries = const [];
      _of = of;
    }
    sent = false;
    _tries = [..._tries.skip(_tries.length >= 2 ? 1 : 0), t];
  }

  Future<void> stopReplay() async {
    final r = _replay;
    if (r != null) await _quietly(r.stop);
  }

  void dispose() {
    final r = _replay;
    if (r != null) _quietly(r.dispose);
  }

  /// 🐞: [hold] stops the game (the mic first) and waits; then the dialog
  /// asks, then the report about [topic] (of the kept tries' [of]) goes
  /// out. [update] redraws the screen; [paused]: the app is in the
  /// background (a recording must not play then).
  Future<void> send(
    State host, {
    required Future<void> Function() hold,
    required ReportTopic Function(Object of) topic,
    required void Function() update,
    required bool Function() paused,
  }) async {
    final sender = app.quizReports;
    if (sender == null || !canSend) return;
    final tries = _tries;
    final about = topic(_of!);
    final context = host.context;
    final uiLang = Localizations.maybeLocaleOf(context)?.languageCode ?? '';
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    asking = true;
    update();
    bool ok;
    try {
      await hold();
      if (!host.mounted) return;
      ok = await _confirm(host, about.asked, tries, paused);
    } finally {
      asking = false;
      await stopReplay();
      if (host.mounted) update();
    }
    // sent meanwhile, or new tries: not this one
    if (!ok || !host.mounted || sent || !identical(tries, _tries)) return;
    sending = true;
    update();
    Map<String, String> device;
    try {
      device = await info();
    } catch (_) {
      device = const {};
    }
    final lang = app.book.lang;
    final report = QuizReport(
      id: FeedbackReport.newId(math.Random.secure()),
      created: DateTime.now(),
      info: {...device, 'studyLang': lang, 'uiLang': uiLang},
      lang: lang,
      question: about.question,
      asked: about.asked,
      options: about.options,
      answer: about.answer,
      tries: tries,
    );
    SendResult result;
    try {
      result = await sender.send(report);
    } catch (e, st) {
      debugPrint('recording report failed: $e\n$st');
      result = SendResult.later;
    }
    if (!host.mounted) return;
    sending = false;
    // not if new tries came meanwhile
    if (result == SendResult.done && identical(tries, _tries)) sent = true;
    update();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result == SendResult.done ? s.quizReportSent : s.quizReportFailed,
        ),
      ),
    );
  }

  /// The dialog before a report: what is sent, the recordings to listen
  /// to (only if the player keeps them in memory), send or not.
  Future<bool> _confirm(
    State host,
    String asked,
    List<QuizTry> tries,
    bool Function() paused,
  ) async {
    final context = host.context;
    final s = S.of(context);
    final replay = _replay ??= app.io.replayPlayer();
    final canPlay = replay.playsFromMemory;
    final ok = await showDialog<bool>(
      context: context,
      // closes with the game page
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: Text(s.quizReportAsk),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(asked),
              if (canPlay)
                for (final (i, t) in tries.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      key: ValueKey('report-play-$i'),
                      onPressed: () => _quietly(() async {
                        await replay.stop();
                        // closed meanwhile: must not play (the mic may
                        // open next)
                        if (!asking || paused() || !host.mounted) return;
                        await replay.play(pcmWav(t.pcm));
                      }),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        tries.length > 1
                            ? '${s.listenRecording} ${i + 1}'
                            : s.listenRecording,
                      ),
                    ),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.send),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// The 🐞 button (only shown while reports are on).
  Widget button(S s, VoidCallback onTap) => RoundButton(
    key: const ValueKey('report'),
    tooltip: s.quizReportSend,
    onTap: canSend ? onTap : null,
    color: const Color(0xFF6D4C41),
    child: sending
        ? const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(color: Colors.white),
          )
        : const EmojiImage('🐞', size: 40),
  );

  static Future<void> _quietly(Future<void> Function() f) async {
    try {
      await f();
    } catch (e, st) {
      debugPrint('report replay failed: $e\n$st');
    }
  }
}
