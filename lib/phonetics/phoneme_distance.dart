// Phoneme-level comparison of a target IPA string with recognised phonemes.
//
// Based on guettli/pp src/comparison/panphon-distance-core.ts: Needleman-
// Wunsch alignment, substitution cost = share of PanPhon articulatory features
// that differ, indel cost 0.5. Differences to pp (deliberate fixes):
//  * zero-width joiner (U+200D, used in the en-GB IPA as "t‍ʃ") is removed,
//    pp tokenised it as an unknown phoneme and penalised every affricate;
//  * combining diacritics stay attached to their base phoneme (e.g. French
//    nasal "ɛ̃"); unknown combinations fall back to the base phoneme's features;
//  * ASCII g is mapped to IPA ɡ: PanPhon only knows ɡ, pp mapped ɡ -> g and so
//    treated g as unknown (g vs. k cost 1.0 instead of one feature);
//  * word boundaries are tracked per target phoneme, not per alignment index
//    (pp shifted them after an insertion or deletion).
import 'dart:convert';
import 'dart:math' as math;

class AlignedPhoneme {
  const AlignedPhoneme(this.target, this.actual, this.cost, this.word);

  /// Expected phoneme, null for an extra (inserted) phoneme.
  final String? target;

  /// Recognised phoneme, null if the target phoneme was missing.
  final String? actual;
  final double cost;

  /// Index of the target word this phoneme belongs to.
  final int word;

  /// Practically the same sound (e.g. oː vs. o, or a German equivalence).
  bool get exact => target != null && actual != null && cost < 0.1;

  /// Close, but audibly different (counts half).
  bool get close => target != null && actual != null && cost < 0.3;

  @override
  String toString() => '${target ?? '∅'}:${actual ?? '∅'}';
}

class Comparison {
  const Comparison(
    this.score,
    this.similarity,
    this.alignment,
    this.target,
    this.actual,
  );

  /// Phoneme hit rate 0..1, drives the game: exact matches count 1, close
  /// ones 0.5, divided by the longer sequence (so extra sounds cost too).
  ///
  /// The feature distance alone ([similarity], what pp shows) is too
  /// lenient for a game: a completely different phrase still reaches ~0.7
  /// because most sounds share many articulatory features.
  final double score;

  /// 1 - alignment cost / worst case (PanPhon feature distance, as in pp but
  /// normalised so that silence gives 0 instead of 0.5).
  final double similarity;
  final List<AlignedPhoneme> alignment;
  final List<String> target;
  final List<String> actual;

  /// 0..3 stars for the game.
  int get stars => score >= 0.85
      ? 3
      : score >= 0.7
      ? 2
      : score >= 0.5
      ? 1
      : 0;
}

class PhonemeComparer {
  PhonemeComparer(this._features);

  /// Loads assets/panphon/panphon_features.json ({"names":[..],"features":{sym:[..]}}).
  factory PhonemeComparer.fromJson(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final f = (data['features'] as Map<String, dynamic>).map(
      (k, v) =>
          MapEntry(k, (v as List).cast<num>().map((e) => e.toInt()).toList()),
    );
    return PhonemeComparer(f);
  }

  final Map<String, List<int>> _features;
  static const double indel = 0.5;

  static const _germanEquivalent = [
    {'ɐ', 'r'}, // vocalised r
    {'ə', 'ɛ'}, // schwa variants
    {'ʁ', 'r'}, // uvular vs. alveolar r, both fine
    {'z', 's'}, // voicing of s varies by region (south vs. north)
  ];

  static bool _isCombining(int c) =>
      (c >= 0x0300 && c <= 0x036F) || c == 0x02B0 || c == 0x02B2 || c == 0x02E0;

  /// Removes markup the recogniser cannot hear (stress, syllable dots,
  /// glottal stops, punctuation, liaison and h-aspiré marks) and harmonises
  /// spelling variants.
  static String normalize(String ipa, String lang) {
    var s = ipa
        .replaceAll(RegExp('[/\\[\\]ˈˌ.ʔ\u200D!?,¡¿‿ʼ]'), '')
        // PanPhon only has the decomposed ç; phrases and ZIPA use U+00E7
        .replaceAll('\u00E7', 'c\u0327')
        .replaceAll('͡', '') // tie bar
        .replaceAll('̯', '') // non-syllabic
        .replaceAll('̴', '') // velarised
        .replaceAllMapped(RegExp('(.)̩'), (m) => 'ə${m[1]}') // syllabic C
        .replaceAll(
          'g',
          'ɡ',
        ) // PanPhon only knows IPA ɡ (U+0261); pp mapped the other way
        .replaceAllMapped(RegExp('(.)˞'), (m) => '${m[1]}ɹ')
        .replaceAll('ɝ', 'ɜɹ');
    if (lang == 'de-DE') {
      s = s.replaceAll('ɛʁ', 'ɐ').replaceAll('ər', 'ɐ');
    }
    return s.trim();
  }

