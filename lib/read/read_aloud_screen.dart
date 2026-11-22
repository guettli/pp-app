// "Read aloud" (📖🎤): a word is written, nothing is said and no picture is
// shown; the child reads it aloud. The phone listens by itself, scores it
// like the word game, then shows the picture and says the word, so the
// child hears how it sounds. Six words a round from the words the child
// already plays with, short ones first.
//
// 0 stars: once more (the child has heard the word now). The stars of a
// round are the average of its words. ➡ also skips a word the child
// cannot read (0 stars).
//
// The microphone opens with the word, and the child gets
// [ReadAloudScreen.noSpeech] to start: reading takes a moment.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/phrases.dart';
import '../game/feedback.dart';
import '../game/game_io.dart';
import '../game/rocket_launch.dart';
import '../game/rules.dart';
import '../game/voice_effects.dart';
import '../net/quiz_report.dart';
import '../quiz/quiz_rules.dart' show optionScores;
import '../quiz/word_listener.dart';
import '../ui/recording_report.dart';
import '../ui/emoji_image.dart';
import '../ui/intros.dart';
import '../ui/round_button.dart';
import '../ui/round_parts.dart';
import '../ui/strings.dart';

enum _Phase { ready, speaking, listening, thinking, result }

/// Up to [count] words from [pool] to read: at most [maxChars] letters,
/// short ones first.
List<Phrase> makeReadRound(
  List<Phrase> pool,
  math.Random rng, {
  int count = 6,
  int maxChars = 12,
}) {
  final words = [
    for (final p in pool)
      if (p.text.runes.length <= maxChars) p,
  ]..shuffle(rng);
  return words.take(count).toList()
    ..sort((a, b) => a.text.runes.length.compareTo(b.text.runes.length));
}

/// The stars of a round: the average of its words, rounded.
int readRoundStars(List<int> stars) => stars.isEmpty
    ? 0
    : (stars.reduce((a, b) => a + b) / stars.length).round().clamp(0, 3);

class ReadAloudScreen extends StatefulWidget {
  const ReadAloudScreen({
    super.key,
    required this.app,
    this.round,
    this.intro = true,
  });

  /// Say what to do before the first word (off in tests of the flow).
  final bool intro;

  final AppState app;

  /// The words; a new random round if null (tests set it).
  final List<Phrase>? round;

  static const words = 6;

  /// Time to start reading before the try ends as "not heard".
  static const noSpeech = Duration(seconds: 12);

  @override
  State<ReadAloudScreen> createState() => _ReadAloudScreenState();
}

