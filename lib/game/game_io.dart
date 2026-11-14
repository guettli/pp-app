// What the game uses to hear and to make sounds, behind small interfaces,
// so tests can run the whole flow after a word with fakes instead of the
// microphone, the TTS engine and the audio players.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';

/// The microphone: 16 kHz mono little-endian 16-bit PCM.
abstract class MicSource {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> dispose();
}

/// Text to speech. [speak] completes when the text has been said.
abstract class Speaker {
  Future<void> setLanguage(String lang);
  Future<void> speak(String text);
  Future<void> stop();
}

/// Plays WAV bytes from memory. [play] completes when playback started;
/// [onComplete] fires when it reached the end.
abstract class SoundOut {
  Future<void> play(Uint8List wav);
  Future<void> stop();
  Stream<void> get onComplete;
  Future<void> dispose();
}

/// Creates the devices for one play screen.
class GameIo {
  const GameIo({
    required this.mic,
    required this.speaker,
    required this.player,
    required this.random,
    required this.canReplay,
  });

  /// The real devices.
  factory GameIo.device() => GameIo(
    mic: RecordMic.new,
    speaker: TtsSpeaker.new,
    player: AudioPlayersOut.new,
    random: math.Random.new,
    // Android plays the WAV from memory. audioplayers writes it to a temp
    // file on iOS, and recordings must not be stored, so no replay there.
    canReplay: Platform.isAndroid,
  );

  final MicSource Function() mic;
  final Speaker Function() speaker;

  /// [duck]: false for short sounds that must not pause other audio.
  final SoundOut Function({bool duck}) player;
  final math.Random Function() random;

  /// Whether the child's recording may be played back.
  final bool canReplay;
}

class RecordMic implements MicSource {
  final _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      autoGain: true,
      noiseSuppress: true,
    ),
  );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

class TtsSpeaker implements Speaker {
  TtsSpeaker() {
    _tts.setSpeechRate(0.4);
    // speak() completes when the phrase has been said
    _tts.awaitSpeakCompletion(true);
  }

  final _tts = FlutterTts();

  @override
  Future<void> setLanguage(String lang) async {
    await _tts.setLanguage(lang);
  }

  @override
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}

class AudioPlayersOut implements SoundOut {
  AudioPlayersOut({bool duck = true}) {
    if (!duck) {
      _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            audioFocus: AndroidAudioFocus.none,
          ),
        ),
      );
    }
  }

  final _player = AudioPlayer();

  @override
  Future<void> play(Uint8List wav) =>
      _player.play(BytesSource(wav, mimeType: 'audio/wav'));

  @override
  Future<void> stop() => _player.stop();

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> dispose() => _player.dispose();
}
