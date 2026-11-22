// Voice games: no words, just the voice.
// - Hold it long: "Aaaa" as long as you can; a balloon grows, and at 8 s it
//   flies away. 3 / 5 / 8 s give 1 / 2 / 3 stars. Only the time of the
//   right sound counts: afterwards the recognizer checks it (a long A is
//   no O, hold_vowel.dart).
// - Low and high: "A" in your own voice, then low like a bear, then high
//   like a mouse; the animal moves with the voice. Stars by how far from
//   the own voice (in semitones).
// The phone says what to do (low and high in its own voice, too), then
// listens. Nothing is stored: the sound is measured frame by frame; hold
// it long keeps it in memory until the sound is checked, then drops it.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../game/feedback.dart';
import '../game/game_io.dart';
import '../game/rocket_launch.dart';
import '../game/voice_effects.dart';
import '../net/quiz_report.dart';
import '../ui/emoji_image.dart';
import '../ui/recording_report.dart';
import '../ui/round_button.dart';
import '../ui/round_parts.dart';
import '../ui/strings.dart';
import '../phonetics/recognizer.dart';
import 'hold_vowel.dart';
import 'pitch.dart';
import 'voice_lines.dart';
import 'voice_listener.dart';
import 'voice_take.dart';

enum VoiceGame { hold, pitch }

enum _Phase { ready, speaking, listening, result }

class VoiceGameScreen extends StatefulWidget {
  const VoiceGameScreen({super.key, required this.app, required this.game});

  final AppState app;
  final VoiceGame game;

  @override
  State<VoiceGameScreen> createState() => _VoiceGameScreenState();
}

/// The steps of the low-and-high game.
enum _PitchStep { normal, low, high }

