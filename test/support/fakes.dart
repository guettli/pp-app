// Fake microphone, TTS, players and recognizer for running the play screen
// without a device. Every device writes to one [IoLog], so a test can check
// what was audible when, e.g. that nothing played while the mic was open.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:phoneme_party/net/feedback.dart' show SendResult;
import 'package:phoneme_party/net/quiz_report.dart';
import 'package:phoneme_party/game/game_io.dart';
import 'package:phoneme_party/phonetics/ctc_decoder.dart';
import 'package:phoneme_party/phonetics/recognizer.dart';

class IoEvent {
  IoEvent(this.at, this.device, this.on, this.detail);
  final Duration at;
  final String device;

  /// true: the device started (playing, speaking, recording); false: ended.
  final bool on;
  final String detail;

  @override
  String toString() =>
      '${at.inMilliseconds}ms $device ${on ? 'on' : 'off'} $detail';
}

/// [from] until [to] (null: still on).
typedef IoInterval = ({
  String device,
  Duration from,
  Duration? to,
  String what,
});

class IoLog {
  IoLog(this.now);

  /// Time since the test started (the fake clock of the widget tester).
  final Duration Function() now;
  final events = <IoEvent>[];

  void on(String device, [String detail = '']) {
    events.add(IoEvent(now(), device, true, detail));
    _on.add(device);
  }

  void off(String device) {
    events.add(IoEvent(now(), device, false, ''));
    _on.remove(device);
    if (!audible) quietSince = now();
  }

  /// When the app's last sound ended.
  Duration quietSince = Duration.zero;

  final _on = <String>{};

  /// Whether something the app plays is on now (the microphone hears it).
  bool get audible => _on.any((d) => d != 'mic');

  /// Things a fake noticed that the real device would get wrong, e.g. a
  /// TTS call that Android would drop.
  final problems = <String>[];
  void problem(String what) => problems.add('${now().inMilliseconds}ms $what');

  List<IoInterval> intervals([String? device]) {
    final open = <String, IoEvent>{};
    final out = <IoInterval>[];
    for (final e in events) {
      if (device != null && e.device != device) continue;
      if (e.on) {
        open[e.device] = e;
      } else {
        final s = open.remove(e.device);
        if (s != null) {
          out.add((device: e.device, from: s.at, to: e.at, what: s.detail));
        }
      }
    }
    for (final s in open.values) {
      out.add((device: s.device, from: s.at, to: null, what: s.detail));
    }
    out.sort((a, b) => a.from.compareTo(b.from));
    return out;
  }

  /// What a device started, in order (e.g. the texts the TTS said).
  List<String> started(String device) => [
    for (final e in events)
      if (e.device == device && e.on) e.detail,
  ];

  /// Sounds (TTS, players) that were on while the microphone recorded.
  /// A sound of [startedBefore] (the phrase) may overlap a recording that
  /// it started before; one that starts during the recording may not.
  List<String> soundsWhileRecording({Set<String> startedBefore = const {}}) {
    final mics = intervals('mic');
    final sounds = intervals().where((i) => i.device != 'mic');
    final end = now();
    return [
      for (final m in mics)
        for (final s in sounds)
          if (s.from < (m.to ?? end) &&
              m.from < (s.to ?? end) &&
              !(startedBefore.contains(s.device) && s.from <= m.from))
            '${s.device} "${s.what}" ${s.from.inMilliseconds}-'
                '${s.to?.inMilliseconds} during mic ${m.from.inMilliseconds}-'
                '${m.to?.inMilliseconds}',
    ];
  }

  /// Notes a problem if [audio] (what the game scores) contains what the
  /// microphone heard of the app's own sounds: [FakeMic] records those
  /// as a constant level ([FakeMic.echoLevel]), which no voice has.
  void checkNoEcho(Float32List audio) {
    var run = 0;
    for (var i = 1; i < audio.length; i++) {
      run = audio[i] == audio[i - 1] && audio[i].abs() > 0.05 ? run + 1 : 0;
      if (run >= 160) {
        problem('the game scored its own sound (${audio.length} samples)');
        return;
      }
    }
  }

