// On-device phone recognition: 16 kHz PCM -> fbank -> ZIPA (ONNX) -> IPA.
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'ctc_decoder.dart';
import 'fbank.dart';

export 'audio.dart';

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
    OrtValue? x, xLens;
    var outputs = <String, OrtValue>{};
    try {
      x = await OrtValue.fromList(feats, [1, frames, numMelBins]);
      xLens = await OrtValue.fromList(Int64List.fromList([frames]), [1]);
      outputs = await _session.run({'x': x, 'x_lens': xLens});
      final out =
          outputs['log_probs'] ?? outputs['logits'] ?? outputs.values.first;
      final data = (await out.asFlattenedList())
          .cast<num>()
          .map((e) => e.toDouble())
          .toList();
      final t = out.shape[1], v = out.shape[2];
      return Recognition(decodeCtc(data, t, v, _tokens));
    } finally {
      await x?.dispose();
      await xLens?.dispose();
      for (final o in outputs.values) {
        await o.dispose();
      }
    }
  }

  Future<void> close() => _session.close();
}
