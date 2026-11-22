// The memory games: the child remembers a few pictures (or words) for a
// moment and finds them again.
//
// "Remember the pictures" (👀, [MemoryGame.look]): a few pictures, then
// they hide (🙈, five seconds), then the child taps them among six.
//
// "Remember the words" (🧠, [MemoryGame.hear]): the phone says a few
// words, no pictures; after a short wait the child taps their pictures
// among six.
//
// "What's missing?" (❓, [MemoryGame.missing]): a few pictures, they
// hide, they come back with a gap; the child taps the one that is gone
// among three.
//
// A right tap says the word; a wrong one too, with a low sound. After
// two wrong taps the right pictures are shown and the round goes on.
// Only a question solved without a wrong tap counts for the stars. No
// microphone.
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
import '../quiz/quiz_rules.dart' show quizStars;
import '../ui/emoji_image.dart';
import '../ui/intros.dart';
import '../ui/round_button.dart';
import '../ui/round_parts.dart';
import '../ui/strings.dart';
import 'memory_rules.dart';

enum _Phase {
  /// The intro or the short cue before a question.
  speaking,

  /// The pictures are there to look at.
  show,

  /// The words are being said.
  hearing,

  /// Nothing to see: remember!
  hide,

  /// Tap the pictures.
  pick,