class _VoiceGameScreenState extends State<VoiceGameScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final VoiceListener _listener;
  late final Speaker _tts;
  late final SoundOut _sfx;
  late final math.Random _rng;
  late final VoiceLines _lines = VoiceLines.of(_lang);

  _Phase _phase = _Phase.ready;

  /// Hold: the sound; low and high: [_PitchStep] index.
  int _step = 0;
  int _attempts = 0;

  /// The try that is being listened to or was just scored.
  VoiceTake? _take;

  /// Hold it long: the time of the right sound in the scored try.
  Duration? _counted;

  /// 🐞 (hold it long): the last tries of the sound, with what was heard.
  late final RecordingReports _reports = RecordingReports(widget.app);

  /// The child's own voice (Hz), from the first step of low and high.
  double? _baseline;

  /// Semitones from [_baseline] of the scored try.
  double? _result;
  int? _resultStars;
  bool _newRecord = false;
  String? _lastPraise;

  /// What comes after the shown result.
  AfterResult _after = AfterResult.next;

  /// The own voice must be held this long to count (a stable pitch).
  static const _baselineMin = Duration(milliseconds: 400);

  /// When the own voice cannot be measured: a typical child's (Hz).
  static const _typicalChild = 260.0;

  /// Best stars per step in this round, for the summary.
  late final List<int> _stars = List.filled(_steps, 0);

  /// Incremented to stop whatever runs (new try, pause, closing).
  int _flow = 0;
  bool _paused = false;
  bool _over = false;
  Timer? _onward;
  Timer? _donePraise;

  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  String get _lang => widget.app.book.lang;
  bool get _hold => widget.game == VoiceGame.hold;
  int get _steps => _hold ? _lines.sounds.length : _PitchStep.values.length;
  _PitchStep get _pitchStep => _PitchStep.values[_step];
  bool get _idle => _phase == _Phase.ready || _phase == _Phase.result;
  bool _current(int id) => mounted && id == _flow && !_paused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final io = widget.app.io;
    _listener = VoiceListener(io.mic());
    _tts = io.speaker();
    _sfx = io.soundPlayer();
    _rng = io.random();
    _tts.setLanguage(_lang);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
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
    _float.dispose();
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
      _paused = false; // goes on with a tap
    }
  }

  String _instruction() {
    if (_hold) return _lines.holdSay(_lines.sounds[_step]);
    return switch (_pitchStep) {
      _PitchStep.normal => _lines.pitchNormal,
      _PitchStep.low => _lines.pitchLow,
      _PitchStep.high => _lines.pitchHigh,
    };
  }

  /// The phone shows how: low for the bear, high for the mouse.
  double _ttsPitch() => _hold
      ? 1
      : switch (_pitchStep) {
          _PitchStep.normal => 1,
          _PitchStep.low => 0.6,
          _PitchStep.high => 1.8,
        };

  Future<void> _say(String text, {double pitch = 1}) async {
    try {
      await _tts.stop();
      await _tts
          .speak(text, pitch: pitch)
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

  /// Says what to do, then listens until the sound is over, then scores.
  Future<void> _start() async {
    if (!_idle || _over || !mounted) return;
    final id = ++_flow;
    _onward?.cancel();
    _float.reset();
    setState(() {
      _phase = _Phase.speaking;
      _take = null;
      _counted = null;
      _result = null;
      _resultStars = null;
      _newRecord = false;
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
    await _say(_instruction(), pitch: _ttsPitch());
    // let the speaker's echo fade before the mic opens
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!_current(id)) return;
    await _quietly(_tts.stop);
    await _quietly(_sfx.stop);
    // paused or closed meanwhile: the mic must not open
    if (!_current(id)) return;
    final take = VoiceTake(
      // low and high: a short "A" is enough
      maxHeld: _hold ? const Duration(seconds: 15) : const Duration(seconds: 3),
    );
    setState(() {
      _phase = _Phase.listening;
      _take = take;
    });
    final audio = _hold ? BytesBuilder(copy: false) : null;
    final heard = await _listener.listen(
      take,
      onFrame: (_, _) {
        if (mounted) setState(() {});
      },
      audio: audio,
    );
    if (!_current(id)) return;
    if (heard == null) {
      // the mic could not start (cancelling also gives null, but then the
      // flow is not current any more)
      _fail(id, (s) => s.tryAgain);
      return;
    }
    if (heard.heardNothing || heard.pitch == null) {
      _fail(id, (s) => s.notHeardVoice);
      return;
    }
    _attempts++;
    ({Duration counted, String? wrong})? sound;
    if (_hold) {
      setState(() => _phase = _Phase.speaking);
      final pcm = audio!.takeBytes();
      sound = await _checkSound(heard, pcm);
      if (!_current(id)) return;
      if (sound == null) {
        _fail(id, (s) => s.tryAgain);
        return;
      }
    }
    await _score(id, heard, sound);
  }

  /// 20 ms of 16 kHz 16-bit PCM.
  static const _frameBytes = 640;

  /// Hold it long: how long the right sound was held, or the wrong sound
  /// heard instead ("a" when an O was asked for). Null if the recognizer
  /// failed.
  ///
  /// With reports on, the try is kept for 🐞: the whole recording, what
  /// was heard, and which part of it counted.
  Future<({Duration counted, String? wrong})?> _checkSound(
    VoiceTake take,
    Uint8List pcm,
  ) async {
    final sound = _lines.sounds[_step];
    final from = take.startFrame! * _frameBytes;
    final to = math.min(take.endFrame! * _frameBytes, pcm.length);
    // for a report: the held sound with a little before and after (the
    // service takes 13 s; a longer hold loses its end)
    final kept = to <= from
        ? pcm
        : Uint8List.sublistView(
            pcm,
            math.max(0, from - 16000),
            math.min(pcm.length, to + 9600),
          );
    void keep(String ipa, VowelCheck? check) => _reports.keep(
      sound,
      QuizTry(
        pcm: kept,
        speech: take.started,
        heard: ipa,
        // the sound heard instead, if it was wrong
        said: check == null
            ? ''
            : check.wrong
            ? check.heard ?? ''
            : sound.sound,
        scores: [(option: sound.shown, score: check?.share ?? 1, same: 0)],
      ),
    );
    if (to <= from) {
      keep('', null);
      return (counted: take.held, wrong: null);
    }
    final Recognition r;
    try {
      r = await widget.app.recognizer.recognize(
        prepareForRecognition(
          pcm16ToFloat(Uint8List.sublistView(pcm, from, to)),
        ),
      );
    } catch (e, st) {
      debugPrint('recognizing the held sound failed: $e\n$st');
      return null;
    }
    final want = sound.sound;
    final check = checkVowel(r, want);
    keep(r.ipa, check);
    debugPrint(
      'hold $want: heard "${r.ipa}" -> '
      '${check == null ? 'nothing clear' : '${check.share} ${check.heard}'}',
    );
    // nothing clear heard: the time counts, the child is not punished
    if (check == null) return (counted: take.held, wrong: null);
    if (check.wrong) return (counted: Duration.zero, wrong: check.heard);
    return (counted: take.held * check.share, wrong: null);
  }

  void _fail(int id, String Function(S) message) {
    if (!mounted || id != _flow) return;
    setState(() => _phase = _Phase.ready);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message(S.of(context)))));
  }

  Future<void> _score(
    int id,
    VoiceTake take, [
    ({Duration counted, String? wrong})? sound,
  ]) async {
    final progress = widget.app.progress;
    int? stars;
    var record = false;
    double? st;
    if (_hold) {
      final counted = sound!.counted;
      _counted = counted;
      stars = holdStars(counted);
      record = await progress.recordHold(
        _lang,
        _lines.sounds[_step].shown,
        counted,
      );
    } else if (_pitchStep == _PitchStep.normal) {
      final hz = take.pitch!;
      if (take.held >= _baselineMin && plausibleVoice(hz)) {
        _baseline = hz;
        await progress.setPitchBase(hz);
      } else if (_attempts < 2) {
        stars = 0; // "once more", without stars on screen
      } else {
        // never stuck before the bear: the voice of last time, or a child's
        _baseline = progress.pitchBase ?? _typicalChild;
      }
    } else {
      st = semitones(_baseline!, take.pitch!);
      final low = _pitchStep == _PitchStep.low;
      stars = low ? lowStars(st) : highStars(st);
      final far = low ? -st : st;
      if (far > 0) record = await progress.recordPitch(far, low: low);
    }
    if (!_current(id)) return;
    // a record is worth saying only with a star: the first try is always
    // one ("Great! New record!", then "hold it once more" for 0.7 s)
    if (stars == 0) record = false;
    final judged = stars != null && (_hold || _pitchStep != _PitchStep.normal);
    if (judged) _stars[_step] = math.max(_stars[_step], stars);
    final after = stars == null
        ? AfterResult.next
        : afterResult(stars, _attempts);
    setState(() {
      _phase = _Phase.result;
      _result = st;
      _resultStars = judged ? stars : null;
      _newRecord = record;
      _after = after;
    });
    if (stars == 3 && _hold) _float.forward(from: 0);
    // the own voice is not judged: a friendly "good" and on
    final shown = stars ?? 2;
    unawaited(_sound(jingle(shown, _rng)));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!_current(id)) return;
    var text = pickPraise(
      _lang,
      // a new record is a success: never "Almost! New record!"
      record ? math.max(shown, 2) : shown,
      _rng,
      avoid: _lastPraise,
      onward: after == AfterResult.next,
    );
    _lastPraise = text;
    if (record) text = '$text ${_lines.record}';
    // another sound than asked for: say which (no praise for it)
    final wrong = sound?.wrong;
    if (wrong != null) text = _lines.holdWrong(_lines.sounds[_step], wrong);
    await _say(text);
    if (!_current(id)) return;
    _onward = Timer(const Duration(milliseconds: 900), () {
      if (_current(id) && _phase == _Phase.result) _goOn();
    });
  }

  /// After a result: the same step once more, or the next one.
  void _goOn() {
    if (_after == AfterResult.retry) {
      _start();
    } else {
      _nextStep();
    }
  }

  void _nextStep() {
    if (_over) return;
    if (_step + 1 >= _steps) {
      _finish();
      return;
    }
    setState(() {
      _step++;
      _attempts = 0;
      _phase = _Phase.ready;
    });
    _start();
  }

  /// Big button: listening -> done; otherwise the next try now.
  void _onMic() {
    switch (_phase) {
      case _Phase.listening:
        _listener.stopNow();
      case _Phase.ready:
        _start();
      case _Phase.result:
        _flow++;
        _onward?.cancel();
        _quietly(_tts.stop);
        _goOn();
      case _Phase.speaking:
        break;
    }
  }

  /// 🔊: hear what to do again (before trying).
  Future<void> _again() async {
    if (_phase != _Phase.ready) return;
    await _say(_instruction(), pitch: _ttsPitch());
  }

  void _finish() {
    _over = true;
    _flow++;
    final s = S.of(context);
    unawaited(_sound(fanfare(_rng)));
    final text = pickPraise(_lang, 3, _rng, avoid: _lastPraise);
    _donePraise = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && !_paused) _say(text);
    });
    final rows = _hold
        ? [
            for (final (i, snd) in _lines.sounds.indexed)
              (
                label: Text(snd.shown, style: _letterStyle(28)),
                stars: _stars[i],
              ),
          ]
        : [
            (
              label: const EmojiImage('🐻', size: 36),
              stars: _stars[_PitchStep.low.index],
            ),
            (
              label: const EmojiImage('🐭', size: 36),
              stars: _stars[_PitchStep.high.index],
            ),
          ];
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      // the back button must not close it: the game is over
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          scrollable: true,
          title: Row(
            children: [
              const EmojiImage('🏆', size: 48),
              const SizedBox(width: 12),
              Flexible(child: Text(s.worldDone)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 64, child: Center(child: r.label)),
                      _StarRow(stars: r.stars, size: 28),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            DoneButton(
              label: s.ok,
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  static TextStyle _letterStyle(double size) => TextStyle(
    color: Colors.white,
    fontSize: size,
    fontWeight: FontWeight.w900,
    shadows: const [Shadow(blurRadius: 6, color: Colors.black45)],
  );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF14143A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          '${_hold ? s.holdTitle : s.pitchTitle}  ·  ${_step + 1}/$_steps',
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: Starfield()),
            Column(
              children: [
                Expanded(child: _hold ? _holdScene(s) : _pitchScene()),
                AnimatedOpacity(
                  opacity: _phase == _Phase.listening ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Text(s.yourTurn, style: _letterStyle(28)),
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

  Widget _controls(S s) {
    final listening = _phase == _Phase.listening;
    final level = _take == null || !listening
        ? 0.0
        : (_take!.started ? 0.25 : 0.0);
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
            onTap: _phase == _Phase.speaking ? null : _onMic,
            color: listening
                ? const Color(0xFFFF5252)
                : _phase == _Phase.speaking
                ? const Color(0xFF3D5AFE)
                : const Color(0xFFFF9100),
            child: EmojiImage(
              _phase == _Phase.speaking ? '👂' : '🎤',
              size: 60,
            ),
          ),
        ),
        if (_hold && _reports.on)
          _reports.button(s, _sendReport)
        else
          // keeps the mic button centred
          const SizedBox(width: 76),
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
      final sound = of as HoldSound;
      return (
        question: 'hold: ${sound.shown}',
        asked: _lines.holdSay(sound),
        options: [
          (text: sound.shown, ipa: [sound.sound]),
        ],
        answer: sound.shown,
      );
    },
  );

  // --- hold it long ---------------------------------------------------

  static const _holdMarks = [3, 5, 8]; // seconds for 1, 2, 3 stars

  Widget _holdScene(S s) {
    final sound = _lines.sounds[_step];
    // listening: how long so far; scored: the time of the right sound
    final held = ((_counted ?? _take?.held)?.inMilliseconds ?? 0) / 1000;
    final best = widget.app.progress.holdBest(_lang, sound.shown);
    return LayoutBuilder(
      builder: (context, c) {
        final grow = (held / _holdMarks.last).clamp(0.0, 1.0);
        final size = math.min(c.maxWidth * 0.75, c.maxHeight * 0.7);
        final balloon = size * (0.3 + 0.7 * grow);
        return Column(
          children: [
            const SizedBox(height: 8),
            if (_resultStars != null)
              _StarRow(stars: _resultStars!, size: 44)
            else
              const SizedBox(height: 44),
            if (_newRecord)
              Text(s.newRecord, style: _letterStyle(24))
            else
              const SizedBox(height: 30),
            Expanded(
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  // how far: a star lights up at 3, 5 and 8 seconds
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final m in _holdMarks.reversed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: AnimatedOpacity(
                            opacity: held >= m ? 1 : 0.25,
                            duration: const Duration(milliseconds: 200),
                            child: const EmojiImage('⭐', size: 40),
                          ),
                        ),
                    ],
                  ),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _float,
                      builder: (_, child) => FractionalTranslation(
                        translation: Offset(
                          0.15 * math.sin(_float.value * 6),
                          -2.5 * Curves.easeIn.transform(_float.value),
                        ),
                        child: child,
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: balloon,
                          height: balloon,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned.fill(
                                child: FittedBox(
                                  child: EmojiImage('🎈', size: size),
                                ),
                              ),
                              Align(
                                alignment: const Alignment(-0.1, -0.25),
                                child: FittedBox(
                                  child: Padding(
                                    padding: EdgeInsets.all(balloon * 0.22),
                                    child: Text(
                                      sound.shown,
                                      style: _letterStyle(64),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 72),
                ],
              ),
            ),
            // for the grown-ups: seconds, and the best so far
            Text(
              '${_seconds(held)} s'
              '${best > Duration.zero ? '   ·   ${s.best}: ${_seconds(best.inMilliseconds / 1000)} s' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        );
      },
    );
  }

  /// "5.5" in English, "5,5" in the other languages.
  String _seconds(double s) {
    final t = s.toStringAsFixed(1);
    final code = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    return code == 'en' ? t : t.replaceAll('.', ',');
  }

  // --- low and high ---------------------------------------------------

  /// Semitones shown from the bottom to the top of the lane.
  static const _lowest = -8.0, _highest = 12.0;

  Widget _pitchScene() {
    final animal = switch (_pitchStep) {
      _PitchStep.normal => '🙂',
      _PitchStep.low => '🐻',
      _PitchStep.high => '🐭',
    };
    final base = _baseline;
    final live = _phase == _Phase.listening ? _take?.livePitch : null;
    // where the animal is: the result, the live voice, or the middle
    final st =
        _result ??
        (base != null && live != null ? semitones(base, live) : null);
    final marks = switch (_pitchStep) {
      _PitchStep.normal => const <double>[],
      _PitchStep.low => const [-1.5, -3.0, -5.0],
      _PitchStep.high => const [2.0, 4.0, 7.0],
    };
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight - 80;
        double y(double st) =>
            h *
            (1 -
                (st.clamp(_lowest, _highest) - _lowest) / (_highest - _lowest));
        final zero = y(0);
        return Stack(
          children: [
            if (_resultStars != null)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    _StarRow(stars: _resultStars!, size: 44),
                    if (_newRecord)
                      Text(S.of(context).newRecord, style: _letterStyle(24)),
                  ],
                ),
              ),
            // the own voice
            if (base != null)
              Positioned(
                top: zero + 40,
                left: 24,
                right: 24,
                child: Container(height: 3, color: Colors.white38),
              ),
            // stars to reach
            for (final (i, m) in marks.indexed)
              Positioned(
                top: y(m) + 40 - 14,
                right: 16,
                child: Opacity(
                  opacity: _resultStars != null && _resultStars! > i ? 1 : 0.4,
                  child: Row(
                    children: [
                      Container(width: 60, height: 2, color: Colors.white24),
                      const EmojiImage('⭐', size: 28),
                    ],
                  ),
                ),
              ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 120),
              top: ((st == null ? zero : y(st)) + 40 - 48).clamp(
                0.0,
                math.max(0.0, c.maxHeight - 96),
              ),
              left: c.maxWidth / 2 - 48,
              child: EmojiImage(animal, size: 96),
            ),
          ],
        );
      },
    );
  }
}

/// [stars] of three, the rest dim.
class _StarRow extends StatelessWidget {
  const _StarRow({required this.stars, required this.size});
  final int stars;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 3; i++)
        Opacity(
          opacity: i < stars ? 1 : 0.25,
          child: EmojiImage('⭐', size: size),
        ),
    ],
  );
}
