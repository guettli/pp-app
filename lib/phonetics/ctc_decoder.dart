// Greedy CTC decoding of ZIPA log-probabilities into IPA phonemes.
//
// Ported from guettli/pp src/speech/phoneme-decoder.ts, including the
// heuristics tuned there on real recordings:
//  * similar vowels that the model splits probability between are merged
//    into classes before picking the winner of a frame,
//  * single-frame phonemes below a per-class confidence threshold are dropped
//    (they are mostly noise).
import 'dart:math' as math;

class DecodedPhoneme {
  DecodedPhoneme(this.symbol, this.confidence, this.frames);
  final String symbol;
  final double confidence;
  final int frames;

  @override
  String toString() => '$symbol(${confidence.toStringAsFixed(2)}x$frames)';
}

const List<Set<String>> _classes = [
  {'e', 'ɛ', 'æ'},
  {'o', 'ɔ'},
  {'a', 'ɑ'},
  {'i', 'ɪ'},
  {'u', 'ʊ'},
  {'ø', 'ʏ', 'œ', 'y'},
  {'ɜ', 'ɜ˞'},
  {'ʁ', 'ʀ'},
];

const _veryWeak = {'ə', 'ɐ', 'w', 'j', 'ʋ', 'ɹ', 'ɻ'};
const _fricatives = {
  'f', 'v', 's', 'z', 'ʃ', 'ʒ', 'θ', 'ð', 'x', 'ç', 'h', 'ʁ', 'ʀ', //
};
const _stops = {'p', 'b', 't', 'd', 'k', 'g', 'ɡ', 'ʔ'};

double _threshold(String s, double base) {
  if (_veryWeak.contains(s)) return base * 0.7;
  if (_fricatives.contains(s)) return base * 0.72;
  if (_stops.contains(s)) return base * 0.8;
  return base;
}

/// Token table from ZIPA's tokens.txt (`<symbol> <id>` per line).
Map<int, String> parseTokens(String tokensTxt) {
  final map = <int, String>{};
  for (final line in tokensTxt.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    final i = t.lastIndexOf(' ');
    if (i <= 0) continue;
    map[int.parse(t.substring(i + 1))] = t.substring(0, i);
  }
  return map;
}

bool _isSpecial(int id, String sym) =>
    id == 0 || sym == '<blk>' || sym == '▁' || sym.startsWith('<');

/// [logProbs] is row-major (frames x vocab) log-softmax output.
List<DecodedPhoneme> decodeCtc(
  List<double> logProbs,
  int frames,
  int vocab,
  Map<int, String> tokens, {
  double minConfidence = 0.5,
}) {
  final classOf = <int, int>{};
  for (var v = 0; v < vocab; v++) {
    final s = tokens[v] ?? '';
    for (var c = 0; c < _classes.length; c++) {
      if (_classes[c].contains(s)) classOf[v] = c;
    }
  }

  final ids = List<int>.filled(frames, 0);
  final confs = List<double>.filled(frames, 0);
  final classSum = List<double>.filled(_classes.length, 0);
  final classBest = List<int>.filled(_classes.length, -1);
  for (var t = 0; t < frames; t++) {
    classSum.fillRange(0, classSum.length, 0);
    classBest.fillRange(0, classBest.length, -1);
    final nonBlank = <double>[];
    var bestId = 0;
    var bestP = -1.0;
    for (var v = 0; v < vocab; v++) {
      final p = math.exp(logProbs[t * vocab + v]);
      final c = classOf[v];
      if (c != null) {
        classSum[c] += p;
        if (classBest[c] < 0 ||
            p > math.exp(logProbs[t * vocab + classBest[c]])) {
          classBest[c] = v;
        }
      } else {
        if (p > bestP) {
          bestP = p;
          bestId = v;
        }
        if (!_isSpecial(v, tokens[v] ?? '')) nonBlank.add(p);
      }
    }
    for (var c = 0; c < _classes.length; c++) {
      if (classBest[c] >= 0) {
        nonBlank.add(classSum[c]);
        if (classSum[c] > bestP) {
          bestP = classSum[c];
          bestId = classBest[c];
        }
      }
    }
    // When probability is spread over a few phonemes, the top-3 sum shows
    // that there is real speech even if no single phoneme is confident.
    nonBlank.sort((a, b) => b.compareTo(a));
    final top3 = nonBlank.take(3).fold<double>(0, (a, b) => a + b);
    final blankWins = _isSpecial(bestId, tokens[bestId] ?? '');
    final dominant = top3 > 0 && bestP / top3 > 0.4;
    ids[t] = bestId;
    confs[t] = !blankWins && top3 > 0.5 && dominant ? top3 : bestP;
  }

  // Collapse runs, drop blanks, filter short low-confidence blips, then
  // merge duplicates that were separated by blanks ("n <blk> n" -> "n").
  final result = <DecodedPhoneme>[];
  var t = 0;
  while (t < frames) {
    var end = t;
    var sum = 0.0;
    while (end < frames && ids[end] == ids[t]) {
      sum += confs[end];
      end++;
    }
    final id = ids[t];
    final sym = tokens[id] ?? '';
    final n = end - t;
    final avg = sum / n;
    t = end;
    if (_isSpecial(id, sym)) continue;
    if (n == 1 && avg < _threshold(sym, minConfidence)) continue;
    if (result.isNotEmpty && result.last.symbol == sym) {
      final last = result.removeLast();
      final f = last.frames + n;
      result.add(
        DecodedPhoneme(sym, (last.confidence * last.frames + sum) / f, f),
      );
    } else {
      result.add(DecodedPhoneme(sym, avg, n));
    }
  }
  return result;
}
