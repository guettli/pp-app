import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/phonetics/ctc_decoder.dart';

void main() {
  final tokens = parseTokens(
    '<blk> 0\n<sos/eos> 1\n<unk> 2\n▁ 3\na 4\nn 5\nɛ 6\ne 7\nt 8\n',
  );
  const vocab = 9;

  /// Builds log-probs where each frame puts [p] on one token and spreads the
  /// rest evenly.
  List<double> frames(List<(int, double)> spec) {
    final out = <double>[];
    for (final (id, p) in spec) {
      for (var v = 0; v < vocab; v++) {
        out.add(math.log(v == id ? p : (1 - p) / (vocab - 1)));
      }
    }
    return out;
  }

  String decode(List<(int, double)> spec) => decodeCtc(
    frames(spec),
    spec.length,
    vocab,
    tokens,
  ).map((p) => p.symbol).join();

  test('parses tokens.txt', () {
    expect(tokens[0], '<blk>');
    expect(tokens[4], 'a');
  });

  test('collapses repeats and drops blanks', () {
    expect(
      decode([(5, .9), (5, .9), (0, .9), (4, .9), (4, .9), (0, .9), (8, .9)]),
      'nat',
    );
  });

  test('merges duplicates separated by blank', () {
    expect(decode([(5, .9), (0, .9), (5, .9)]), 'n');
  });

  test('drops single low-confidence frames', () {
    expect(decode([(4, .9), (4, .9), (8, .2), (0, .9)]), 'a');
  });

  test('keeps long phonemes even at low confidence', () {
    expect(decode([(4, .3), (4, .3), (4, .3)]), 'a');
  });

  test('similar vowels are merged before choosing the winner', () {
    // e and ɛ each 0.3 > any other single token; as a class they win
    final lp = <double>[];
    for (var v = 0; v < vocab; v++) {
      lp.add(
        math.log(
          v == 6 || v == 7
              ? 0.3
              : v == 0
              ? 0.25
              : 0.15 / 6,
        ),
      );
    }
    final twice = [...lp, ...lp];
    final r = decodeCtc(twice, 2, vocab, tokens);
    expect(r.single.symbol, anyOf('e', 'ɛ'));
  });
}
