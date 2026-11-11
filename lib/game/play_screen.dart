// One "world" = 8 phrases. For each phrase the child listens, speaks, and
// launches a rocket: the clearer the pronunciation, the higher it flies.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../data/phrases.dart';
import '../phonetics/phoneme_distance.dart';
import '../phonetics/recognizer.dart';
import '../ui/emoji_image.dart';
import '../ui/strings.dart';
import 'rocket_launch.dart';

enum _Phase { ready, listening, thinking, result }

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key, required this.app, required this.world});

  final AppState app;
  final int world;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> with TickerProviderStateMixin {
  static const _maxRecording = Duration(seconds: 4);

  final _recorder = AudioRecorder();
  final _tts = FlutterTts();
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
  StreamSubscription<Amplitude>? _ampSub;
  int _sessionStars = 0;

  Phrase get _phrase => _phrases[_index];
  String get _lang => widget.app.book.lang;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage(_lang);
    _tts.setSpeechRate(0.4);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    _ampSub?.cancel();
    _recorder.dispose();
    _tts.stop();
    _bob.dispose();
    super.dispose();
  }

  Future<void> _speak() async {
    await _tts.stop();
    await _tts.speak(_phrase.text);
  }

  Future<void> _toggleMic() async {
    if (_phase == _Phase.listening) {
      await _stop();
      return;
    }
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(S.of(context).needMic)));
      }
      return;
    }
    await _tts.stop();
    _buffer.clear();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        noiseSuppress: true,
      ),
    );
    _sub = stream.listen(_buffer.add);
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((a) {
          setState(() => _level = ((a.current + 50) / 50).clamp(0.0, 1.0));
        });
    _timer = Timer(_maxRecording, _stop);
    setState(() {
      _phase = _Phase.listening;
      _result = null;
    });
  }

  Future<void> _stop() async {
    if (_phase != _Phase.listening) return;
    _timer?.cancel();
    await _recorder.stop();
    await _sub?.cancel();
    await _ampSub?.cancel();
    setState(() {
      _phase = _Phase.thinking;
      _level = 0;
    });
    final audio = trimSilence(pcm16ToFloat(_buffer.takeBytes()));
    final rec = await widget.app.recognizer.recognize(audio);
    final cmp = widget.app.comparer.compare(_phrase.ipa, rec.ipa, _lang);
    final best = await widget.app.progress.record(
      _lang,
      _phrase.text,
      cmp.stars,
    );
    if (!mounted) return;
    setState(() {
      _phase = _Phase.result;
      _result = cmp;
      if (best) _sessionStars += cmp.stars;
    });
  }

  void _next() {
    if (_index + 1 >= _phrases.length) {
      _showWorldDone();
      return;
    }
    setState(() {
      _index++;
      _phase = _Phase.ready;
      _result = null;
    });
  }

  void _showWorldDone() {
    final s = S.of(context);
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
        content: Text(s.newStars(_sessionStars)),
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

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
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
                    const SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: _bob,
                      builder: (_, child) => Transform.translate(
                        offset: Offset(0, math.sin(_bob.value * math.pi) * -10),
                        child: child,
                      ),
                      child: GestureDetector(
                        onTap: _speak,
                        child: EmojiImage(
                          _phrase.emoji,
                          size: math.min(160, c.maxHeight * 0.22),
                        ),
                      ),
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
                    const Spacer(),
                    _controls(s, scheme),
                    const SizedBox(height: 24),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _controls(S s, ColorScheme scheme) {
    final listening = _phase == _Phase.listening;
    final thinking = _phase == _Phase.thinking;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          tooltip: s.listen,
          onTap: thinking ? null : _speak,
          color: const Color(0xFF3D5AFE),
          child: const EmojiImage('🔊', size: 40),
        ),
        AnimatedScale(
          scale: listening ? 1.0 + _level * 0.35 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: _RoundButton(
            tooltip: s.speak,
            size: 110,
            onTap: thinking ? null : _toggleMic,
            color: listening
                ? const Color(0xFFFF5252)
                : const Color(0xFFFF9100),
            child: thinking
                ? const CircularProgressIndicator(color: Colors.white)
                : const EmojiImage('🎤', size: 60),
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

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.child,
    required this.onTap,
    required this.color,
    required this.tooltip,
    this.size = 76,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Material(
          color: color,
          shape: const CircleBorder(),
          elevation: enabled ? 8 : 0,
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
