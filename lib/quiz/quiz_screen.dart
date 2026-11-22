// The quiz: the phone asks "What can fly? Tree, bird or house?", shows the
// three pictures, and the child answers by saying the word. Eight
// questions a round, about the words the child already plays with. A word
// the phone did not understand is asked once more instead of being marked
// wrong. Tapping a picture says its word (not while listening).
//
// If a grown-up switched on quiz reports (feedback screen), a 🐞 button
// sends the question just played, with the child's recordings, to the
// developer (lib/net/quiz_report.dart), after asking: the dialog can play
// the recordings first (only from memory, never from a file). Without
// reports, recordings are dropped after scoring.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/phrases.dart';
import '../game/feedback.dart';
import '../game/game_io.dart';
import '../game/rocket_launch.dart';
import '../game/voice_effects.dart';
import '../net/device_info.dart';
import '../net/feedback.dart' show FeedbackReport, SendResult;
import '../net/quiz_report.dart';
import '../ui/emoji_image.dart';
import '../ui/intros.dart';
import '../ui/round_button.dart';
import '../ui/round_parts.dart';
import '../ui/strings.dart';
import 'facts.dart';
import 'quiz_lines.dart';
import 'quiz_rules.dart';
import 'sound_rules.dart';
import 'word_listener.dart';

enum _Phase { ready, speaking, listening, thinking, result }