  /// The question is done.
  result,
}

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({
    super.key,
    required this.app,
    required this.game,
    this.round,
    this.intro = true,
  });

  final AppState app;
  final MemoryGame game;

  /// The questions; a new random round if null (tests set it).
  final List<MemoryQuestion>? round;

  /// Say what to do before the first question (off in tests of the flow).
  final bool intro;

  /// How long the pictures hide (and after the words, how long to wait).
  static const hideSeconds = 5;

  /// How long [n] pictures are shown.
  static Duration showTime(int n) => Duration(milliseconds: 1500 + 1000 * n);

  /// Wrong taps before the right pictures are shown.
  static const maxWrong = 2;

  /// The key of the best round in [Progress.thinkBest].
  static String progressKey(MemoryGame game) => 'memory-${game.name}';

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen>
    with WidgetsBindingObserver {
  late final Speaker _tts;
  late final SoundOut _sfx;
  late final math.Random _rng;
  late final MemoryLines _lines = MemoryLines.of(_lang);
  late final List<MemoryQuestion> _round = widget.round ?? _makeRound();

  _Phase _phase = _Phase.speaking;
  int _index = 0;

  /// Per question: solved without a wrong tap (true), not (false), not yet.
  late final List<bool?> _results = List.filled(_round.length, null);

  /// Pictures of the current question tapped rightly / wrongly.
  final _found = <Phrase>{};
  final _wrong = <Phrase>{};

  /// "Remember the words": how many words were said (or are being).
  int _heard = 0;

  /// Seconds left while the pictures hide.
  int _hideLeft = 0;

  late bool _introDone = !widget.intro;
  String? _lastPraise;

  /// Incremented to stop what runs (new question, pause, closing).
  int _flow = 0;
  bool _paused = false;
  bool _over = false;
  Timer? _onward;
  Timer? _donePraise;

  String get _lang => widget.app.book.lang;
  MemoryQuestion get _q => _round[_index];
  bool get _hear => widget.game == MemoryGame.hear;
  bool get _missing => widget.game == MemoryGame.missing;

  String get _which => switch (widget.game) {
    MemoryGame.look => _lines.whichSeen,
    MemoryGame.hear => _lines.whichHeard,
    MemoryGame.missing => _lines.whichMissing,
  };

  List<MemoryQuestion> _makeRound() {
    final app = widget.app;
    final round = makeMemoryRound(widget.game, app.knownWords(), _rng);
    if (round.length == memorySizes[widget.game]!.length) return round;
    return makeMemoryRound(widget.game, app.book.phrases, _rng);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final io = widget.app.io;
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
    _quietly(_tts.stop);
    _quietly(_sfx.dispose);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _paused = true;
      _flow++;
      _onward?.cancel();
      _donePraise?.cancel();
      _quietly(_tts.stop);
      _quietly(_sfx.stop);
    } else if (state == AppLifecycleState.resumed) {
      if (!_paused) return;
      _paused = false;
      if (_over || !mounted) return;
      switch (_phase) {
        // cut off while looking or remembering: the question once more
        case _Phase.speaking || _Phase.show || _Phase.hearing || _Phase.hide:
          _ask();
        case _Phase.pick:
          _repeat();
        case _Phase.result:
          _onward = Timer(const Duration(milliseconds: 900), _next);
      }
    }
  }

  bool _current(int id) => mounted && id == _flow && !_paused;

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
    if (_paused) return;
    await _quietly(() async {
      await _sfx.stop();
      await _sfx.play(wavBytes(s));
    });
  }

  Future<bool> _wait(int id, Duration d) async {
    await Future<void>.delayed(d);
    return _current(id);
  }

  /// The current question from the start: (intro or cue,) show or say,
  /// hide, then the pictures to tap.
  Future<void> _ask() async {
    if (_over || !mounted || _round.isEmpty) return;
    final id = ++_flow;
    _onward?.cancel();
    setState(() {
      _phase = _Phase.speaking;
      _found.clear();
      _wrong.clear();
      _heard = 0;
    });
    if (!_introDone) {
      _introDone = true;
      await _say(
        introLine(switch (widget.game) {
          MemoryGame.look => GameIntro.memoryLook,
          MemoryGame.hear => GameIntro.memoryHear,
          MemoryGame.missing => GameIntro.memoryMissing,
        }, _lang),
      );
    } else {
      await _say(_hear ? _lines.listen : _lines.look);
    }
    if (!await _wait(id, const Duration(milliseconds: 300))) return;
    if (_hear) {
      setState(() => _phase = _Phase.hearing);
      for (final (i, p) in _q.shown.indexed) {
        setState(() => _heard = i + 1);
        await _say(p.text);
        if (!await _wait(id, const Duration(milliseconds: 700))) return;
      }
    } else {
      setState(() => _phase = _Phase.show);
      if (!await _wait(id, MemoryScreen.showTime(_q.shown.length))) return;
    }
    for (var left = MemoryScreen.hideSeconds; left > 0; left--) {
      setState(() {
        _phase = _Phase.hide;
        _hideLeft = left;
      });
      if (!await _wait(id, const Duration(seconds: 1))) return;
    }
    setState(() => _phase = _Phase.pick);
    await _say(_which);
  }

  /// 🔊: the question once more (only while tapping).
  Future<void> _repeat() async {
    if (_phase != _Phase.pick || _over) return;
    ++_flow;
    await _say(_which);
  }

  Future<void> _tap(Phrase p) async {
    if (_phase != _Phase.pick || _over) return;
    if (_found.contains(p) || _wrong.contains(p)) return;
    final id = ++_flow;
    final answers = _q.answers;
    if (answers.contains(p)) {
      setState(() => _found.add(p));
      if (_found.length == answers.length) {
        await _done(id, p);
        return;
      }
      unawaited(_sound(jingle(2, _rng)));
      await _say(p.text);
      return;
    }
    setState(() => _wrong.add(p));
    unawaited(_sound(jingle(0, _rng)));
    if (_wrong.length >= MemoryScreen.maxWrong) {
      await _done(id, null);
      return;
    }
    if (!await _wait(id, const Duration(milliseconds: 400))) return;
    await _say(p.text);
  }

  /// The question is over: [last] the tap that found the last picture, or
  /// null when the child gave up after too many wrong taps.
  Future<void> _done(int id, Phrase? last) async {
    final first = _wrong.isEmpty;
    setState(() {
      _phase = _Phase.result;
      _results[_index] = last != null && first;
    });
    if (last != null) {
      unawaited(_sound(jingle(first ? 3 : 2, _rng)));
    }
    if (!await _wait(id, const Duration(milliseconds: 500))) return;
    if (last != null) {
      // right after a wrong tap: still right, a "well done" (not "almost")
      final praise = pickPraise(_lang, first ? 3 : 2, _rng, avoid: _lastPraise);
      _lastPraise = praise;
      await _say('${last.text}! $praise');
    } else {
      // these were the ones: their words, while they light up
      final missed = [
        for (final a in _q.answers)
          if (!_found.contains(a)) a.text,
      ];
      await _say('${missed.join(', ')}.');
    }
    if (!_current(id)) return;
    _onward = Timer(const Duration(milliseconds: 900), _next);
  }

  void _next() {
    _onward?.cancel();
    if (!mounted || _over || _phase != _Phase.result) return;
    _flow++;
    _quietly(_tts.stop);
    if (_index + 1 >= _round.length) {
      _finish();
      return;
    }
    setState(() => _index++);
    _ask();
  }

  Future<void> _finish() async {
    _over = true;
    _flow++;
    final right = _results.where((r) => r == true).length;
    final stars = quizStars(right, _round.length);
    var record = false;
    try {
      record = await widget.app.progress.recordThink(
        MemoryScreen.progressKey(widget.game),
        _lang,
        stars,
      );
    } catch (e, st) {
      debugPrint('saving the memory record failed: $e\n$st');
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
      right: right,
      total: _round.length,
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
        title: Text(switch (widget.game) {
          MemoryGame.look => s.lookTitle,
          MemoryGame.hear => s.hearWordsTitle,
          MemoryGame.missing => s.missingTitle,
        }),
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
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _stage(),
                    ),
                  ),
                  _controls(s),
                  const SizedBox(height: 24),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _stage() => switch (_phase) {
    _Phase.speaking => _big(_hear ? '👂' : '👀', key: 'memory-wait'),
    _Phase.show => _grid([
      for (final (i, p) in _q.shown.indexed)
        _picture(p.emoji, key: 'memory-shown-$i'),
    ]),
    _Phase.hearing => _big(
      '👂',
      key: 'memory-hearing',
      dots: _q.shown.length,
      lit: _heard,
    ),
    _Phase.hide => _big(
      '🙈',
      key: 'memory-hide',
      dots: MemoryScreen.hideSeconds,
      lit: _hideLeft,
    ),
    _Phase.pick || _Phase.result =>
      _missing
          ? Column(
              children: [
                Expanded(flex: 2, child: _gapRow()),
                Expanded(flex: 3, child: _options()),
              ],
            )
          : _options(),
  };

  /// One big picture, with a row of dots under it ([lit] of [dots] full).
  Widget _big(String emoji, {required String key, int dots = 0, int lit = 0}) =>
      LayoutBuilder(
        builder: (context, c) {
          final size = math.max(
            40.0,
            math.min(160.0, math.min(c.maxWidth, c.maxHeight) - 60),
          );
          return Center(
            child: Column(
              key: ValueKey(key),
              mainAxisSize: MainAxisSize.min,
              children: [
                EmojiImage(emoji, size: size),
                if (dots > 0) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < dots; i++)
                        Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < lit
                                ? const Color(0xFFFFD54F)
                                : Colors.white24,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      );

  /// "What's missing?": the pictures again, ❓ where one is gone (after
  /// the answer, the one that was gone).
  /// The gap row sits in its own light panel: it is to look at, the
  /// pictures below are to tap.
  Widget _gapRow() => Container(
    key: const ValueKey('memory-gap-panel'),
    margin: const EdgeInsets.symmetric(horizontal: 12),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(28),
    ),
    child: _grid([
      for (final (i, p) in _q.shown.indexed)
        if (p == _q.missing)
          _picture(
            _phase == _Phase.result ? p.emoji : '❓',
            key: 'memory-gap',
            color: _phase == _Phase.result
                ? const Color(0xFF2E7D32)
                : const Color(0xFFF59E0B),
          )
        else
          _picture(p.emoji, key: 'memory-left-$i'),
    ]),
  );

  Widget _options() =>
      _grid([for (final (i, o) in _q.options.indexed) _option(o, i)]);

  Widget _option(Phrase o, int i) {
    final result = _phase == _Phase.result;
    final isAnswer = _q.answers.contains(o);
    final found = _found.contains(o);
    final wrong = _wrong.contains(o);
    // after the answer: the found ones green, those not found framed
    final shown = result && isAnswer && !found;
    final color = found
        ? const Color(0xFF2E7D32)
        : wrong
        ? const Color(0xFFB45309)
        : null;
    return Opacity(
      opacity: wrong || (result && !isAnswer) ? 0.45 : 1,
      child: _picture(
        o.emoji,
        key: 'memory-option-$i',
        color: color,
        frame: shown ? const Color(0xFF4ADE80) : null,
        onTap: () => _tap(o),
      ),
    );
  }

  Widget _picture(
    String emoji, {
    required String key,
    Color? color,
    Color? frame,
    VoidCallback? onTap,
  }) => Material(
    key: ValueKey(key),
    color: color ?? const Color(0xFF2B2B6B),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: frame == null
          ? BorderSide.none
          : BorderSide(color: frame, width: 6),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: FittedBox(child: EmojiImage(emoji, size: 160)),
      ),
    ),
  );

  /// [cells] as big as they fit, in rows of equal length (the last may be
  /// shorter).
  Widget _grid(List<Widget> cells) => LayoutBuilder(
    builder: (context, c) {
      const gap = 12.0;
      final n = cells.length;
      var perRow = 1;
      var cell = 0.0;
      for (var per = 1; per <= n; per++) {
        final rows = (n / per).ceil();
        final size = math.min(
          (c.maxWidth - gap * (per + 1)) / per,
          (c.maxHeight - gap * (rows - 1)) / rows,
        );
        if (size > cell) {
          cell = size;
          perRow = per;
        }
      }
      cell = math.max(math.min(cell, 220), 40);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < n; r += perRow) ...[
              if (r > 0) const SizedBox(height: gap),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = r; i < math.min(r + perRow, n); i++) ...[
                    if (i > r) const SizedBox(width: gap),
                    SizedBox.square(dimension: cell, child: cells[i]),
                  ],
                ],
              ),
            ],
          ],
        ),
      );
    },
  );

  Widget _controls(S s) {
    final result = _phase == _Phase.result;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        RoundButton(
          key: const ValueKey('memory-repeat'),
          tooltip: s.listen,
          color: const Color(0xFF3B82F6),
          onTap: _phase == _Phase.pick ? _repeat : null,
          dimmed: _phase != _Phase.pick,
          child: const EmojiImage('🔊', size: 40),
        ),
        RoundButton(
          tooltip: s.next,
          color: const Color(0xFF00C853),
          onTap: result && !_over ? _next : null,
          child: const Icon(
            Icons.arrow_forward_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
      ],
    );
  }

  static const _text = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w800,
    shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
  );
}