  /// Splits normalised IPA into phonemes, returning the word index of each.
  (List<String>, List<int>) tokenize(String ipa, String lang) {
    final phonemes = <String>[];
    final words = <int>[];
    var w = 0;
    for (final word in normalize(ipa, lang).split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final runes = word.runes.toList();
      var i = 0;
      while (i < runes.length) {
        var len = 1;
        for (final l in [3, 2]) {
          if (i + l <= runes.length &&
              _features.containsKey(String.fromCharCodes(runes, i, i + l))) {
            len = l;
            break;
          }
        }
        final tok = String.fromCharCodes(runes, i, i + len);
        i += len;
        final c = tok.runes.first;
        if (phonemes.isNotEmpty &&
            words.last == w &&
            (tok == 'ː' || tok == 'ˑ' || (len == 1 && _isCombining(c)))) {
          phonemes[phonemes.length - 1] += tok;
        } else {
          phonemes.add(tok);
          words.add(w);
        }
      }
      w++;
    }
    return _dropGlides(phonemes, words);
  }

  static const _glideVowels = {
    'j': {'i', 'ɪ', 'y', 'ʏ'},
    'w': {'u', 'ʊ'},
  };
  static const _vowels = 'aeiouyæøœɑɒɔəɛɜɪʊʏɐʌɤɯɨʉ';

  /// Drops a glide that only spells the second half of a diphthong
  /// ("aji" -> "ai") or a vowel's off-glide at the end of a word ("tuːw").
  /// The recogniser often writes the diphthong in "Ei" /aɪ̯/ as a-j-i; in a
  /// word of two sounds that one extra sound would cost two stars. Applied
  /// to target and recognition alike. A glide before another vowel stays
  /// ("kja", Spanish "siʝa" heard as "sija").
  static (List<String>, List<int>) _dropGlides(
    List<String> phonemes,
    List<int> words,
  ) {
    String base(int i) => String.fromCharCode(phonemes[i].runes.first);
    bool sameWord(int i, int j) =>
        j >= 0 && j < phonemes.length && words[i] == words[j];
    final p = <String>[], w = <int>[];
    for (var i = 0; i < phonemes.length; i++) {
      final own = _glideVowels[phonemes[i]];
      if (own != null) {
        final prev = sameWord(i, i - 1) ? base(i - 1) : null;
        final next = sameWord(i, i + 1) ? base(i + 1) : null;
        final diphthong =
            prev != null &&
            _vowels.contains(prev) &&
            !own.contains(prev) &&
            next != null &&
            own.contains(next);
        final offGlide = prev != null && own.contains(prev) && next == null;
        if (diphthong || offGlide) continue;
      }
      p.add(phonemes[i]);
      w.add(words[i]);
    }
    return (p, w);
  }

  /// Whether [phoneme] (a token from [tokenize]) has articulatory features.
  bool isKnown(String phoneme) => _lookup(phoneme) != null;

  List<int>? _lookup(String p) {
    var s = p;
    while (s.isNotEmpty) {
      final f = _features[s];
      if (f != null) return f;
      final r = s.runes.toList();
      if (r.length == 1) return null;
      s = String.fromCharCodes(r, 0, r.length - 1);
    }
    return null;
  }

  double phonemeCost(String a, String b, String lang) {
    if (a == b) return 0;
    if (lang == 'de-DE' &&
        _germanEquivalent.any((s) => s.contains(a) && s.contains(b))) {
      return 0;
    }
    final fa = _lookup(a), fb = _lookup(b);
    if (fa == null || fb == null) return 1;
    var diff = 0;
    for (var i = 0; i < fa.length; i++) {
      if (fa[i] != fb[i]) diff++;
    }
    return diff / fa.length;
  }

  Comparison compare(String targetIpa, String actualIpa, String lang) {
    final (t, tw) = tokenize(targetIpa, lang);
    final (a, _) = tokenize(actualIpa, lang);
    final m = t.length, n = a.length;
    final dp = List.generate(m + 1, (_) => List<double>.filled(n + 1, 0));
    for (var i = 1; i <= m; i++) {
      dp[i][0] = i * indel;
    }
    for (var j = 1; j <= n; j++) {
      dp[0][j] = j * indel;
    }
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        dp[i][j] = math.min(
          math.min(dp[i - 1][j] + indel, dp[i][j - 1] + indel),
          dp[i - 1][j - 1] + phonemeCost(t[i - 1], a[j - 1], lang),
        );
      }
    }
    final out = <AlignedPhoneme>[];
    var i = m, j = n;
    while (i > 0 || j > 0) {
      // word of an inserted phoneme = word of the next target phoneme
      final word = i > 0 ? tw[i - 1] : (tw.isEmpty ? 0 : tw.first);
      if (i > 0 && j > 0) {
        final c = phonemeCost(t[i - 1], a[j - 1], lang);
        if ((dp[i][j] - (dp[i - 1][j - 1] + c)).abs() < 1e-9) {
          out.add(AlignedPhoneme(t[i - 1], a[j - 1], c, word));
          i--;
          j--;
          continue;
        }
      }
      if (i > 0 && (dp[i][j] - (dp[i - 1][j] + indel)).abs() < 1e-9) {
        out.add(AlignedPhoneme(t[i - 1], null, indel, word));
        i--;
      } else {
        out.add(AlignedPhoneme(null, a[j - 1], indel, word));
        j--;
      }
    }
    if (m + n == 0) return Comparison(1, 1, const [], t, a);
    // Worst case: delete every target phoneme and insert every actual one.
    final sim = (1 - dp[m][n] / (indel * (m + n))).clamp(0.0, 1.0);
    var hits = 0.0;
    for (final x in out) {
      hits += x.exact ? 1 : (x.close ? 0.5 : 0);
    }
    final score = hits / math.max(m, n);
    return Comparison(score, sim, out.reversed.toList(), t, a);
  }
}
