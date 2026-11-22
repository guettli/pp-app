// The thinking games: no letters, no numbers, the child thinks about the
// world and taps a picture.
//
// "What do I need?" (🎒, [ThinkGame.needs]): the phone tells a small
// problem ("My hands are cold. What do I need?"); one of three pictures
// helps (🧤).
//
// "Who am I?" (🕵️, [ThinkGame.riddle]): a thing tells about itself, one
// clue after the other ("I live on a farm." "I eat grass." "I say moo!");
// the child taps one of four pictures when sure. 💡 gives the next clue
// at any time: waiting and listening costs nothing, only a wrong tap
// does. Each clue alone fits only the answer among the pictures (no
// banana with the apple: it can be eaten and grows on a tree too).
//
// "Odd one out" (🧺, [ThinkGame.odd]): three pictures of one kind, one of
// another; a wrong tap brings a nudge ("Three of them are animals."),
// the right tap says why ("The others are all animals.").
//
// "Who lives here?" (🏞️, [ThinkGame.home]): a place (🌊) and three
// animals; one lives there.
//
// "Feeling faces" (😄😠, [ThinkGame.faces]): a feeling is named, four
// faces. "How do I feel?" (🍦😢, [ThinkGame.feelings]): a small story,
// three faces; the right one says what helps (feelings_data.dart).
//
// A wrong tap says what the tapped picture is and goes on with the next
// clue (or the problem once more). Only a right first tap counts for the
// stars. No microphone.
//
// If a grown-up switched on quiz reports (feedback screen), a 🐞 button
// sends the current question (what was said, the pictures, the answer,
// the taps, an optional note) as a bug report through the feedback
// outbox, after asking. No recording: there is none.
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
import '../net/feedback.dart';
import '../quiz/quiz_rules.dart' show quizStars;
import '../ui/emoji_image.dart';
import '../ui/intros.dart';
import '../ui/round_button.dart';
import '../ui/round_parts.dart';
import '../ui/strings.dart';
import 'think_rules.dart';

/// The name is the key of the best round in [Progress.thinkBest].
enum ThinkGame { needs, riddle, odd, home, faces, feelings }

enum _Phase { speaking, choosing, result }

class ThinkScreen extends StatefulWidget {
  const ThinkScreen({
    super.key,
    required this.app,
    required this.game,
    this.round,
    this.intro = true,
    this.info = deviceInfo,
  });

  final AppState app;
  final ThinkGame game;

  /// The questions; a new random round if null (tests set it).
  final List<ThinkQuestion>? round;

  /// Say what to do before the first question (off in tests of the flow).
  final bool intro;

  /// App version, phone and Android version for a 🐞 report (replaced in
  /// tests).
  final Future<Map<String, String>> Function() info;

  @override
  State<ThinkScreen> createState() => _ThinkScreenState();
}

class _ThinkScreenState extends State<ThinkScreen> with WidgetsBindingObserver {
  late final Speaker _tts;
  late final SoundOut _sfx;
  late final math.Random _rng;
  late final List<ThinkQuestion> _round = widget.round ?? _makeRound();

  _Phase _phase = _Phase.speaking;
  int _index = 0;

  /// How many clues of the current question were said (or are being).
  int _given = 0;

  /// Per question: right at the first tap (true), not (false), not yet.
  late final List<bool?> _results = List.filled(_round.length, null);

  /// Pictures of the current question tapped wrongly.
  final _wrong = <Phrase>{};

  /// 🐞: the report dialog is open (or about to): the game holds.
  bool _asking = false;

  /// 🐞: the report is being sent (the game goes on meanwhile).
  bool _reporting = false;

  /// Questions (by index) already reported.
  final _reported = <int>{};

  late bool _introDone = !widget.intro;

  /// The intro is being said: pictures do not react yet.
  bool _introPlaying = false;
  String? _lastPraise;

  /// Incremented to stop what runs (new question, pause, closing).
  int _flow = 0;
  bool _paused = false;
  bool _over = false;
  Timer? _onward;
  Timer? _donePraise;

  String get _lang => widget.app.book.lang;
  bool get _riddle => widget.game == ThinkGame.riddle;
  ThinkQuestion get _q => _round[_index];
  bool get _moreClues => _given < _q.clues.length;

