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

import '../net/device_info.dart';
import 'screen_awake.dart';

/// The microphone: 16 kHz mono little-endian 16-bit PCM.
abstract class MicSource {
  Future<bool> hasPermission();

  /// [voiceProcessing]: automatic gain and noise suppression, good for
  /// words. Off for the voice games: a long steady vowel would be taken
  /// for noise and faded out.
  Future<Stream<Uint8List>> start({bool voiceProcessing = true});
  Future<void> stop();
  Future<void> dispose();

  /// The child is speaking into the mic: counts like a touch, so the
  /// screen does not go off (see screen_awake.dart).
  void heardVoice();
}

/// Text to speech. [speak] completes when the text has been said.
abstract class Speaker {
  Future<void> setLanguage(String lang);

  /// [pitch]: 1 is normal, 0.5 very low, 2 very high.
  Future<void> speak(String text, {double pitch = 1});
  Future<void> stop();
}

/// Plays WAV bytes. [play] completes when playback started; [onComplete]
/// fires when it reached the end (not on [stop]).
abstract class SoundOut {
  /// Whether [play] keeps the bytes in memory. Only then may the child's
  /// recording be played: recordings must never be written anywhere.
  bool get playsFromMemory;

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
    required this.replayPlayer,
    required this.soundPlayer,
    required this.random,
    this.listensWhileSpeaking = false,
    this.info = deviceInfo,
  });

  /// The real devices.
  factory GameIo.device() => GameIo(
    mic: RecordMic.new,
    speaker: TtsSpeaker.new,
    replayPlayer: AudioPlayersOut.new,
    soundPlayer: () => AudioPlayersOut(takesFocus: false),
    random: math.Random.new,
    // Android records next to the TTS without changing how it sounds
    // (checked on the A80). iOS would switch the audio session to
    // play-and-record, which can move the voice to the earpiece: untested.
    listensWhileSpeaking: Platform.isAndroid,
  );

  final MicSource Function() mic;

  /// Open the microphone while the phone still says the phrase (see
  /// phonetics/echo_gate.dart); else only after it.
  final bool listensWhileSpeaking;
  final Speaker Function() speaker;

  /// Plays the child's voice back (funny voice).
  final SoundOut Function() replayPlayer;

  /// Melodies: may overlap the replay and must not pause the praise.
  final SoundOut Function() soundPlayer;
  final math.Random Function() random;

  /// App version, phone model and system version, for a report.
  final Future<Map<String, String>> Function() info;
}

class RecordMic implements MicSource {
  final _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start({bool voiceProcessing = true}) =>
      _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: voiceProcessing,
          noiseSuppress: voiceProcessing,
        ),
      );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();

  @override
  void heardVoice() => ScreenAwake.instance.voice();
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

  double _pitch = 1;

  @override
  Future<void> speak(String text, {double pitch = 1}) async {
    if (pitch != _pitch) {
      await _tts.setPitch(pitch);
      _pitch = pitch;
    }
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}

class AudioPlayersOut implements SoundOut {
  /// [takesFocus]: false for short sounds that must not pause other audio
  /// (Android audio focus none).
  AudioPlayersOut({bool takesFocus = true}) {
    if (!takesFocus) {
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

  /// Android plays a BytesSource from memory; on iOS (and elsewhere)
  /// audioplayers writes it to a temp file first.
  @override
  bool get playsFromMemory => Platform.isAndroid;

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
