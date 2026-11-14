import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

const studyLanguages = ['de-DE', 'en-GB', 'fr-FR', 'it-IT', 'es-ES'];

const languageNames = {
  'de-DE': 'Deutsch',
  'en-GB': 'English',
  'fr-FR': 'Français',
  'it-IT': 'Italiano',
  'es-ES': 'Español',
};

const languageFlags = {
  'de-DE': '🇩🇪',
  'en-GB': '🇬🇧',
  'fr-FR': '🇫🇷',
  'it-IT': '🇮🇹',
  'es-ES': '🇪🇸',
};

class Phrase {
  const Phrase({
    required this.text,
    required this.emoji,
    required this.ipa,
    required this.level,
    this.translations = const {},
    this.alternatives = const [],
  });

  factory Phrase.fromJson(Map<String, dynamic> j) => Phrase(
    text: j['p'] as String,
    emoji: j['e'] as String,
    ipa: j['ipa'] as String,
    level: j['lvl'] as int,
    translations: (j['tr'] as Map<String, dynamic>? ?? {})
        .cast<String, String>(),
    alternatives: [
      for (final a in (j['alt'] as List? ?? []).cast<Map<String, dynamic>>())
        (text: a['p'] as String, ipa: a['ipa'] as String),
    ],
  );

  final String text;
  final String emoji;
  final String ipa;

  /// Difficulty 0..1000 (from guettli/pp).
  final int level;
  final Map<String, String> translations;

  /// Other common words for the same picture (e.g. Möhre for Karotte). The
  /// app says [text], but any of them is accepted.
  final List<({String text, String ipa})> alternatives;

  /// [text] and all [alternatives].
  List<({String text, String ipa})> get accepted => [
    (text: text, ipa: ipa),
    ...alternatives,
  ];
}

class PhraseBook {
  PhraseBook(this.lang, this.phrases);

  final String lang;

  /// Sorted by level (easy first).
  final List<Phrase> phrases;

  static Future<PhraseBook> load(String lang) async {
    final raw = await rootBundle.loadString('assets/phrases/$lang.json');
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return PhraseBook(lang, list.map(Phrase.fromJson).toList());
  }

  /// Phrases for world [world] (0-based): 8 phrases per world, easy first.
  static const perWorld = 8;
  int get worldCount => (phrases.length / perWorld).ceil();

  List<Phrase> world(int world) {
    final start = world * perWorld;
    return phrases.sublist(start, math.min(start + perWorld, phrases.length));
  }
}