  @override
  String toString() => events.join('\n');
}

/// What the child does in one recording.
enum Child {
  /// Says something (a tone of 0.7 s after a short pause).
  speaks,

  /// Answers at once: a tone of 0.7 s from 150 ms (a quick reaction)
  /// after the app's last sound ended, whenever the microphone opened.
  speaksAtOnce,

  /// Says nothing.
  silent,

  /// Speaks, then the recording breaks (the stream reports an error and
  /// ends, as when another app takes the microphone).
  micBreaks,

  /// Speaks, then the stream just ends (no error).
  micEnds,
}

/// Streams 20 ms chunks of 16 kHz PCM in (fake) real time. While the app
/// plays something ([IoLog.audible]) the microphone hears that, as a
/// constant [echoLevel]; the child's time line ([Child]) runs only while
/// nothing plays, so the child answers after the phone has spoken.
class FakeMic implements MicSource {
  static const echoLevel = 0.6;

  FakeMic(this.log, this.child, {this.permission = true});

  final IoLog log;

  /// Called on every start: what the child does this time.
  final Child Function() child;
  bool permission;
  StreamController<Uint8List>? _ctrl;
  Timer? _timer;

  bool get recording => _ctrl != null;

  /// [hasPermission] throws (a broken platform channel).
  bool permissionThrows = false;

  /// How long [start] takes (the real one opens the audio device).
  Duration startup = Duration.zero;

  @override
  Future<bool> hasPermission() async {
    if (permissionThrows) throw StateError('no permission service');
    return permission;
  }

  /// What the last start asked for.
  bool? voiceProcessing;

  /// If set, each start plays these samples (then silence) instead of
  /// [child].
  List<double> Function()? script;

  /// The next starts fail (the audio device cannot be opened).
  bool startThrows = false;

  /// Audio arrives this much after it was heard (the platform's buffers),
  /// so the end of a sound still arrives after the sound stopped.
  Duration latency = Duration.zero;

  /// The stream ends by itself this long after the start (whatever the
  /// child does).
  Duration? endsAfter;

  /// The child starts this much later (thinks, reads) before speaking.
  Duration speechDelay = Duration.zero;

