// One "world" = 8 phrases. For each phrase the child listens, speaks, and
// launches a rocket: the clearer the pronunciation, the higher it flies.
// Then a melody and spoken praise, the child hears itself as a mouse, bear
// or robot, and a word with at least one star flies into the world's
// collection at the bottom. Then the game goes on by itself: next word, or
// after 0 stars one more try at the same word.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../data/phrases.dart';
import '../phonetics/endpointer.dart';
import '../phonetics/phoneme_distance.dart';
import '../phonetics/recognizer.dart';
import '../ui/emoji_image.dart';
import '../ui/strings.dart';
import 'rocket_launch.dart';
import 'feedback.dart';
import 'rules.dart';
import 'voice_effects.dart';
import 'world_scene.dart';

/// One round: `starting` (permission, set-up) -> `speaking` (the phone says
/// the phrase) -> `listening` (hands-free: ends when the child stops
/// talking) -> `thinking` -> `result`. Taps during `starting`/`speaking`/
/// `thinking` are ignored, so a child cannot start two rounds.
enum _Phase { ready, starting, speaking, listening, thinking, result }

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key, required this.app, required this.world});

  final AppState app;
  final int world;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  final _tts = FlutterTts();
  final _player = AudioPlayer();

  /// Melodies; separate from [_player] so they may overlap the replay.
  final _sfx = AudioPlayer();
  final _rng = math.Random();
  String? _lastPraise;

  /// Tries of the current word (one retry after 0 stars).
  int _attempts = 0;

  /// Goes on to the next word (or the retry) after the feedback.
  Timer? _advance;

  /// Incremented when the child takes over (listen again, replay), so the
  /// running feedback stops where it is.
  int _feedbackId = 0;

  /// The app is in the background: nothing may start by itself.
  bool _paused = false;

  /// The last word is done and the dialog is open: the round is over.
  bool _worldDone = false;

  /// Praise in the world-done dialog, slightly after the fanfare.
  Timer? _donePraise;
  late final List<Phrase> _phrases = widget.app.book.world(widget.world);
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  int _index = 0;
  _Phase _phase = _Phase.ready;
  Comparison? _result;
  final _buffer = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _sub;
  Timer? _timer;
  double _level = 0;
  Endpointer? _endpointer;
  int _sessionStars = 0;

  /// The last recording (trimmed), kept in memory only for the funny replay.
  Float32List? _lastAudio;
  VoiceEffect _effect = VoiceEffect.robot; // the first replay is the mouse
  bool _replaying = false;

  /// Incremented to cancel a running replay.
  int _replayId = 0;

  /// Android plays the WAV from memory. audioplayers writes it to a temp
  /// file on iOS, and recordings must not be stored, so no replay there yet.
  final bool _canReplay = Platform.isAndroid;

  final _stackKey = GlobalKey();
  final _emojiKey = GlobalKey();
  late final _slotKeys = List.generate(_phrases.length, (_) => GlobalKey());
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// The phrase whose picture is flying into its slot, and the way.
  int? _flying;
  bool _flyingIsNew = false;
  (Rect, Rect)? _flightPath;

  /// The slot that jumps after a landing.
  int? _bounce;

  /// Incremented to abandon a running round (screen closed, app paused).
  int _round = 0;

  Phrase get _phrase => _phrases[_index];
  String get _lang => widget.app.book.lang;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tts.setLanguage(_lang);
    _tts.setSpeechRate(0.4);
    // speak() completes when the phrase has been said, so listening can
    // start right after it
    _tts.awaitSpeakCompletion(true);
    // melodies must not pause the replay or the praise
    _sfx.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    _round++;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _sub?.cancel();
    _recorder.dispose();
    _tts.stop();
    _replayId++;
    _advance?.cancel();
    _donePraise?.cancel();
    _player.dispose();
    _sfx.dispose();
    _bob.dispose();
    _fly.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Not on `inactive`: the permission dialog causes that.
    if (state == AppLifecycleState.paused) {
      _paused = true;
      _abort();
    } else if (state == AppLifecycleState.resumed && _paused) {
      _paused = false;
      // the word stays on screen; go on from there
      _scheduleAdvance(_round);
    }
  }

  bool get _idle => _phase == _Phase.ready || _phase == _Phase.result;
  bool _current(int round) => mounted && round == _round;

  /// Says the phrase again without recording.
  Future<void> _speak() async {
    if (!_idle) return;
    final round = _round;
    final id = ++_feedbackId;
    _advance?.cancel();
    await _stopReplay();
    await _speakText(_phrase.text);
    if (id == _feedbackId) _scheduleAdvance(round);
  }

  /// Speaks [text]; returns when done, or after a timeout if the TTS
  /// engine is missing or stuck, and never throws.
  Future<void> _speakText(String text) async {
    try {
      await _tts.stop();
      await _tts
          .speak(text)
          .timeout(
            Duration(seconds: 3 + text.length ~/ 4),
            onTimeout: () => null,
          );
    } catch (e, st) {
      debugPrint('tts failed: $e\n$st');
    }
  }

  /// Stops everything that would go on by itself after a word.
  void _cancelFlow() {
    _feedbackId++;
    _advance?.cancel();
  }

  /// Sounds are only allowed while nothing is being said or recorded.
  bool get _quiet =>
      _phase == _Phase.ready ||
      _phase == _Phase.result ||
      _phase == _Phase.thinking;

  /// Plays a synthesised sound (melody, pling).
  Future<void> _playSfx(Float32List sound) async {
    if (!_quiet || _paused) return;
    try {
      await _sfx.stop();
      // a round may have started meanwhile: never play into the mic
      if (!mounted || !_quiet) return;
      await _sfx.play(BytesSource(wavBytes(sound), mimeType: 'audio/wav'));
      if (!mounted || !_quiet) await _sfx.stop();
    } catch (e, st) {
      debugPrint('sound failed: $e\n$st');
    }
  }

  /// Melody, spoken praise and the funny replay; then on by itself.
  Future<void> _feedback(int round, int stars) async {
    final id = ++_feedbackId;
    bool gone() =>
        !_current(round) || _phase != _Phase.result || id != _feedbackId;
    unawaited(_playSfx(jingle(stars, _rng)));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (gone()) return;
    // after the last try the game moves on: do not ask for another one
    final text = pickPraise(
      _lang,
      stars,
      _rng,
      avoid: _lastPraise,
      onward: afterResult(stars, _attempts) == AfterResult.next,
    );
    _lastPraise = text;
    await _speakText(text);
    if (gone()) return;
    await _replay(advanceAfter: false);
    if (gone()) return;
    _scheduleAdvance(round);
  }

  /// After a short pause: the next word, or one more try after 0 stars.
  /// Nothing happens if the child started something else meanwhile.
  void _scheduleAdvance(int round) {
    _advance?.cancel();
    bool stale() =>
        !_current(round) ||
        _phase != _Phase.result ||
        _paused ||
        _worldDone ||
        _result == null;
    if (stale()) return;
    final id = _feedbackId;
    _advance = Timer(const Duration(milliseconds: 900), () {
      final result = _result;
      if (stale() || id != _feedbackId || result == null) return;
      if (_replaying) return; // the replay schedules again when it ends
      switch (afterResult(result.stars, _attempts)) {
        case AfterResult.retry:
          _play();
        case AfterResult.next:
          _next();
      }
    });
  }

  /// The funny-voice button: replay now, go on afterwards.
  void _onReplayTap() {
    _cancelFlow();
    _replay();
  }

  /// Stops a replay (playing or about to start).
  Future<void> _stopReplay() async {
    _replayId++;
    if (_replaying && mounted) setState(() => _replaying = false);
    await _player.stop();
  }

  /// Plays the last recording with the next funny voice. With
  /// [advanceAfter], the game goes on when it has finished.
  Future<void> _replay({bool advanceAfter = true}) async {
    final audio = _lastAudio;
    final round = _round;
    if (!_canReplay || audio == null || _phase != _Phase.result) {
      if (advanceAfter) _scheduleAdvance(round);
      return;
    }
    final id = ++_replayId;
    // A new round, Next or the background may cancel us at every await.
    bool cancelled() => !mounted || id != _replayId || _phase != _Phase.result;
    setState(() {
      _effect = _effect.next;
      _replaying = true;
    });
    try {
      await _tts.stop();
      await _player.stop();
      if (cancelled()) return;
      final effected = applyVoiceEffect(_effect, audio);
      final done = _player.onPlayerComplete.first;
      await _player.play(
        BytesSource(wavBytes(effected), mimeType: 'audio/wav'),
      );
      if (cancelled()) {
        await _player.stop();
        return;
      }
      final seconds = effected.length / 16000;
      await done.timeout(
        Duration(milliseconds: (seconds * 1000).round() + 1500),
        onTimeout: () {},
      );
    } catch (e, st) {
      debugPrint('replay failed: $e\n$st');
    } finally {
      // a newer replay (tap while playing) owns the flag now
      if (mounted && id == _replayId) {
        setState(() => _replaying = false);
        if (advanceAfter) _scheduleAdvance(round);
      }
    }
  }

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stack == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
  }

  /// The picture of phrase [i] flies from the big picture into its slot.
  /// [isNew]: the slot was empty before, so it stays empty until landing.
  void _flyToSlot(int i, {required bool isNew}) {
    final round = _round;
    final from = _rectOf(_emojiKey);
    final to = _rectOf(_slotKeys[i]);
    if (from == null || to == null) return;
    setState(() {
      _flying = i;
      _flyingIsNew = isNew;
      _flightPath = (from, to);
      _bounce = null;
    });
    _fly.forward(from: 0).then((_) {
      if (!mounted) return;
      if (_current(round) && _phase == _Phase.result) _playSfx(pling(_rng));
      setState(() {
        _flying = null;
        _flightPath = null;
        _bounce = i;
      });
    });
  }

  /// The phone says the phrase, then listens until the child has spoken.
  Future<void> _play() async {
    if (!_idle || !mounted || _worldDone) return;
    final round = ++_round;
    final back = _phase;
    setState(() {
      _phase = _Phase.starting;
      _lastAudio = null;
    });
    _cancelFlow();
    try {
      await _sfx.stop();
      await _stopReplay();
      // Ask before speaking, so the dialog does not cover the phrase.
      if (!await _recorder.hasPermission()) {
        _fail(back, (s) => s.needMic);
        return;
      }
      if (!_current(round)) return;
      setState(() {
        _phase = _Phase.speaking;
        _result = null;
      });
      await _tts.stop();
      await _tts
          .speak(_phrase.text)
          .timeout(
            Duration(seconds: 3 + _phrase.text.length ~/ 4),
            onTimeout: () => null, // no TTS engine: listen anyway
          );
      // let the speaker's echo fade before the mic opens
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!_current(round)) return;
      // never record our own replay or melody
      await _player.stop();
      await _sfx.stop();
      await _listen(round);
    } catch (e, st) {
      debugPrint('round failed: $e\n$st');
      if (_current(round)) _fail(back, (s) => s.tryAgain);
    }
  }

  Future<void> _listen(int round) async {
    _buffer.clear();
    final ep = _endpointer = Endpointer();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        noiseSuppress: true,
      ),
    );
    if (!_current(round)) {
      await _recorder.stop();
      return;
    }
    _sub = stream.listen((chunk) {
      _buffer.add(chunk);
      ep.addPcm16(chunk);
      if (!mounted) return;
      final db = 20 * math.log(math.max(ep.level, 1e-5)) / math.ln10;
      setState(() => _level = ((db + 50) / 50).clamp(0.0, 1.0));
      if (ep.done) _stop();
    });
    _timer = Timer(recordingLimit(_phrase.text), _stop);
    setState(() => _phase = _Phase.listening);
  }

  /// Ends the recording (child finished, time limit, or tap) and scores it.
  Future<void> _stop() async {
    if (_phase != _Phase.listening) return;
    final round = _round;
    // Set synchronously: the timer, the endpointer and a tap must not all
    // get past here.
    final phrase = _phrase;
    final heard = _endpointer?.heardSpeech ?? true;
    _timer?.cancel();
    setState(() {
      _phase = _Phase.thinking;
      _level = 0;
    });
    try {
      await _recorder.stop();
      await _sub?.cancel();
      _sub = null;
      if (!heard) {
        _fail(_Phase.ready, (s) => s.notHeard);
        return;
      }
      final audio = prepareForRecognition(pcm16ToFloat(_buffer.takeBytes()));
      final rec = await widget.app.recognizer.recognize(audio);
      final cmp = scorePhrase(widget.app.comparer, phrase, rec.ipa, _lang);
      final prev = await widget.app.progress.record(
        _lang,
        phrase.text,
        cmp.stars,
      );
      if (!_current(round)) return; // aborted (background) meanwhile
      setState(() {
        _phase = _Phase.result;
        _result = cmp;
        _sessionStars += starsGained(cmp.stars, prev);
        _lastAudio = audio;
        _attempts++;
      });
      if (cmp.stars >= 1) _flyToSlot(_index, isNew: prev < 1);
      unawaited(_feedback(round, cmp.stars));
    } catch (e, st) {
      debugPrint('recognition failed: $e\n$st');
      _fail(_Phase.ready, (s) => s.tryAgain);
    }
  }

  /// Stops whatever runs (app went to the background) without scoring.
  Future<void> _abort() async {
    _cancelFlow();
    _donePraise?.cancel();
    await _tts.stop();
    await _sfx.stop();
    await _stopReplay(); // also in the result phase, which counts as idle
    if (_idle) return;
    _round++;
    _timer?.cancel();
    await _tts.stop();
    if (_phase == _Phase.listening) {
      await _recorder.stop();
      await _sub?.cancel();
      _sub = null;
    }
    if (mounted) setState(() => _phase = _Phase.ready);
  }

  /// Big button: listening -> done talking; idle -> new round.
  void _onMic() {
    switch (_phase) {
      case _Phase.listening:
        _stop();
      case _Phase.ready || _Phase.result:
        _play();
      case _Phase.starting || _Phase.speaking || _Phase.thinking:
        break;
    }
  }

  /// Returns to [phase] and tells the parent what went wrong.
  void _fail(_Phase phase, String Function(S) message) {
    if (!mounted) return;
    setState(() => _phase = phase);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message(S.of(context)))));
  }

  void _next() {
    if (_worldDone) return;
    _cancelFlow();
    if (_index + 1 >= _phrases.length) {
      // end the round, so nothing of it goes on behind the dialog
      _worldDone = true;
      _round++;
      _tts.stop();
      _stopReplay();
      _showWorldDone();
      return;
    }
    setState(() {
      _attempts = 0;
      _index++;
      _phase = _Phase.ready;
      _result = null;
    });
    _play();
  }

  void _showWorldDone() {
    final s = S.of(context);
    _playSfx(fanfare(_rng));
    final text = pickPraise(_lang, 3, _rng, avoid: _lastPraise);
    _lastPraise = text;
    _donePraise = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && !_paused) _speakText(text);
    });
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const EmojiImage('🏆', size: 48),
            const SizedBox(width: 12),
            Text(s.worldDone),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DancingScene(
              emojis: [for (final p in _phrases) p.emoji],
              collected: _collected(),
            ),
            const SizedBox(height: 16),
            Text(s.newStars(_sessionStars)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: Text(s.ok),
          ),
        ],
      ),
    );
  }

  /// Which phrases of this world have at least one star (ever).
  List<bool> _collected() => [
    for (final p in _phrases) widget.app.progress.stars(_lang, p.text) >= 1,
  ];

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final collected = _collected();
    if (_flying != null && _flyingIsNew) {
      collected[_flying!] = false; // still in the air
    }
    return Scaffold(
      backgroundColor: const Color(0xFF14143A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          '${s.world} ${widget.world + 1}  ·  ${_index + 1}/${_phrases.length}',
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            return Stack(
              key: _stackKey,
              children: [
                const Positioned.fill(child: Starfield()),
                Positioned.fill(
                  child: RocketLaunch(
                    key: ValueKey('rocket-$_index-${_result.hashCode}'),
                    target: _result?.score,
                    stars: _result?.stars ?? 0,
                  ),
                ),
                Column(
                  children: [
                    // Picture, word and result take what is left above the
                    // buttons and shrink on small phones.
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SizedBox(width: c.maxWidth, child: _top(s, c)),
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: _phase == _Phase.listening ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        s.yourTurn,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _controls(s, scheme),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: WorldScene(
                        emojis: [for (final p in _phrases) p.emoji],
                        collected: collected,
                        current: _index,
                        slotKeys: _slotKeys,
                        bounce: _bounce,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
                if (_flying != null && _flightPath != null)
                  _Flight(
                    animation: _fly,
                    path: _flightPath!,
                    emoji: _phrases[_flying!].emoji,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Picture (tap: hear it again) with the funny-voice button beside it,
  /// the word, and the result chips.
  Widget _top(S s, BoxConstraints c) {
    final showReplay =
        _canReplay && _lastAudio != null && _phase == _Phase.result;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // same width on both sides keeps the picture centred
            SizedBox(
              width: 80,
              child: showReplay
                  ? AnimatedScale(
                      scale: _replaying ? 1.2 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: _RoundButton(
                        tooltip: s.funnyVoice,
                        size: 64,
                        onTap: _onReplayTap,
                        color: const Color(0xFF7C4DFF),
                        child: EmojiImage(_effect.emoji, size: 40),
                      ),
                    )
                  : null,
            ),
            AnimatedBuilder(
              animation: _bob,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, math.sin(_bob.value * math.pi) * -10),
                child: child,
              ),
              child: GestureDetector(
                onTap: _idle ? _speak : null,
                child: EmojiImage(
                  _phrase.emoji,
                  key: _emojiKey,
                  size: math.min(160, c.maxHeight * 0.22),
                ),
              ),
            ),
            const SizedBox(width: 80),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _phrase.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: 12),
          PhonemeChips(result: _result!),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _controls(S s, ColorScheme scheme) {
    final listening = _phase == _Phase.listening;
    final busy = _phase == _Phase.thinking || _phase == _Phase.starting;
    final Widget micChild = switch (_phase) {
      _Phase.starting ||
      _Phase.thinking => const CircularProgressIndicator(color: Colors.white),
      _Phase.speaking => const EmojiImage('👂', size: 60),
      _ => const EmojiImage('🎤', size: 60),
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          tooltip: s.listen,
          onTap: _idle ? _speak : null,
          color: const Color(0xFF3D5AFE),
          child: const EmojiImage('🔊', size: 40),
        ),
        AnimatedScale(
          scale: listening ? 1.0 + _level * 0.35 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: _RoundButton(
            tooltip: listening ? s.yourTurn : s.speak,
            size: 110,
            onTap: busy || _phase == _Phase.speaking ? null : _onMic,
            dimmed: busy,
            color: listening
                ? const Color(0xFFFF5252)
                : _phase == _Phase.speaking
                ? const Color(0xFF3D5AFE)
                : const Color(0xFFFF9100),
            child: micChild,
          ),
        ),
        _RoundButton(
          tooltip: s.next,
          onTap: _phase == _Phase.result ? _next : null,
          color: const Color(0xFF00C853),
          child: const Icon(
            Icons.arrow_forward_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
      ],
    );
  }
}

/// A picture on its way from [path].$1 to [path].$2, along an arc.
class _Flight extends AnimatedWidget {
  const _Flight({
    required Animation<double> animation,
    required this.path,
    required this.emoji,
  }) : super(listenable: animation);

  final (Rect, Rect) path;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeInOutCubic.transform(
      (listenable as Animation<double>).value,
    );
    final (from, to) = path;
    final r = Rect.lerp(from, to, t)!;
    // a little hop sideways and up, then down into the slot
    final lift = math.sin(t * math.pi) * 80;
    return Positioned.fromRect(
      rect: r.shift(Offset(lift * 0.5, -lift)),
      child: IgnorePointer(
        child: Transform.rotate(
          angle: t * 2 * math.pi,
          child: FittedBox(child: EmojiImage(emoji, size: from.height)),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.child,
    required this.onTap,
    required this.color,
    required this.tooltip,
    this.size = 76,
    this.dimmed,
  });

  /// Defaults to "disabled"; false keeps a busy button fully visible.
  final bool? dimmed;

  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dim = dimmed ?? onTap == null;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: dim ? 0.35 : 1,
        child: Material(
          color: color,
          shape: const CircleBorder(),
          elevation: dim ? 0 : 8,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// One chip per expected phoneme: green = good, orange = close, red = missing/wrong.
class PhonemeChips extends StatelessWidget {
  const PhonemeChips({super.key, required this.result});

  final Comparison result;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    int? word;
    for (final a in result.alignment) {
      if (a.target == null) continue; // extra sounds are not shown to kids
      if (word != null && a.word != word) chips.add(const SizedBox(width: 12));
      word = a.word;
      final color = a.exact
          ? const Color(0xFF00C853)
          : a.close
          ? const Color(0xFFFFAB00)
          : const Color(0xFFFF5252);
      chips.add(
        Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            a.target!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return Wrap(alignment: WrapAlignment.center, children: chips);
  }
}
