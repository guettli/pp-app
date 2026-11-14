// Fake microphone, TTS, players and recognizer for running the play screen
// without a device. Every device writes to one [IoLog], so a test can check
// what was audible when, e.g. that nothing played while the mic was open.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

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
typedef Interval = ({String device, Duration from, Duration? to, String what});

class IoLog {
  IoLog(this.now);

  /// Time since the test started (the fake clock of the widget tester).
  final Duration Function() now;
  final events = <IoEvent>[];

  void on(String device, [String detail = '']) =>
      events.add(IoEvent(now(), device, true, detail));
  void off(String device) => events.add(IoEvent(now(), device, false, ''));

  List<Interval> intervals([String? device]) {
    final open = <String, IoEvent>{};
    final out = <Interval>[];
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
  List<String> soundsWhileRecording() {
    final mics = intervals('mic');
    final sounds = intervals().where((i) => i.device != 'mic');
    final end = now();
    return [
      for (final m in mics)
        for (final s in sounds)
          if (s.from < (m.to ?? end) && m.from < (s.to ?? end))
            '${s.device} "${s.what}" ${s.from.inMilliseconds}-'
                '${s.to?.inMilliseconds} during mic ${m.from.inMilliseconds}-'
                '${m.to?.inMilliseconds}',
    ];
  }

  @override
  String toString() => events.join('\n');
}

/// What the child does in one recording.
enum Child {
  /// Says something (a tone of 0.7 s after a short pause).
  speaks,

  /// Says nothing.
  silent,
}

/// Streams 20 ms chunks of 16 kHz PCM in (fake) real time.
class FakeMic implements MicSource {
  FakeMic(this.log, this.child, {this.permission = true});

  final IoLog log;

  /// Called on every start: what the child does this time.
  final Child Function() child;
  bool permission;
  StreamController<Uint8List>? _ctrl;
  Timer? _timer;

  bool get recording => _ctrl != null;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<Stream<Uint8List>> start() async {
    await stop();
    final what = child();
    // onCancel: without it, cancel() returns a root-zone future that the
    // fake clock never completes
    final ctrl = _ctrl = StreamController<Uint8List>(onCancel: () async {});
    log.on('mic', what.name);
    var t = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      ctrl.add(_chunk(what, t));
      t += 20;
    });
    return ctrl.stream;
  }

  static Uint8List _chunk(Child what, int ms) {
    const n = 320;
    final b = ByteData(n * 2);
    final rng = math.Random(ms);
    final speech = what == Child.speaks && ms >= 400 && ms < 1100;
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
      await c.close();
    }
  }

  @override
  Future<void> dispose() => stop();
}

/// Speaks 60 ms per letter plus 300 ms. With [hang], it never finishes
/// (a stuck TTS engine).
class FakeSpeaker implements Speaker {
  FakeSpeaker(this.log, {this.hang = false});

  final IoLog log;
  bool hang;
  Completer<void>? _done;
  Timer? _timer;
  String? language;

  @override
  Future<void> setLanguage(String lang) async => language = lang;

  @override
  Future<void> speak(String text) {
    _end();
    final done = _done = Completer<void>();
    log.on('tts', text);
    if (!hang) {
      _timer = Timer(Duration(milliseconds: 300 + 60 * text.length), _end);
    }
    return done.future;
  }

  void _end() {
    _timer?.cancel();
    _timer = null;
    final d = _done;
    _done = null;
    if (d != null) {
      log.off('tts');
      d.complete();
    }
  }

  @override
  Future<void> stop() async => _end();
}

/// Plays as long as the WAV lasts (16 kHz mono 16-bit, 44 byte header).
class FakeOut implements SoundOut {
  FakeOut(this.log, this.name);

  final IoLog log;
  final String name;
  final _complete = StreamController<void>.broadcast();
  Timer? _timer;
  int plays = 0;

  @override
  Future<void> play(Uint8List wav) async {
    await stop();
    plays++;
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
  FakeRecognizer(this.answer);

  final String Function() answer;
  int calls = 0;

  @override
  Future<Recognition> recognize(Float32List audio) async {
    calls++;
    final ipa = answer();
    return Recognition([
      for (final r in ipa.runes) DecodedPhoneme(String.fromCharCode(r), 1, 1),
    ]);
  }
}

/// All fakes of one test, wired into a [GameIo].
class FakeDevices {
  FakeDevices(this.log, {Child Function()? child, this.canReplay = true})
    : mic = FakeMic(log, child ?? () => Child.speaks),
      speaker = FakeSpeaker(log);

  final IoLog log;
  final FakeMic mic;
  final FakeSpeaker speaker;
  final bool canReplay;
  late final FakeOut player = FakeOut(log, 'replay');
  late final FakeOut sfx = FakeOut(log, 'sfx');

  GameIo get io => GameIo(
    mic: () => mic,
    speaker: () => speaker,
    player: ({bool duck = true}) => duck ? player : sfx,
    random: () => math.Random(1),
    canReplay: canReplay,
  );
}