class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.app,
    this.round,
    this.info = deviceInfo,
    this.sounds = false,
    this.intro = true,
  });

  /// Say what to do before the first word (off in tests of the flow).
  final bool intro;

  final AppState app;

  /// The sound detective: "What starts like Maus?" (quiz/sound_rules.dart)
  /// instead of questions about the things.
  final bool sounds;

  /// The questions; a new random round if null.
  final List<QuizQuestion>? round;

  /// App version, phone and Android version for a quiz report (replaced
  /// in tests).
  final Future<Map<String, String>> Function() info;

  /// Questions per round.
  static const questions = 8;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final WordListener _listener;
  late final Speaker _tts;
  late final SoundOut _sfx;

  /// Plays a recording in the report dialog; created when first needed.
  SoundOut? _replay;
  late final math.Random _rng;
  late final QuizLines _lines = QuizLines.of(_lang);
  late final List<QuizQuestion> _round = widget.round ?? _makeRound();

  _Phase _phase = _Phase.ready;
  int _index = 0;

  /// Tries of the current question that were not understood.
  int _unclear = 0;

  /// Per question: right (true), wrong (false), not yet (null).
  late final List<bool?> _results = List.filled(_round.length, null);

  /// The tries of the question played last, for a quiz report (only kept
  /// when reports are on; memory only).
  List<QuizTry> _tries = [];
  int _triesOf = -1;
  bool _reportSending = false;

  /// The intro (what to do) was said: once, before the first word.
  late bool _introDone = !widget.intro;

  /// The report dialog is open (or about to): one at a time, and the
  /// replay may only play while it is open.
  bool _reportAsking = false;
  bool _reportSent = false;

  /// What the child said for the current question (shown in the result).
  Phrase? _chosen;
  String? _lastPraise;

  /// Incremented to stop whatever runs (new try, pause, closing).
  int _flow = 0;
  bool _paused = false;
  bool _over = false;
  Timer? _onward;
  Timer? _donePraise;

  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  String get _lang => widget.app.book.lang;
  QuizQuestion get _q => _round[_index];
  bool get _idle => _phase == _Phase.ready || _phase == _Phase.result;
  bool _current(int id) => mounted && id == _flow && !_paused;

  /// The words of the open worlds (at least the first three), so the
  /// child knows them; all words if that is not enough for a round.
  List<QuizQuestion> _makeRound() {
    final app = widget.app;
    final book = app.book;
    final pool = app.knownWords();
    bool similar(Phrase a, Phrase b) =>
        soundsSimilar(app.comparer, book.lang, a, b);
    if (widget.sounds) {
      List<QuizQuestion> make(List<Phrase> from) => makeSoundRound(
        from,
        app.comparer,
        book.lang,
        _rng,
        count: QuizScreen.questions,
        similar: similar,
      );
      final round = make(pool);
      return round.length >= QuizScreen.questions ? round : make(book.phrases);
    }
    final round = makeRound(
      pool,
      app.facts,
      _rng,
      count: QuizScreen.questions,
      similar: similar,
    );
    if (round.length >= QuizScreen.questions) return round;
    return makeRound(
      book.phrases,
      app.facts,
      _rng,
      count: QuizScreen.questions,
      similar: similar,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final io = widget.app.io;
    _listener = WordListener(io.mic());
    _tts = io.speaker();
    _sfx = io.soundPlayer();
    _rng = io.random();
    _tts.setLanguage(_lang);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  @override
  void dispose() {
    _flow++;
    WidgetsBinding.instance.removeObserver(this);
    _onward?.cancel();
    _donePraise?.cancel();
    _listener.dispose();
    _quietly(_tts.stop);
    _quietly(_sfx.dispose);
    final replay = _replay;
    if (replay != null) _quietly(replay.dispose);
    _bounce.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Not on `inactive`: the permission dialog causes that.
    if (state == AppLifecycleState.paused) {
      _paused = true;
      _flow++;
      _onward?.cancel();
      _donePraise?.cancel();
      _listener.cancel(); // the mic first
      _quietly(_tts.stop);
      _quietly(_sfx.stop);
      final replay = _replay;
      if (replay != null) _quietly(replay.stop);
      if (!_idle && mounted) setState(() => _phase = _Phase.ready);
    } else if (state == AppLifecycleState.resumed) {
      _paused = false; // goes on with a tap
    }
  }

  Future<void> _say(String text) async {
    try {
      await _tts.stop();
      await _tts
          .speak(text)
          .timeout(Duration(seconds: 3 + text.length ~/ 4), onTimeout: () {});
    } catch (e, st) {
      debugPrint('tts failed: $e\n$st');
    }
  }

  static Future<void> _quietly(Future<void> Function() f) async {
    try {
      await f();
    } catch (e, st) {
      debugPrint('sound failed: $e\n$st');
    }
  }

  Future<void> _sound(Float32List s) async {
    if (!_idle || _paused || _listener.listening) return;
    await _quietly(() async {
      await _sfx.stop();
      await _sfx.play(wavBytes(s));
    });
  }

  /// Asks the current question, listens, and scores the answer.
  Future<void> _ask() async {
    if (!_idle || _over || !mounted || _round.isEmpty) return;
    final id = ++_flow;
    _onward?.cancel();
    setState(() {
      _phase = _Phase.speaking;
      _chosen = null;
    });
    await _quietly(_sfx.stop);
    bool allowed;
    try {
      allowed = await _listener.mic.hasPermission();
    } catch (e, st) {
      debugPrint('permission check failed: $e\n$st');
      _fail(id, (s) => s.tryAgain);
      return;
    }
    if (!allowed) {
      _fail(id, (s) => s.needMic);
      return;
    }
    if (!_current(id)) return;
    if (!_introDone) {
      await _say(introLine(GameIntro.sayWord, _lang));
      // cut off (paused, 🐞): said again with the next try
      if (!_current(id)) return;
      _introDone = true;
    }
    await _say(_lines.ask(_q));
    // let the speaker's echo fade before the mic opens
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!_current(id)) return;
    await _quietly(_tts.stop);
    await _quietly(_sfx.stop);
    await _stopReplay();
    // paused or closed meanwhile: the mic must not open
    if (!_current(id)) return;
    setState(() => _phase = _Phase.listening);
    final heard = await _listener.listen(
      onChunk: () {
        if (mounted) setState(() {});
      },
    );
    if (!_current(id)) return;
    if (heard == null) {
      // the mic could not start (cancelling also gives null, but then the
      // flow is not current any more)
      _fail(id, (s) => s.tryAgain);
      return;
    }
    if (!heard.speech) {
      _keepTry(heard, '', null);
      _fail(id, (s) => s.notHeardVoice);
      return;
    }
    setState(() => _phase = _Phase.thinking);
    Phrase? said;
    String? ipa;
    try {
      final rec = await widget.app.recognizer
          .recognize(heard.audio)
          .timeout(const Duration(seconds: 20));
      said = heardOption(
        widget.app.comparer,
        _q.options,
        rec.ipa,
        _lang,
        echo: _q.ask.like,
      );
      debugPrint('quiz: heard "${rec.ipa}" -> ${said?.text}');
      ipa = rec.ipa;
    } catch (e, st) {
      debugPrint('recognition failed: $e\n$st');
      // not when the try was dropped meanwhile (paused, closed)
      if (_current(id)) _keepTry(heard, '', null);
      _fail(id, (s) => s.tryAgain);
      return;
    }
    if (!_current(id)) return;
    _keepTry(heard, ipa, said);
    if (said == null && _unclear == 0) {
      // misheard, or a word that is not one of the three: once more
      _unclear++;
      // still "speaking": taps must not cut it off and ask twice
      setState(() => _phase = _Phase.speaking);
      await _say(_lines.notUnderstood);
      if (!_current(id)) return;
      setState(() => _phase = _Phase.ready);
      unawaited(_ask());
      return;
    }
    await _answered(id, said);
  }

  /// Keeps a try of the current question for a quiz report: the last two
  /// (the server takes two; a question is asked twice at most).
  void _keepTry(Heard heard, String ipa, Phrase? said) {
    if (!_reportsOn) return;
    if (_triesOf != _index) {
      _tries = [];
      _triesOf = _index;
    }
    _reportSent = false;
    _tries = [
      ..._tries.skip(_tries.length >= 2 ? 1 : 0),
      QuizTry(
        pcm: heard.pcm,
        speech: heard.speech,
        heard: ipa,
        said: said?.text,
        scores: optionScores(widget.app.comparer, _q.options, ipa, _lang),
      ),
    ];
  }

  bool get _reportsOn =>
      widget.app.quizReports != null && widget.app.progress.quizReports;

  /// Stops what runs (a question being asked or listened to) and waits
  /// for a tap: the report dialog must not record or be recorded.
  Future<void> _hold() async {
    _flow++;
    _onward?.cancel();
    _donePraise?.cancel();
    await _listener.cancel(); // the mic first
    await _quietly(_tts.stop);
    await _quietly(_sfx.stop);
    await _stopReplay();
    if (mounted && _phase != _Phase.result) {
      setState(() => _phase = _Phase.ready);
    }
  }

  /// 🐞: asks, then sends the question played last with its recordings.
  /// The game holds (the result stays, or the question waits for 🎤).
  Future<void> _sendReport() async {
    final sender = widget.app.quizReports;
    if (sender == null || _tries.isEmpty || _reportSending || _reportAsking) {
      return;
    }
    final tries = _tries;
    final q = _round[_triesOf];
    setState(() => _reportAsking = true);
    bool ok;
    try {
      await _hold();
      if (!mounted) return;
      ok = await _confirmReport(q, tries);
    } finally {
      _reportAsking = false;
      await _stopReplay();
      if (mounted) setState(() {});
    }
    // sent meanwhile, or new tries: not this one
    if (!ok || !mounted || _reportSent || !identical(tries, _tries)) return;
    final uiLang = Localizations.maybeLocaleOf(context)?.languageCode ?? '';
    setState(() => _reportSending = true);
    Map<String, String> device;
    try {
      device = await widget.info();
    } catch (_) {
      device = const {};
    }
    final report = QuizReport(
      id: FeedbackReport.newId(math.Random.secure()),
      created: DateTime.now(),
      info: {...device, 'studyLang': _lang, 'uiLang': uiLang},
      lang: _lang,
      question: _lines.question(q.ask),
      asked: _lines.ask(q),
      options: [
        for (final o in q.options)
          (text: o.text, ipa: [for (final w in o.accepted) w.ipa]),
      ],
      answer: q.answer.text,
      tries: tries,
    );
    SendResult result;
    try {
      result = await sender.send(report);
    } catch (e, st) {
      debugPrint('quiz report failed: $e\n$st');
      result = SendResult.later;
    }
    if (!mounted) return;
    final s = S.of(context);
    setState(() {
      _reportSending = false;
      // not if new tries came meanwhile
      if (result == SendResult.done && identical(tries, _tries)) {
        _reportSent = true;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == SendResult.done ? s.quizReportSent : s.quizReportFailed,
        ),
      ),
    );
  }

  /// The dialog before a report: what is sent, the recordings to listen
  /// to (only if the player keeps them in memory), send or not.
  Future<bool> _confirmReport(QuizQuestion q, List<QuizTry> tries) async {
    final s = S.of(context);
    final replay = _replay ??= widget.app.io.replayPlayer();
    final canPlay = replay.playsFromMemory;
    final ok = await showDialog<bool>(
      context: context,
      // closes with the quiz page
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: Text(s.quizReportAsk),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_lines.ask(q)),
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
                        if (!_reportAsking || _paused || !mounted) return;
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

  Future<void> _stopReplay() async {
    final replay = _replay;
    if (replay != null) await _quietly(replay.stop);
  }

  void _fail(int id, String Function(S) message) {
    if (!mounted || id != _flow) return;
    setState(() => _phase = _Phase.ready);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message(S.of(context)))));
  }

  /// [said]: the option the child said, null if still not understood.
  Future<void> _answered(int id, Phrase? said) async {
    final right = said == _q.answer;
    setState(() {
      _phase = _Phase.result;
      _chosen = said;
      _results[_index] = right;
    });
    _bounce.forward(from: 0);
    unawaited(_sound(jingle(right ? 3 : 1, _rng)));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!_current(id)) return;
    final String text;
    if (right) {
      text = pickPraise(_lang, 3, _rng, avoid: _lastPraise);
      _lastPraise = text;
    } else {
      text = _lines.answerIs(_q.answer.text);
    }
    await _say(text);
    if (!_current(id)) return;
    _onward = Timer(const Duration(milliseconds: 900), () {
      if (_current(id) && _phase == _Phase.result) _next();
    });
  }

  void _next() {
    if (_over) return;
    if (_index + 1 >= _round.length) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _unclear = 0;
      _chosen = null;
      _phase = _Phase.ready;
    });
    _ask();
  }

  /// Big button: listening -> done; otherwise ask (again) now.
  void _onMic() {
    switch (_phase) {
      case _Phase.listening:
        _listener.stopNow();
      case _Phase.ready:
        _ask();
      case _Phase.result:
        _flow++;
        _onward?.cancel();
        _quietly(_tts.stop);
        _next();
      case _Phase.speaking || _Phase.thinking:
        break;
    }
  }

  /// 🔊: hear the question again (before answering).
  Future<void> _again() async {
    if (_phase != _Phase.ready) return;
    await _say(_lines.ask(_q));
  }

  /// A picture: says its word, so the child knows what to say.
  Future<void> _sayOption(Phrase p) async {
    if (!_idle) return;
    if (_phase == _Phase.result) {
      _flow++; // stay on the result until the child goes on
      _onward?.cancel();
    }
    await _say(p.text);
  }

  Future<void> _finish() async {
    _over = true;
    _flow++;
    final right = _results.where((r) => r == true).length;
    final stars = quizStars(right, _round.length);
    var record = false;
    try {
      final progress = widget.app.progress;
      record = widget.sounds
          ? await progress.recordSounds(_lang, stars)
          : await progress.recordQuiz(_lang, stars);
    } catch (e, st) {
      debugPrint('saving the quiz record failed: $e\n$st');
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.ready);
    // not when the app went to the background meanwhile
    unawaited(_sound(fanfare(_rng)));
    // the round is done: at least a "well done", never "almost"
    var text = pickPraise(_lang, math.max(stars, 2), _rng, avoid: _lastPraise);
    if (record) text = '$text ${newRecordLine(_lang)}';
    _donePraise = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && !_paused) _say(text);
    });
    await showRoundEnd(
      context,
      stars: stars,
      right: right,
      total: _round.length,
      record: record,
    );
  }

  static const _text = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w800,
    shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
  );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF14143A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.sounds ? s.soundsTitle : s.quizTitle),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: Starfield()),
            if (_round.isEmpty)
              Center(child: Text(s.tryAgain, style: _text))
            else
              Column(
                children: [
                  ProgressDots(results: _results, index: _index),
                  const SizedBox(height: 16),
                  if (_q.ask.like case final like?)
                    _likeHeader(like)
                  else
                    // large text on a small phone: the question shrinks,
                    // the pictures keep their room
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.17,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: MediaQuery.sizeOf(context).width - 32,
                          child: Text(
                            _lines.question(_q.ask),
                            textAlign: TextAlign.center,
                            style: _text.copyWith(fontSize: 28),
                          ),
                        ),
                      ),
                    ),
                  Expanded(child: _options()),
                  AnimatedOpacity(
                    opacity: _phase == _Phase.listening ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.07,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          s.yourTurn,
                          style: _text.copyWith(fontSize: 28),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _controls(s),
                  const SizedBox(height: 24),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// "What starts like Maus?" with the picture of the mouse (a tap says
  /// it). Shrinks on a low screen (landscape, large text).
  Widget _likeHeader(Phrase like) {
    final height = MediaQuery.sizeOf(context).height;
    return LayoutBuilder(
      builder: (context, c) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.17),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: c.maxWidth - 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  key: const ValueKey('quiz-like'),
                  onTap: () => _sayOption(like),
                  child: EmojiImage(like.emoji, size: 56),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _lines.question(_q.ask),
                    textAlign: TextAlign.center,
                    style: _text.copyWith(fontSize: 28),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _options() {
    final result = _phase == _Phase.result;
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 16 * 4) / 3;
        final pic = math.min(w * 0.8, c.maxHeight * 0.45);
        // portrait with room: two and one below, much bigger than three
        // in a row (a third of the width)
        if (c.maxHeight > c.maxWidth * 1.1) {
          final w2 = (c.maxWidth - 16 * 3) / 2;
          final pic2 = math.min(w2 * 0.75, (c.maxHeight - 16) / 2 - 64);
          if (pic2 > pic) {
            return FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: c.maxWidth,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final o in _q.options)
                      _option(o, w2, pic2, result: result),
                  ],
                ),
              ),
            );
          }
        }
        // shrinks when there is no room (landscape, large text)
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: c.maxWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final o in _q.options) _option(o, w, pic, result: result),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _option(Phrase o, double width, double pic, {required bool result}) {
    final isAnswer = o == _q.answer;
    final color = !result
        ? const Color(0xFF2B2B6B)
        : isAnswer
        ? const Color(0xFF2E7D32)
        : o == _chosen
        ? const Color(0xFFB45309)
        : const Color(0xFF1D1D45);
    return AnimatedBuilder(
      animation: _bounce,
      builder: (_, child) {
        // at most into the 16 dp gap: big tiles (tablet) must not cover
        // their neighbours
        final up = result && isAnswer
            ? math.sin(_bounce.value * math.pi) * math.min(0.15, 16 / width)
            : 0.0;
        return Transform.scale(scale: 1 + up, child: child);
      },
      child: Opacity(
        opacity: result && !isAnswer && o != _chosen ? 0.5 : 1,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _sayOption(o),
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EmojiImage(o.emoji, size: pic),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          o.text,
                          style: _text.copyWith(fontSize: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(S s) {
    final listening = _phase == _Phase.listening;
    final busy = _phase == _Phase.speaking || _phase == _Phase.thinking;
    final level = listening ? (_listener.level * 8).clamp(0.0, 0.3) : 0.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        RoundButton(
          tooltip: s.listen,
          onTap: _phase == _Phase.ready ? _again : null,
          color: const Color(0xFF3D5AFE),
          child: const EmojiImage('🔊', size: 40),
        ),
        AnimatedScale(
          scale: 1 + level,
          duration: const Duration(milliseconds: 120),
          child: RoundButton(
            tooltip: listening ? s.yourTurn : s.speak,
            size: 110,
            onTap: busy ? null : _onMic,
            dimmed: busy ? false : null,
            color: listening
                ? const Color(0xFFFF5252)
                : busy
                ? const Color(0xFF3D5AFE)
                : const Color(0xFFFF9100),
            child: EmojiImage(busy ? '👂' : '🎤', size: 60),
          ),
        ),
        // also keeps the mic button centred
        if (_reportsOn)
          RoundButton(
            tooltip: s.quizReportSend,
            onTap:
                _tries.isNotEmpty &&
                    !_reportSending &&
                    !_reportSent &&
                    !_reportAsking
                ? _sendReport
                : null,
            color: const Color(0xFF6D4C41),
            child: _reportSending
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : const EmojiImage('🐞', size: 40),
          )
        else
          const SizedBox(width: 76),
      ],
    );
  }
}