  @override
  Future<Stream<Uint8List>> start({bool voiceProcessing = true}) async {
    await stop();
    if (startup > Duration.zero) await Future<void>.delayed(startup);
    if (startThrows) throw StateError('microphone cannot be opened');
    this.voiceProcessing = voiceProcessing;
    final audio = script?.call();
    if (audio != null) return _play(audio);
    final what = child();
    // onCancel: without it, cancel() returns a root-zone future that the
    // fake clock never completes
    final ctrl = _ctrl = StreamController<Uint8List>(onCancel: () async {});
    log.on('mic', what.name);
    var t = 0; // ms of the child's time: only while nothing plays
    var micMs = 0;
    final queue = <Uint8List>[];
    void emit(Uint8List chunk) {
      queue.add(chunk);
      if (queue.length > latency.inMilliseconds ~/ 20) {
        ctrl.add(queue.removeAt(0));
      }
    }

    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      micMs += 20;
      final end = endsAfter;
      if (end != null && micMs > end.inMilliseconds) {
        stop();
        return;
      }
      if (log.audible) {
        emit(_echo());
        return;
      }
      if (t == 1200 && (what == Child.micBreaks || what == Child.micEnds)) {
        if (what == Child.micBreaks) {
          ctrl.addError(StateError('microphone taken'));
        }
        stop();
        return;
      }
      emit(
        _chunk(
          what,
          what == Child.speaksAtOnce
              ? (log.now() - log.quietSince).inMilliseconds
              : t - speechDelay.inMilliseconds,
        ),
      );
      t += 20;
    });
    return ctrl.stream;
  }

  Stream<Uint8List> _play(List<double> audio) {
    final ctrl = _ctrl = StreamController<Uint8List>(onCancel: () async {});
    log.on('mic', 'script');
    var pos = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final b = ByteData(640);
      for (var i = 0; i < 320; i++, pos++) {
        final v = pos < audio.length ? audio[pos] : 0.0;
        b.setInt16(i * 2, (v.clamp(-1, 1) * 32767).round(), Endian.little);
      }
      ctrl.add(b.buffer.asUint8List());
    });
    return ctrl.stream;
  }

  static Uint8List _echo() {
    final b = ByteData(640);
    for (var i = 0; i < 320; i++) {
      b.setInt16(i * 2, (echoLevel * 32767).round(), Endian.little);
    }
    return b.buffer.asUint8List();
  }

  static Uint8List _chunk(Child what, int ms) {
    const n = 320;
    final b = ByteData(n * 2);
    final rng = math.Random(ms);
    final speech = switch (what) {
      Child.silent => false,
      Child.speaksAtOnce => ms >= 150 && ms < 850,
      _ => ms >= 400 && ms < 1100,
    };
    for (var i = 0; i < n; i++) {
      final s = (ms * 16 + i) / 16000;
      var v = (rng.nextDouble() - 0.5) * 0.002;
      if (speech) v += 0.3 * math.sin(2 * math.pi * 220 * s);
      b.setInt16(i * 2, (v * 32767).round(), Endian.little);
    }
    return b.buffer.asUint8List();
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final c = _ctrl;
    _ctrl = null;
    if (c != null) {
      log.off('mic');
      // not awaited: after the listener cancelled, close() never completes
      unawaited(c.close());
    }
  }

  @override
  Future<void> dispose() => stop();

  /// How often the app was told the child is speaking (keeps the screen on).
  int voices = 0;

  @override
  void heardVoice() => voices++;
}

/// Speaks 60 ms per letter plus 300 ms, like flutter_tts with
/// awaitSpeakCompletion:
/// - [speak] while speaking is dropped and returns at once (Android,
///   QUEUE_FLUSH); noted as a problem, since the text is never heard.
/// - [stop] completes a running [speak] on Android, but not on iOS
///   ([completesOnStop] false): there the caller's timeout has to end it.
/// - [hang]: a stuck engine that never finishes.
class FakeSpeaker implements Speaker {
  FakeSpeaker(this.log, {this.completesOnStop = true, this.hang = false});

  final IoLog log;
  final bool completesOnStop;
  bool hang;
  Completer<void>? _done;
  Timer? _timer;
  String? language;

  bool get speaking => _done != null;

  @override
  Future<void> setLanguage(String lang) async => language = lang;

  /// The pitch of each [speak], in order.
  final pitches = <double>[];

  /// [speak] throws (no voice for the language).
  bool failSpeak = false;

  @override
  Future<void> speak(String text, {double pitch = 1}) {
    if (failSpeak) return Future.error(StateError('no voice'));
    pitches.add(pitch);
    if (speaking) {
      log.problem('tts dropped "$text": still speaking');
      return Future.value();
    }
    final done = _done = Completer<void>();
    log.on('tts', text);
    if (!hang) {
      _timer = Timer(Duration(milliseconds: 300 + 60 * text.length), () {
        _end(complete: true);
      });
    }
    return done.future;
  }

  void _end({required bool complete}) {
    _timer?.cancel();
    _timer = null;
    final d = _done;
    _done = null;
    if (d != null) {
      log.off('tts');
      if (complete) d.complete();
    }
  }

  /// [stop] throws (an engine that broke).
  bool failStop = false;

  @override
  Future<void> stop() async {
    if (failStop) throw StateError('tts engine gone');
    _end(complete: completesOnStop);
  }
}