  List<ThinkQuestion> _makeRound() {
    final book = widget.app.book;
    return switch (widget.game) {
      ThinkGame.needs => makeNeedsRound(book, _rng),
      ThinkGame.riddle => makeRiddleRound(book, _rng),
      ThinkGame.odd => makeOddRound(book, widget.app.facts, _rng),
      ThinkGame.home => makeHomeRound(book, _rng),
      ThinkGame.faces => makeFacesRound(_lang, _rng),
      ThinkGame.feelings => makeFeelingsRound(_lang, _rng),
    };
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
      _introPlaying = false;
      // a clue cut off: 🔊 says it again
      if (_phase == _Phase.speaking && mounted) {
        setState(() => _phase = _Phase.choosing);
      }
    } else if (state == AppLifecycleState.resumed) {
      _paused = false;
      // the report dialog is open: it goes on when that closes
      if (_asking) return;
      // back while choosing: what was said so far, once more
      // paused before the first clue (during the intro): ask it now
      if (_over) return;
      if (_given == 0) {
        _ask();
      } else if (_phase == _Phase.choosing) {
        _repeat();
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

  /// Says [text] (a clue); afterwards the pictures wait for a tap. They
  /// can be tapped while it is said, too.
  Future<void> _speakThen(int id, String text) async {
    setState(() => _phase = _Phase.speaking);
    await _say(text);
    if (_current(id) && _phase == _Phase.speaking) {
      setState(() => _phase = _Phase.choosing);
    }
  }

  /// The first clue of the current question (after the intro, once).
  Future<void> _ask() async {
    if (_over || !mounted || _round.isEmpty) return;
    final id = ++_flow;
    _onward?.cancel();
    if (!_introDone) {
      _introDone = true;
      setState(() {
        _phase = _Phase.speaking;
        _introPlaying = true;
      });
      await _say(
        introLine(switch (widget.game) {
          ThinkGame.needs => GameIntro.needs,
          ThinkGame.riddle => GameIntro.riddle,
          ThinkGame.odd => GameIntro.odd,
          ThinkGame.home => GameIntro.home,
          ThinkGame.faces => GameIntro.faces,
          ThinkGame.feelings => GameIntro.feelings,
        }, _lang),
      );
      if (mounted) setState(() => _introPlaying = false);
      if (!_current(id) || _phase != _Phase.speaking) return;
    }
    setState(() => _given = 1);
    await _speakThen(id, _q.clues.first);
  }

  /// 💡: the next clue.
  Future<void> _hint() async {
    if (_asking ||
        _phase == _Phase.result ||
        _over ||
        _introPlaying ||
        !_moreClues) {
      return;
    }
    final id = ++_flow;
    setState(() => _given++);
    await _speakThen(id, _q.clues[_given - 1]);
  }

  /// 🔊: every clue said so far, once more.
  Future<void> _repeat() async {
    if (_asking ||
        _phase == _Phase.result ||
        _over ||
        _introPlaying ||
        _given == 0) {
      return;
    }
    final id = ++_flow;
    await _speakThen(id, _q.clues.take(_given).join(' '));
  }

  Future<void> _tap(Phrase p) async {
    if (_asking || _phase == _Phase.result || _over || _wrong.contains(p)) {
      return;
    }
    if (_introPlaying || _given == 0) return;
    final id = ++_flow;
    if (p == _q.answer) {
      final first = _wrong.isEmpty;
      setState(() {
        _phase = _Phase.result;
        _results[_index] = first;
      });
      unawaited(_sound(jingle(first ? 3 : 2, _rng)));
      // right after a wrong tap: still right, a "well done" (not "almost")
      final praise = pickPraise(_lang, first ? 3 : 2, _rng, avoid: _lastPraise);
      _lastPraise = praise;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!_current(id)) return;
      // why it is right, if there is more to say than the word
      final because = _q.because;
      await _say(
        because == null ? '${p.text}! $praise' : '${p.text}! $because $praise',
      );
      if (!_current(id)) return;
      _onward = Timer(const Duration(milliseconds: 600), _next);
      return;
    }
    // wrong: what the child tapped, then the next clue (or the last one
    // again)
    // the next clue is due at once: 🔊 or another tap meanwhile keep it
    setState(() {
      _wrong.add(p);
      if (_moreClues) _given++;
      _phase = _Phase.speaking;
    });
    unawaited(_sound(jingle(0, _rng)));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!_current(id)) return;
    await _say(p.text);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!_current(id)) return;
    await _speakThen(id, _q.clues[_given - 1]);
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
    setState(() {
      _index++;
      _given = 0;
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
      final progress = widget.app.progress;
      record = await progress.recordThink(widget.game.name, _lang, stars);
    } catch (e, st) {
      debugPrint('saving the thinking record failed: $e\n$st');
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

  bool get _reportsOn =>
      widget.app.feedback != null && widget.app.progress.quizReports;

  /// What a 🐞 report says about the current question.
  String _describe() {
    final q = _q;
    final said = _given == 0 ? q.clues.take(1) : q.clues.take(_given);
    return [
      'Game: ${widget.game.name} ($_lang), '
          'question ${_index + 1} of ${_round.length}',
      'Said: ${said.join(' ')}',
      if (q.clues.length > said.length)
        'Not said yet: ${q.clues.skip(said.length).join(' ')}',
      'Pictures: ${q.options.map((o) => '${o.emoji} ${o.text}').join(', ')}',
      'Answer: ${q.answer.emoji} ${q.answer.text}',
      if (_wrong.isNotEmpty)
        'Tapped: ${_wrong.map((o) => '${o.emoji} ${o.text}').join(', ')}',
      if (_phase == _Phase.result) 'Solved',
    ].join('\n');
  }

  /// 🐞: holds the game, asks (with room for a note), then puts the
  /// current question into the feedback outbox.
  Future<void> _report() async {
    final outbox = widget.app.feedback;
    if (outbox == null ||
        _asking ||
        _reporting ||
        _over ||
        _reported.contains(_index)) {
      return;
    }
    final index = _index;
    final about = _describe();
    // hold at once: no taps, nothing said while the grown-up reads
    setState(() {
      _asking = true;
      if (_phase == _Phase.speaking) _phase = _Phase.choosing;
    });
    _flow++;
    _onward?.cancel();
    String? note;
    var info = <String, String>{};
    try {
      await _quietly(_tts.stop);
      await _quietly(_sfx.stop);
      Map<String, String> device;
      try {
        device = await widget.info();
      } catch (_) {
        device = const {};
      }
      if (!mounted) return;
      final uiLang = Localizations.maybeLocaleOf(context)?.languageCode ?? '';
      info = {...device, 'studyLang': _lang, 'uiLang': uiLang};
      note = await _askReport(about, info);
    } finally {
      _asking = false;
      if (mounted) setState(() => _reporting = note != null);
    }
    if (!mounted) return;
    _goOn();
    if (note == null) return;
    final report = FeedbackReport(
      id: FeedbackReport.newId(math.Random.secure()),
      kind: FeedbackKind.bug,
      text: note.isEmpty ? about : '$note\n\n$about',
      info: info,
      created: DateTime.now(),
    );
    ReportState state;
    try {
      state = await outbox.add(report);
    } catch (e, st) {
      debugPrint('think report failed: $e\n$st');
      state = ReportState.rejected;
    }
    if (!mounted) return;
    final s = S.of(context);
    setState(() {
      _reporting = false;
      // rejected: may be tried again
      if (state != ReportState.rejected) _reported.add(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (state) {
          ReportState.sent => s.quizReportSent,
          ReportState.waiting => s.feedbackQueued,
          ReportState.rejected => s.tryAgain,
        }),
      ),
    );
  }

  /// After the report dialog: the game goes on where it was held (the
  /// clues so far once more, or on to the next question).
  void _goOn() {
    if (_over || _paused || !mounted) return;
    if (_phase == _Phase.result) {
      _onward = Timer(const Duration(milliseconds: 600), _next);
    } else if (_given > 0) {
      unawaited(_repeat());
    }
  }

  /// The dialog before a report: what is sent and a note. Null: not sent.
  Future<String?> _askReport(String about, Map<String, String> info) =>
      showDialog<String>(
        context: context,
        // closes with the game page
        useRootNavigator: false,
        builder: (_) => _ReportDialog(about: about, info: info),
      );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF14143A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(switch (widget.game) {
          ThinkGame.needs => s.needsTitle,
          ThinkGame.riddle => s.riddleTitle,
          ThinkGame.odd => s.oddTitle,
          ThinkGame.home => s.homeTitle,
          ThinkGame.faces => s.facesTitle,
          ThinkGame.feelings => s.feelingsTitle,
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
                  _clue(),
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

  /// The latest clue, small: for those who can read along. With a place
  /// ("Who lives here?"), its picture big before it.
  Widget _clue() {
    final text = _given == 0 ? '' : _q.clues[_given - 1];
    final landscape = MediaQuery.sizeOf(context).height < 500;
    final scene = _q.scene;
    final clue = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SizedBox(
        height: landscape ? 28 : 56,
        child: LayoutBuilder(
          builder: (context, c) => FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: c.maxWidth,
              child: Text(
                text,
                key: const ValueKey('think-clue'),
                textAlign: TextAlign.center,
                style: _text.copyWith(fontSize: 20),
              ),
            ),
          ),
        ),
      ),
    );
    if (scene == null) return clue;
    // landscape: no room above, the place beside the question
    if (landscape) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 16),
          EmojiImage(scene, key: const ValueKey('think-scene'), size: 36),
          Expanded(child: clue),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: EmojiImage(
            scene,
            key: const ValueKey('think-scene'),
            // a small phone: the pictures need the room
            size: MediaQuery.sizeOf(context).height < 700 ? 96 : 120,
          ),
        ),
        clue,
      ],
    );
  }

  /// The pictures: in one row when wide, else 2 x 2 (or 3 in a row).
  Widget _options() => LayoutBuilder(
    builder: (context, c) {
      final n = _q.options.length;
      final wide = c.maxWidth > c.maxHeight * 1.6;
      // three in portrait: two and one below, bigger than three in a row
      final perRow = wide ? n : 2;
      final rows = (n / perRow).ceil();
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
        key: ValueKey('think-option-$i'),
        color: color,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _tap(o),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Expanded(
                  flex: 3,
                  child: FittedBox(child: EmojiImage(o.emoji, size: 160)),
                ),
                if (result && isAnswer)
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(o.text, style: _text.copyWith(fontSize: 24)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(S s) {
    final result = _phase == _Phase.result;
    final canHint = !result && !_introPlaying && _given > 0 && _moreClues;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        RoundButton(
          key: const ValueKey('think-repeat'),
          tooltip: s.listen,
          color: const Color(0xFF3B82F6),
          onTap: result ? null : _repeat,
          dimmed: result,
          child: const EmojiImage('🔊', size: 40),
        ),
        if (_riddle)
          RoundButton(
            key: const ValueKey('think-hint'),
            tooltip: s.hint,
            color: const Color(0xFFF59E0B),
            onTap: canHint ? _hint : null,
            child: const Icon(
              Icons.lightbulb_rounded,
              color: Colors.white,
              size: 40,
            ),
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
        if (_reportsOn)
          RoundButton(
            key: const ValueKey('think-report'),
            tooltip: s.quizReportSend,
            color: const Color(0xFF6D4C41),
            onTap:
                !_asking &&
                    !_reporting &&
                    !_over &&
                    _given > 0 &&
                    !_reported.contains(_index)
                ? _report
                : null,
            child: _reporting
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : const EmojiImage('🐞', size: 40),
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

/// Asks before a 🐞 report: what is sent, and a note to type. Pops the
/// note (maybe empty) on "Send", null on "Cancel". Owns the note's
/// controller: it must live until the dialog has faded out.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.about, required this.info});

  final String about;

  /// Sent too: app, phone, languages.
  final Map<String, String> info;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.thinkReportAsk),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.about),
            const SizedBox(height: 12),
            Text(s.feedbackSends, style: Theme.of(context).textTheme.bodySmall),
            for (final e in widget.info.entries)
              Text(
                '${e.key}: ${e.value}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('think-report-note'),
              controller: _note,
              maxLines: 3,
              minLines: 1,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: s.thinkReportNote,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          key: const ValueKey('think-report-send'),
          onPressed: () => Navigator.of(context).pop(_note.text.trim()),
          child: Text(s.send),
        ),
      ],
    );
  }
}