class _ReadAloudScreenState extends State<ReadAloudScreen>
    with WidgetsBindingObserver {
  late final WordListener _listener;
  late final Speaker _tts;
  late final SoundOut _sfx;
  late final math.Random _rng;
  late final List<Phrase> _round = widget.round ?? _makeRound();

  _Phase _phase = _Phase.ready;
  int _index = 0;

  /// Tries of the current word.
  int _attempts = 0;

  /// Best stars per word so far (null: not read yet).
  late final List<int?> _stars = List.filled(_round.length, null);

  /// The intro (what to do) was said: once, before the first word.
  late bool _introDone = !widget.intro;

  /// Stars of the last try of the current word (shown in the result).
  int _last = 0;
  String? _lastPraise;

  /// Incremented to stop what runs (next word, pause, closing).
  int _flow = 0;
  bool _paused = false;
  bool _over = false;
  Timer? _onward;
  Timer? _donePraise;

  String get _lang => widget.app.book.lang;
  Phrase get _p => _round[_index];

  /// 🐞: the last tries of the word, with what was heard.
  late final RecordingReports _reports = RecordingReports(widget.app);

  void _keepTry(Heard heard, String ipa, int? stars) {
    if (!_reports.on) return;
    _reports.keep(
      _p,
      QuizTry(
        pcm: heard.pcm,
        speech: heard.speech,
        heard: ipa,
        said: stars == null ? '' : '$stars',
        scores: optionScores(widget.app.comparer, [_p], ipa, _lang),
      ),
    );
    setState(() {});
  }

  bool get _idle => _phase == _Phase.ready || _phase == _Phase.result;
  bool _current(int id) => mounted && id == _flow && !_paused;

  /// Known words; filled up from the rest of the book if too few.
  List<Phrase> _makeRound() {
    final known = widget.app.knownWords();
    final round = makeReadRound(known, _rng, count: ReadAloudScreen.words);
    if (round.length >= ReadAloudScreen.words) return round;
    final more = makeReadRound(
      [
        for (final p in widget.app.book.phrases)
          if (!known.contains(p)) p,
      ],
      _rng,
      count: ReadAloudScreen.words - round.length,
    );
    return [...round, ...more]
      ..sort((a, b) => a.text.runes.length.compareTo(b.text.runes.length));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final io = widget.app.io;
    _listener = WordListener(io.mic(), noSpeech: ReadAloudScreen.noSpeech);
    _tts = io.speaker();
    _sfx = io.soundPlayer();
    _rng = io.random();
    _tts.setLanguage(_lang);
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
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
    _reports.dispose();
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
      _reports.stopReplay();
      if (!_idle && mounted) setState(() => _phase = _Phase.ready);
    } else if (state == AppLifecycleState.resumed) {
      _paused = false; // goes on with a tap on 🎤 (or ➡)
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
    if (_paused || _listener.listening) return;
    await _quietly(() async {
      await _sfx.stop();
      await _sfx.play(wavBytes(s));
    });
  }

  /// Listens to the child reading the current word, then scores it.
  Future<void> _listen() async {
    if (!_idle || _over || !mounted || _round.isEmpty) return;
    final id = ++_flow;
    _onward?.cancel();
    // nothing of the phone may be in the recording
    await _quietly(_tts.stop);
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
    // paused or closed meanwhile: the mic must not open
    if (!_current(id)) return;
    if (!_introDone) {
      // busy: 🎤 and ➡ wait until it is said
      setState(() => _phase = _Phase.speaking);
      await _say(introLine(GameIntro.readAloud, _lang));
      // let the speaker's echo fade before the mic opens
      await Future<void>.delayed(const Duration(milliseconds: 250));
      // cut off (paused): said again with the next try
      if (!_current(id)) return;
      _introDone = true;
      await _quietly(_tts.stop);
      if (!_current(id)) return;
    }
    setState(() => _phase = _Phase.listening);
    final heard = await _listener.listen(
      // reading takes a moment before the first sound
      limit: ReadAloudScreen.noSpeech + recordingLimit(_p.text),
      onChunk: () {
        if (mounted) setState(() {});
      },
    );
    if (!_current(id)) return;
    if (heard == null) {
      _fail(id, (s) => s.tryAgain);
      return;
    }
    if (!heard.speech) {
      _keepTry(heard, '', null);
      _fail(id, (s) => s.notHeardVoice);
      return;
    }
    setState(() => _phase = _Phase.thinking);
    int stars;
    var ipa = '';
    try {
      final rec = await widget.app.recognizer
          .recognize(heard.audio)
          .timeout(const Duration(seconds: 20));
      ipa = rec.ipa;
      stars = scorePhrase(widget.app.comparer, _p, ipa, _lang).stars;
      debugPrint('read aloud: heard "$ipa" -> $stars');
    } catch (e, st) {
      debugPrint('recognition failed: $e\n$st');
      _fail(id, (s) => s.tryAgain);
      return;
    }
    if (!_current(id)) return;
    _keepTry(heard, ipa, stars);
    await _scored(id, stars);
  }

  void _fail(int id, String Function(S) message) {
    if (!mounted || id != _flow) return;
    setState(() => _phase = _Phase.ready);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message(S.of(context)))));
  }

  Future<void> _scored(int id, int stars) async {
    _attempts++;
    setState(() {
      _phase = _Phase.result;
      _last = stars;
      _stars[_index] = math.max(_stars[_index] ?? 0, stars);
    });
    unawaited(_sound(jingle(stars, _rng)));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!_current(id)) return;
    final retry = afterResult(stars, _attempts) == AfterResult.retry;
    final praise = pickPraise(
      _lang,
      stars,
      _rng,
      avoid: _lastPraise,
      onward: !retry,
    );
    _lastPraise = praise;
    // the word as it sounds: the child can compare
    await _say('${_p.text}! $praise');
    if (!_current(id)) return;
    if (retry) {
      // once more, now that the child has heard it
      setState(() => _phase = _Phase.ready);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (_current(id)) unawaited(_listen());
      return;
    }
    _onward = Timer(const Duration(milliseconds: 900), () {
      if (_current(id) && _phase == _Phase.result) _next();
    });
  }

  /// ➡: the next word (also one the child could not read: 0 stars).
  void _next() {
    _onward?.cancel();
    if (!mounted || _over || !_idle) return;
    // ➡ during the praise: it stops at once
    _flow++;
    _quietly(_tts.stop);
    if (_index + 1 >= _round.length) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _attempts = 0;
      _last = 0;
      _phase = _Phase.ready;
    });
    _listen();
  }

  /// 🎤: listening -> done; ready -> listen now; result -> once more.
  void _onMic() {
    switch (_phase) {
      case _Phase.listening:
        _listener.stopNow();
      case _Phase.ready:
        _listen();
      case _Phase.result:
        _flow++;
        _onward?.cancel();
        _quietly(_tts.stop);
        setState(() => _phase = _Phase.ready);
        _listen();
      case _Phase.thinking || _Phase.speaking:
        break;
    }
  }

  Future<void> _finish() async {
    _over = true;
    _flow++;
    final all = [for (final s in _stars) s ?? 0];
    final stars = readRoundStars(all);
    var record = false;
    try {
      record = await widget.app.progress.recordReadAloud(_lang, stars);
    } catch (e, st) {
      debugPrint('saving the read-aloud record failed: $e\n$st');
    }
    if (!mounted) return;
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
      right: all.reduce((a, b) => a + b),
      total: all.length * 3,
      record: record,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF14143A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(s.readAloudTitle),
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
                  ProgressDots(
                    results: [
                      for (final st in _stars) st == null ? null : st >= 1,
                    ],
                    index: _index,
                  ),
                  Expanded(child: _middle()),
                  AnimatedOpacity(
                    opacity: _phase == _Phase.listening ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      s.yourTurn,
                      style: _text.copyWith(fontSize: 26),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _controls(s),
                  const SizedBox(height: 16),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// The word; with the result also its picture and the stars (until
  /// then the word has all the room).
  Widget _middle() {
    final result = _phase == _Phase.result;
    final word = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        _p.text,
        key: const ValueKey('read-word'),
        style: _text.copyWith(fontSize: 64),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          if (result)
            Expanded(
              flex: 3,
              child: FittedBox(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EmojiImage(_p.emoji, size: 160),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Opacity(
                            opacity: i < _last ? 1 : 0.2,
                            child: const EmojiImage('⭐', size: 44),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Expanded(flex: 2, child: Center(child: word)),
        ],
      ),
    );
  }

  Widget _controls(S s) {
    final listening = _phase == _Phase.listening;
    final busy = _phase == _Phase.thinking || _phase == _Phase.speaking;
    final level = listening ? (_listener.level * 8).clamp(0.0, 0.3) : 0.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (_reports.on)
          _reports.button(s, _sendReport)
        else
          // keeps the mic button centred
          const SizedBox(width: 76),
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
        RoundButton(
          tooltip: s.next,
          color: const Color(0xFF00C853),
          onTap: _idle && !_over ? _next : null,
          child: const Icon(
            Icons.arrow_forward_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
      ],
    );
  }

  /// 🐞: stops what runs (the mic first), asks, sends the last tries.
  Future<void> _sendReport() => _reports.send(
    this,
    hold: () async {
      _flow++;
      _onward?.cancel();
      _donePraise?.cancel();
      await _listener.cancel();
      await _quietly(_tts.stop);
      await _quietly(_sfx.stop);
      if (mounted && !_idle) setState(() => _phase = _Phase.ready);
    },
    paused: () => _paused,
    update: () => setState(() {}),
    topic: (of) {
      final p = of as Phrase;
      return (
        question: 'read aloud: ${p.text}',
        asked: p.text,
        options: [
          (text: p.text, ipa: [for (final w in p.accepted) w.ipa]),
        ],
        answer: p.text,
      );
    },
  );

  static const _text = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w800,
    shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
  );
}
