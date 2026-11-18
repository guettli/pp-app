// "Letter puzzle" (✏️): the picture, the phone says the word, and the child
// spells it by tapping letter tiles in order. Six words a round from the
// words the child already plays with, short ones first; later words get
// one or two extra tiles that are not in the word.
//
// A wrong tile shakes and stays; after two wrong tiles for the same place
// the right one glows. A word without a wrong tile is a star. Single
// letters are not spoken: device TTS says them badly in many languages.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../game/feedback.dart';
import '../game/game_io.dart';
import '../game/rocket_launch.dart';
import '../game/voice_effects.dart';
import '../quiz/quiz_rules.dart' show quizStars;
import '../ui/emoji_image.dart';
import '../ui/round_button.dart';
import '../ui/round_parts.dart';
import '../ui/strings.dart';
import 'spell_rules.dart';

class SpellScreen extends StatefulWidget {
  const SpellScreen({super.key, required this.app, this.round});

  final AppState app;

  /// The puzzles; a new random round if null (tests set it).
  final List<SpellPuzzle>? round;

  static const words = 6;

  /// Wrong tiles for one place before the right one glows.
  static const hintAfter = 2;

  @override
  State<SpellScreen> createState() => _SpellScreenState();
}

class _SpellScreenState extends State<SpellScreen> with WidgetsBindingObserver {
  late final Speaker _tts;
  late final SoundOut _sfx;
  late final math.Random _rng;
  late final List<SpellPuzzle> _round = widget.round ?? _makeRound();

  int _index = 0;

  /// Letters placed of the current word.
  int _placed = 0;

  /// Which tiles of the current word are used up.
  late List<bool> _used = _fresh();

  /// Wrong tiles for the current place, and for the whole word.
  int _missesHere = 0;
  int _misses = 0;

  /// The tile that was wrong just now (shakes), or null.
  int? _shaking;
  Timer? _shakeEnd;

  /// Per word: no wrong tile (true), with wrong tiles (false), not yet.
  late final List<bool?> _results = List.filled(_round.length, null);
  String? _lastPraise;

  /// Incremented to stop what runs (next word, pause, closing).
  int _flow = 0;
  bool _paused = false;
  bool _over = false;
  Timer? _onward;
  Timer? _donePraise;

  String get _lang => widget.app.book.lang;
  SpellPuzzle get _p => _round[_index];
  bool get _done => _round.isNotEmpty && _placed == _p.letters.length;

  List<bool> _fresh() =>
      _round.isEmpty ? [] : List.filled(_round[_index].tiles.length, false);

  List<SpellPuzzle> _makeRound() {
    final app = widget.app;
    final alphabet = alphabetOf(app.book.phrases);
    final round = makeSpellRound(
      app.knownWords(),
      alphabet,
      _rng,
      count: SpellScreen.words,
    );
    if (round.length >= SpellScreen.words) return round;
    return makeSpellRound(
      app.book.phrases,
      alphabet,
      _rng,
      count: SpellScreen.words,
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _sayWord());
  }

