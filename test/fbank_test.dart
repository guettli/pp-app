import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/phonetics/fbank.dart';
import 'package:phoneme_party/phonetics/recognizer.dart';

/// Minimal reader for 16-bit PCM mono WAV files.
Float32List readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final b = ByteData.sublistView(bytes);
  var off = 12;
  while (off + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes, off, off + 4);
    final size = b.getUint32(off + 4, Endian.little);
    if (id == 'data') {
      return pcm16ToFloat(
        Uint8List.sublistView(bytes, off + 8, off + 8 + size),
      );
    }
    off += 8 + size + (size & 1);
  }
  throw StateError('no data chunk');
}

void main() {
  test('matches Lhotse Fbank on a real recording (Der Hund)', () {
    final ref =
        jsonDecode(File('test/fixtures/der_hund_fbank.json').readAsStringSync())
            as Map<String, dynamic>;
    final expected = (ref['data'] as List).cast<num>();
    final got = extractFbank(readWav('test/fixtures/der_hund.wav'));

    expect(got.length ~/ numMelBins, ref['frames']);
    expect(got.length, expected.length);
    var maxErr = 0.0;
    var sumErr = 0.0;
    for (var i = 0; i < got.length; i++) {
      final e = (got[i] - expected[i]).abs();
      sumErr += e;
      if (e > maxErr) maxErr = e;
    }
    final meanErr = sumErr / got.length;
    // float32 vs float64 differences only; log energies range roughly -16..10
    expect(meanErr, lessThan(1e-3), reason: 'mean abs error $meanErr');
    expect(maxErr, lessThan(0.05), reason: 'max abs error $maxErr');
  });

  test('silence hits the log floor', () {
    final f = extractFbank(Float32List(16000));
    expect(f.length, 100 * numMelBins);
    expect(f.every((v) => (v - -15.942385).abs() < 1e-4), isTrue);
  });

  test('empty input', () {
    expect(extractFbank(Float32List(0)), isEmpty);
  });
}
