// On-device phone recognition: 16 kHz PCM -> fbank -> ZIPA (ONNX) -> IPA.
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'ctc_decoder.dart';
import 'fbank.dart';

class Recognition {
  Recognition(this.phonemes);
  final List<DecodedPhoneme> phonemes;
  String get ipa => phonemes.map((p) => p.symbol).join();
}

class PhoneRecognizer {
  PhoneRecognizer._(this._session, this._tokens);

  static const modelAsset = 'assets/models/model.onnx';
  static const tokensAsset = 'assets/models/tokens.txt';

  final OrtSession _session;
  final Map<int, String> _tokens;

  static Future<PhoneRecognizer> load() async {
    final tokens = parseTokens(await rootBundle.loadString(tokensAsset));
    final session = await OnnxRuntime().createSessionFromAsset(
      modelAsset,
      options: OrtSessionOptions(intraOpNumThreads: 2),
    );
    return PhoneRecognizer._(session, tokens);
  }

  /// [audio]: mono 16 kHz samples in [-1, 1].
  Future<Recognition> recognize(Float32List audio) async {
    final feats = extractFbank(audio);
    final frames = feats.length ~/ numMelBins;
    if (frames < 10) return Recognition(const []);
    final x = await OrtValue.fromList(feats, [1, frames, numMelBins]);
    final xLens = await OrtValue.fromList(Int64List.fromList([frames]), [1]);
    final outputs = await _session.run({'x': x, 'x_lens': xLens});
    try {
      final out =
          outputs['log_probs'] ?? outputs['logits'] ?? outputs.values.first;
      final data = (await out.asFlattenedList())
          .cast<num>()
          .map((e) => e.toDouble())
          .toList();
      final t = out.shape[1], v = out.shape[2];
      return Recognition(decodeCtc(data, t, v, _tokens));
    } finally {
      await x.dispose();
      await xLens.dispose();
      for (final o in outputs.values) {
        await o.dispose();
      }
    }
  }

  Future<void> close() => _session.close();
}

/// Converts little-endian 16-bit PCM bytes to floats in [-1, 1].
Float32List pcm16ToFloat(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final view = ByteData.sublistView(bytes);
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Cuts leading/trailing silence (keeps 150 ms margin) so the model sees
/// mostly speech. Returns the input unchanged if no speech is found.
Float32List trimSilence(Float32List audio, {double threshold = 0.02}) {
  const win = 320; // 20 ms
  int? first, last;
  for (var s = 0; s + win <= audio.length; s += win) {
    var e = 0.0;
    for (var i = s; i < s + win; i++) {
      e += audio[i] * audio[i];
    }
    if (e / win > threshold * threshold) {
      first ??= s;
      last = s + win;
    }
  }
  if (first == null) return audio;
  const margin = 2400;
  final a = (first - margin).clamp(0, audio.length);
  final b = (last! + margin).clamp(0, audio.length);
  return Float32List.sublistView(audio, a, b);
}