  @override
  void dispose() {
    _flow++;
    WidgetsBinding.instance.removeObserver(this);
    _onward?.cancel();
    _donePraise?.cancel();
    _shakeEnd?.cancel();
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
      _paused = false;
      // back in the middle of a word: the word again; after it ➡ goes on
      if (!_done && !_over) _sayWord();
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

  /// The picture or 🔊: the word (again). Does not stop what runs: after
  /// the last letter the game still goes on by itself.
  Future<void> _sayWord() async {
    // not during the praise of a finished word: it would cut it off
    if (_over || !mounted || _round.isEmpty || _paused || _done) return;
    await _say(_p.phrase.text);
  }

  void _tap(int tile) {
    if (_over || _done || _used[tile] || _round.isEmpty) return;
    final want = _p.letters[_placed];
    if (sameLetter(_p.tiles[tile], want)) {
      setState(() {
        _used[tile] = true;
        _placed++;
        _missesHere = 0;
        _shaking = null;
      });
      if (_done) {
        _wordDone();
      } else {
        unawaited(_sound(pling(_rng)));
      }
      return;
    }
    _shakeEnd?.cancel();
    setState(() {
      _missesHere++;
      _misses++;
      _shaking = tile;
    });
    unawaited(_sound(jingle(0, _rng)));
    _shakeEnd = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _shaking = null);
    });
  }

  /// The tile that glows as a hint (after [SpellScreen.hintAfter] wrong
  /// tiles for this place), or null.
  int? get _hint {
    if (_done || _missesHere < SpellScreen.hintAfter) return null;
    final want = _p.letters[_placed];
    for (final (i, t) in _p.tiles.indexed) {
      if (!_used[i] && sameLetter(t, want)) return i;
    }
    return null;
  }

  Future<void> _wordDone() async {
    final id = ++_flow;
    final perfect = _misses == 0;
    setState(() => _results[_index] = perfect);
    unawaited(_sound(jingle(perfect ? 3 : 2, _rng)));
    final praise = pickPraise(_lang, perfect ? 3 : 2, _rng, avoid: _lastPraise);
    _lastPraise = praise;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!_current(id)) return;
    await _say('${_p.phrase.text}! $praise');
    if (!_current(id)) return;
    _onward = Timer(const Duration(milliseconds: 800), _next);
  }

  void _next() {
    _onward?.cancel();
    if (!mounted || _over || !_done) return;
    // ➡ during the praise: it stops at once
    _flow++;
    _quietly(_tts.stop);
    if (_index + 1 >= _round.length) {
      _finish();
      return;
    }
    _shakeEnd?.cancel();
    setState(() {
      _index++;
      _placed = 0;
      _used = _fresh();
      _missesHere = 0;
      _misses = 0;
      _shaking = null;
    });
    _sayWord();
  }

  Future<void> _finish() async {
    _over = true;
    _flow++;
    final right = _results.where((r) => r == true).length;
    final stars = quizStars(right, _round.length);
    var record = false;
    try {
      record = await widget.app.progress.recordSpell(_lang, stars);
    } catch (e, st) {
      debugPrint('saving the spell record failed: $e\n$st');
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
        title: Text(s.spellTitle),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: Starfield()),
            if (_round.isEmpty)
              Center(child: Text(s.tryAgain, style: _text))
            else
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth > c.maxHeight;
                  final picture = _picture(
                    math.min(c.maxHeight * (wide ? 0.45 : 0.25), 160),
                  );
                  final puzzle = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _slots(c.maxWidth * (wide ? 0.55 : 1)),
                      const SizedBox(height: 20),
                      _tiles(c.maxWidth * (wide ? 0.55 : 1)),
                    ],
                  );
                  return Column(
                    children: [
                      ProgressDots(results: _results, index: _index),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: wide
                              ? Row(
                                  children: [
                                    picture,
                                    const SizedBox(width: 24),
                                    puzzle,
                                  ],
                                )
                              : Column(
                                  children: [
                                    picture,
                                    const SizedBox(height: 24),
                                    puzzle,
                                  ],
                                ),
                        ),
                      ),
                      _controls(s),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _picture(double size) => GestureDetector(
    key: const ValueKey('spell-picture'),
    onTap: _done ? null : _sayWord,
    child: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: EmojiImage(_p.phrase.emoji, size: size),
    ),
  );

  /// The word so far: placed letters, empty boxes for the rest.
  Widget _slots(double width) {
    final n = _p.letters.length;
    final box = math.min(52.0, (width - 32) / n - 6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < n; i++)
          Container(
            width: box,
            height: box * 1.2,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: i < _placed
                  ? (_done ? const Color(0xFF2E7D32) : const Color(0xFF2B2B6B))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: i == _placed ? Colors.white : Colors.white38,
                width: i == _placed ? 3 : 2,
              ),
            ),
            child: i < _placed
                ? FittedBox(
                    child: Text(
                      _p.letters[i],
                      style: _text.copyWith(fontSize: box * 0.7),
                    ),
                  )
                : null,
          ),
      ],
    );
  }

  /// The tiles to tap; used ones stay as faint gaps, so nothing moves.
  Widget _tiles(double width) {
    final hint = _hint;
    final size = math.min(64.0, (width - 32) / 5 - 10);
    return SizedBox(
      width: math.max(width - 32, size),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final (i, t) in _p.tiles.indexed)
            _tile(i, t, size, glow: i == hint),
        ],
      ),
    );
  }

  Widget _tile(int i, String letter, double size, {required bool glow}) {
    final used = _used[i];
    final wrong = _shaking == i;
    return TweenAnimationBuilder<double>(
      key: ValueKey('spell-tile-$i-${wrong ? _misses : 0}'),
      tween: Tween(begin: wrong ? 1 : 0, end: 0),
      duration: const Duration(milliseconds: 400),
      builder: (_, v, child) => Transform.translate(
        offset: Offset(math.sin(v * math.pi * 6) * 8 * v, 0),
        child: child,
      ),
      child: Opacity(
        opacity: used ? 0.15 : 1,
        child: Material(
          key: ValueKey('spell-tile-$i'),
          color: wrong
              ? const Color(0xFFB45309)
              : glow
              ? const Color(0xFFF59E0B)
              : const Color(0xFF3B2B7B),
          borderRadius: BorderRadius.circular(14),
          elevation: used ? 0 : 6,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: used ? null : () => _tap(i),
            child: SizedBox.square(
              dimension: size,
              child: Center(
                child: FittedBox(
                  child: Text(
                    // tiles in small letters; the word above as written
                    letter.toLowerCase(),
                    style: _text.copyWith(fontSize: size * 0.6),
                  ),
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
        onTap: _done ? null : _sayWord,
        child: const EmojiImage('🔊', size: 40),
      ),
      RoundButton(
        tooltip: s.next,
        color: const Color(0xFF00C853),
        onTap: _done && !_over ? _next : null,
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
