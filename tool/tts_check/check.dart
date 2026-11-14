// Automatic pronunciation check of the word list (see README).
//
//   dart run tool/tts_check/check.dart features <work dir>
//   dart run tool/tts_check/check.dart score <work dir> <tokens.txt> <out.json>
//   dart run tool/tts_check/check.dart rescore <report.json> <out.json>
//
// "features" runs the app's silence trimming and fbank on every synthesized
// word; "score" decodes the model output (tool/tts_check/infer.py) and scores
// it exactly like the game does; "rescore" scores the recognitions of an
// existing report again (to see the effect of a change in the scoring).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:phoneme_party/phonetics/audio.dart';
import 'package:phoneme_party/phonetics/ctc_decoder.dart';
import 'package:phoneme_party/phonetics/endpointer.dart';
import 'package:phoneme_party/phonetics/fbank.dart';
import 'package:phoneme_party/phonetics/phoneme_distance.dart';

Float32List _readF32(String path) =>
    File(path).readAsBytesSync().buffer.asFloat32List();

String _with(String path, String ext) =>
    path.replaceFirst(RegExp(r'\.f32$'), ext);

/// Plays [audio] to the app's [Endpointer] in 100 ms chunks like the
/// recorder does: returns the audio up to where the app stops recording, or
/// null if the app would not hear speech at all.
Float32List? _endpoint(Float32List audio) {
  final ep = Endpointer();
  const chunk = 1600;
  var end = audio.length;
  for (var i = 0; i < audio.length; i += chunk) {
    final j = i + chunk < audio.length ? i + chunk : audio.length;
    ep.add(Float32List.sublistView(audio, i, j));
    if (ep.done) {
      end = j;
      break;
    }
  }
  return ep.heardSpeech ? Float32List.sublistView(audio, 0, end) : null;
}

/// Best match over the word and its alternatives, like scorePhrase in
/// lib/game/rules.dart (which needs Flutter, so it is not imported here).
Comparison _score(
  PhonemeComparer comparer,
  Map<String, dynamic> item,
  String recognized,
) {
  Comparison? best;
  for (final ipa in [item['ipa'] as String, ...?(item['alt'] as List?)?.cast<String>()]) {
    final c = comparer.compare(ipa, recognized, item['lang'] as String);
    if (best == null || c.score > best.score) best = c;
  }
  return best!;
}

PhonemeComparer _comparer() => PhonemeComparer.fromJson(
  File('assets/panphon/panphon_features.json').readAsStringSync(),
);

void _write(String path, List<Map<String, dynamic>> rows) => File(
  path,
).writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(rows)}\n');

void main(List<String> args) {
  if (args[0] == 'rescore') {
    final comparer = _comparer();
    final rows = (jsonDecode(File(args[1]).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    for (final r in rows) {
      if (r['notHeard'] == true) continue;
      final c = _score(comparer, r, r['recognized'] as String);
      r['score'] = double.parse(c.score.toStringAsFixed(3));
      r['stars'] = c.stars;
    }
    _write(args[2], rows);
    return;
  }
  final work = args[1];
  final index = (jsonDecode(File('$work/index.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  if (args[0] == 'features') {
    for (final item in index) {
      final f = '$work/${item['file']}';
      final audio = _endpoint(_readF32(f));
      if (audio == null) {
        // the app would say "nothing heard" and not score it
        File(_with(f, '.notheard')).writeAsStringSync('');
        continue;
      }
      final feats = extractFbank(prepareForRecognition(audio));
      File(_with(f, '.fb')).writeAsBytesSync(feats.buffer.asUint8List());
    }
    return;
  }
  final tokens = parseTokens(File(args[2]).readAsStringSync());
  final comparer = _comparer();
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
    final notHeard = File(_with(f, '.notheard')).existsSync();
    final c = _score(comparer, item, recognized);
    out.add({
      for (final k in ['lang', 'voice', 'p', 'e', 'ipa', 'alt']) k: item[k],
      'notHeard': notHeard,
      'recognized': recognized,
      'score': notHeard ? 0.0 : double.parse(c.score.toStringAsFixed(3)),
      'stars': notHeard ? 0 : c.stars,
    });
  }
  _write(args[3], out);
}
