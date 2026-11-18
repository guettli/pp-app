// "Listen closely" (👂): the phone says a word, the child taps its picture
// among four. Eight words a round from the words the child already plays
// with; later in the round one wrong picture sounds like the answer.
//
// A wrong tap is not a dead end: the phone says what the tapped picture
// is ("Haus") and the word again, and the child tries once more. Only
// the first tap counts for the stars. No microphone.
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
import '../ui/round_button.dart';
import '../ui/round_parts.dart';
import '../ui/strings.dart';
import 'listen_rules.dart';

enum _Phase { speaking, choosing, result }

class ListenScreen extends StatefulWidget {
  const ListenScreen({super.key, required this.app, this.round});

  final AppState app;

  /// The questions; a new random round if null (tests set it).
  final List<ListenQuestion>? round;

  static const questions = 8;

  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen>
    with WidgetsBindingObserver {
  late final Speaker _tts;
  late final SoundOut _sfx;
  late final math.Random _rng;
  late final List<ListenQuestion> _round = widget.round ?? _makeRound();

  _Phase _phase = _Phase.speaking;
  int _index = 0;

  /// Per question: right at the first tap (true), not (false), not yet.
  late final List<bool?> _results = List.filled(_round.length, null);

  /// Pictures of the current question tapped wrongly.
  final _wrong = <Phrase>{};
  String? _lastPraise;

  /// Incremented to stop what runs (new question, pause, closing).
  int _flow = 0;
  bool _paused = false;
  bool _over = false;
  Timer? _onward;
  Timer? _donePraise;

  String get _lang => widget.app.book.lang;
  ListenQuestion get _q => _round[_index];

  List<ListenQuestion> _makeRound() {
    final app = widget.app;
    double closeness(Phrase a, Phrase b) =>
        app.comparer.compare(a.ipa, b.ipa, app.book.lang).score;
    final round = makeListenRound(
      app.knownWords(),
      _rng,
      closeness: closeness,
      count: ListenScreen.questions,
    );
    if (round.length >= ListenScreen.questions) return round;
    return makeListenRound(
      app.book.phrases,
      _rng,
      closeness: closeness,
      count: ListenScreen.questions,
    );
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
      // a word cut off: the pictures stay tappable, 🔊 says it again
      if (_phase == _Phase.speaking && mounted) {
        setState(() => _phase = _Phase.choosing);
      }
    } else if (state == AppLifecycleState.resumed) {
      _paused = false; // goes on with a tap (➡ after a result)
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

  /// Says the word of the current question; the pictures can be tapped
  /// already while it is said.
  Future<void> _ask() async {
    if (_over || !mounted || _round.isEmpty) return;
    final id = ++_flow;
    _onward?.cancel();
    setState(() => _phase = _Phase.speaking);
    await _say(_q.answer.text);
    if (_current(id) && _phase == _Phase.speaking) {
      setState(() => _phase = _Phase.choosing);
    }
  }

  /// 🔊: the word again.
  Future<void> _repeat() async {
    if (_phase == _Phase.result || _over) return;
    final id = ++_flow;
    setState(() => _phase = _Phase.speaking);
    await _say(_q.answer.text);
    if (_current(id) && _phase == _Phase.speaking) {
      setState(() => _phase = _Phase.choosing);
    }
  }

  Future<void> _tap(Phrase p) async {
    if (_phase == _Phase.result || _over || _wrong.contains(p)) return;
    final id = ++_flow;
    if (p == _q.answer) {
      final first = _wrong.isEmpty;
      setState(() {
        _phase = _Phase.result;
        _results[_index] = first;
      });
      unawaited(_sound(jingle(first ? 3 : 1, _rng)));
      final praise = pickPraise(_lang, first ? 3 : 1, _rng, avoid: _lastPraise);
      _lastPraise = praise;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!_current(id)) return;
      await _say('${p.text}! $praise');
      if (!_current(id)) return;
      _onward = Timer(const Duration(milliseconds: 600), _next);
      return;
    }
    // wrong: what the child tapped, then the word once more
    setState(() {
      _wrong.add(p);
      _phase = _Phase.speaking;
    });
    unawaited(_sound(jingle(0, _rng)));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!_current(id)) return;
    await _say(p.text);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!_current(id)) return;
    await _say(_q.answer.text);
    if (_current(id) && _phase == _Phase.speaking) {
      setState(() => _phase = _Phase.choosing);
    }
  }

  void _next() {
    _onward?.cancel();
    if (!mounted || _over || _phase != _Phase.result) return;
    if (_index + 1 >= _round.length) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _wrong.clear();
    });
    _ask();
  }

  Future<void> _finish() async {
    _over = true;
    _flow++;
    final right = _results.where((r) => r == true).length;
    final stars = quizStars(right, _round.length);
    var record = false;
    try {
      record = await widget.app.progress.recordListen(_lang, stars);
    } catch (e, st) {
      debugPrint('saving the listen record failed: $e\n$st');
    }
    if (!mounted) return;
    final s = S.of(context);
    unawaited(_sound(fanfare(_rng)));
    var text = pickPraise(_lang, math.max(stars, 1), _rng, avoid: _lastPraise);
    if (record) text = '$text ${s.newRecord}';
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
        title: Text(s.listenTitle),
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
                  Expanded(child: _options()),
                  _controls(s),
                  const SizedBox(height: 24),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// The pictures, 2 x 2 (a row of four when wide).
  Widget _options() => LayoutBuilder(
    builder: (context, c) {
      final wide = c.maxWidth > c.maxHeight * 1.6;
      final perRow = wide ? 4 : 2;
      final rows = (_q.options.length / perRow).ceil();
      final cell = math.min(
        (c.maxWidth - 16 * (perRow + 1)) / perRow,
        (c.maxHeight - 16 * (rows + 1)) / rows,
      );
      return Center(
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: [
            for (final (i, o) in _q.options.indexed)
              SizedBox.square(
                dimension: math.max(cell, 40),
                child: _option(o, i),
              ),
          ],
        ),
      );
    },
  );

  Widget _option(Phrase o, int i) {
    final result = _phase == _Phase.result;
    final isAnswer = o == _q.answer;
    final wrong = _wrong.contains(o);
    final color = result && isAnswer
        ? const Color(0xFF2E7D32)
        : wrong
        ? const Color(0xFFB45309)
        : const Color(0xFF2B2B6B);
    return Opacity(
      opacity: wrong || (result && !isAnswer) ? 0.45 : 1,
      child: Material(
        key: ValueKey('listen-option-$i'),
        color: color,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _tap(o),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (_, c) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EmojiImage(
                      o.emoji,
                      size: c.maxHeight * (result ? 0.6 : 0.8),
                    ),
                    // the word is shown with the answer, not before:
                    // this is a game for the ears
                    if (result && isAnswer)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          o.text,
                          style: _text.copyWith(fontSize: 24),
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

  Widget _controls(S s) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      RoundButton(
        tooltip: s.listen,
        color: const Color(0xFF3B82F6),
        onTap: _phase == _Phase.result ? null : _repeat,
        dimmed: _phase == _Phase.result,
        child: const EmojiImage('🔊', size: 40),
      ),
      RoundButton(
        tooltip: s.next,
        color: const Color(0xFF00C853),
        onTap: _phase == _Phase.result && !_over ? _next : null,
        child: const Icon(
          Icons.arrow_forward_rounded,
          color: Colors.white,
          size: 40,
        ),
      ),
    ],
  );

  static const _text = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w800,
    shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
  );
}