/// Plays as long as the WAV lasts (16 kHz mono 16-bit, 44 byte header).
class FakeOut implements SoundOut {
  FakeOut(this.log, this.name, {this.playsFromMemory = true});

  final IoLog log;
  final String name;
  @override
  final bool playsFromMemory;
  final _complete = StreamController<void>.broadcast();
  Timer? _timer;
  int plays = 0;

  /// Like audioplayers, the player takes a moment to prepare; a [stop]
  /// meanwhile cancels the start.
  static const startup = Duration(milliseconds: 100);
  bool starting = false;
  bool _cancelStart = false;

  @override
  Future<void> play(Uint8List wav) async {
    await stop();
    plays++;
    starting = true;
    _cancelStart = false;
    await Future<void>.delayed(startup);
    starting = false;
    if (_cancelStart) return;
    final ms = (wav.length - 44) ~/ 2 * 1000 ~/ 16000;
    log.on(name, '${ms}ms');
    _timer = Timer(Duration(milliseconds: ms), () {
      _timer = null;
      log.off(name);
      _complete.add(null);
    });
  }

  @override
  Future<void> stop() async {
    if (starting) _cancelStart = true;
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    log.off(name);
  }

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  Future<void> dispose() async {
    await stop();
    await _complete.close();
  }
}

/// Answers with the IPA [answer] gives (e.g. the target: 3 stars).
class FakeRecognizer implements Recognizer {
  FakeRecognizer(this.answer, {this.delay = Duration.zero, this.log});

  /// If set, every scored recording is checked for the app's own sounds.
  final IoLog? log;

  /// Seconds of audio of the last call.
  double lastSeconds = 0;

  /// Seconds of the child's voice in the last call (its samples are well
  /// above the faint noise of [FakeMic]).
  double lastSpeechSeconds = 0;

  final String Function() answer;

  /// How long recognition takes.
  final Duration delay;
  int calls = 0;

  @override
  Future<Recognition> recognize(Float32List audio) async {
    calls++;
    lastSeconds = audio.length / 16000;
    lastSpeechSeconds = audio.where((v) => v.abs() > 0.05).length / 16000;
    log?.checkNoEcho(audio);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final ipa = answer();
    final symbols = [for (final r in ipa.runes) String.fromCharCode(r)];
    // one model frame per symbol, one after the other
    return Recognition([
      for (final (i, s) in symbols.indexed) DecodedPhoneme(s, 1, 1, start: i),
    ], frames: symbols.length);
  }
}

/// All fakes of one test, wired into a [GameIo].
class FakeDevices {
  FakeDevices(
    this.log, {
    Child Function()? child,
    bool fromMemory = true,
    bool ttsCompletesOnStop = true,
    this.listensWhileSpeaking = true,
  }) : mic = FakeMic(log, child ?? () => Child.speaks),
       speaker = FakeSpeaker(log, completesOnStop: ttsCompletesOnStop),
       player = FakeOut(log, 'replay', playsFromMemory: fromMemory),
       sfx = FakeOut(log, 'sfx', playsFromMemory: fromMemory);

  final IoLog log;
  final bool listensWhileSpeaking;
  final FakeMic mic;
  final FakeSpeaker speaker;
  final FakeOut player;
  final FakeOut sfx;

  GameIo get io => GameIo(
    mic: () => mic,
    speaker: () => speaker,
    replayPlayer: () => player,
    soundPlayer: () => sfx,
    random: () => math.Random(1),
    listensWhileSpeaking: listensWhileSpeaking,
    info: () async => {'phone': 'test'},
  );
}

/// Takes 🐞 recording reports.
class FakeQuizReports implements QuizReportSender {
  final sent = <QuizReport>[];
  SendResult result = SendResult.done;

  @override
  Future<SendResult> send(QuizReport report) async {
    sent.add(report);
    return result;
  }
}
