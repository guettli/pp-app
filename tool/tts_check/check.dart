// Automatic pronunciation check of the word list (see README).
//
//   dart run tool/tts_check/check.dart features <work dir>
//   dart run tool/tts_check/check.dart score <work dir> <tokens.txt> <out.json>
//
// "features" runs the app's silence trimming and fbank on every synthesized
// word; "score" decodes the model output (tool/tts_check/infer.py) and scores
// it exactly like the game does.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:phoneme_party/phonetics/audio.dart';
import 'package:phoneme_party/phonetics/ctc_decoder.dart';
import 'package:phoneme_party/phonetics/fbank.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';

Float32List _readF32(String path) =>
    File(path).readAsBytesSync().buffer.asFloat32List();

String _with(String path, String ext) =>
    path.replaceFirst(RegExp(r'\.f32$'), ext);

void main(List<String> args) {
  final work = args[1];
  final index = (jsonDecode(File('$work/index.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  if (args[0] == 'features') {
    for (final item in index) {
      final f = '$work/${item['file']}';
      final feats = extractFbank(trimSilence(_readF32(f)));
      File(_with(f, '.fb')).writeAsBytesSync(feats.buffer.asUint8List());
    }
    return;
  }
  final tokens = parseTokens(File(args[2]).readAsStringSync());
  final comparer = PhonemeComparer.fromJson(
    File('assets/panphon/panphon_features.json').readAsStringSync(),
  );
  final out = <Map<String, dynamic>>[];
  for (final item in index) {
    final f = '$work/${item['file']}';
    var recognized = '';
    final shape = File(_with(f, '.shape'));
    if (shape.existsSync()) {
      final tv = shape.readAsStringSync().split(' ').map(int.parse).toList();
      final lp = _readF32(_with(f, '.lp')).map((e) => e.toDouble()).toList();
      recognized = decodeCtc(lp, tv[0], tv[1], tokens).map((p) => p.symbol).join();
    }
    final c = comparer.compare(item['ipa'] as String, recognized, item['lang'] as String);
    out.add({
      for (final k in ['lang', 'voice', 'p', 'e', 'ipa']) k: item[k],
      'recognized': recognized,
      'score': double.parse(c.score.toStringAsFixed(3)),
      'stars': c.stars,
    });
  }
  File(args[3]).writeAsStringSync(
    '${const JsonEncoder.withIndent(' ').convert(out)}\n',
  );
}
