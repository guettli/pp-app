// All words of the study language, for the grown-ups (and curious
// children): picture, word, other accepted words, and what the quiz knows
// about it. Tapping a word says it.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/phrases.dart';
import '../game/game_io.dart';
import '../quiz/facts.dart';
import '../quiz/quiz_lines.dart';
import 'emoji_image.dart';
import 'strings.dart';

class WordListScreen extends StatefulWidget {
  const WordListScreen({super.key, required this.app});

  final AppState app;

  @override
  State<WordListScreen> createState() => _WordListScreenState();
}

class _WordListScreenState extends State<WordListScreen> {
  late final Speaker _tts = widget.app.io.speaker()
    ..setLanguage(widget.app.book.lang);
  late final QuizLines _lines = QuizLines.of(widget.app.book.lang);

  @override
  void dispose() {
    _tts.stop().catchError((Object _) {});
    super.dispose();
  }

  Future<void> _say(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('tts failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final book = widget.app.book;
    return Scaffold(
      backgroundColor: const Color(0xFF14143A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('${s.wordsTitle}  ·  ${book.phrases.length}'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: book.phrases.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _row(context, book.phrases[i]),
      ),
    );
  }

  Widget _row(BuildContext context, Phrase p) {
    final fact = widget.app.facts.of(p);
    final code = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    final measures = [
      if (fact?.sizeCm != null) formatSize(fact!.sizeCm!, code),
      if (fact?.weightKg != null) formatWeight(fact!.weightKg!, code),
    ];
    return Material(
      color: const Color(0xFF2B2B6B),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _say(p.text),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EmojiImage(p.emoji, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        p.text,
                        for (final a in p.alternatives) a.text,
                      ].join(' · '),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (measures.isNotEmpty)
                      Text(
                        measures.join('  ·  '),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    if (fact != null && fact.yes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final prop in Prop.values)
                              if (fact.yes.contains(prop))
                                _chip(_lines.label(prop)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFF3B2B7B),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text, style: const TextStyle(color: Colors.white)),
  );
}

/// A rough number: two significant digits at most, "," except in English.
String _rough(double v, String code) {
  final String t;
  if (v >= 10) {
    final digits = v.round().toString().length;
    final unit = digits <= 2 ? 1 : int.parse('1${'0' * (digits - 2)}');
    t = ((v / unit).round() * unit).toString();
  } else {
    final r = (v * 10).round() / 10;
    t = r == r.roundToDouble() ? r.round().toString() : r.toString();
  }
  return code == 'en' ? t : t.replaceAll('.', ',');
}

/// "≈ 30 cm", "≈ 4 m", "≈ 1 km".
String formatSize(double cm, String code) => cm < 100
    ? '≈ ${_rough(cm, code)} cm'
    : cm < 100000
    ? '≈ ${_rough(cm / 100, code)} m'
    : '≈ ${_rough(cm / 100000, code)} km';

/// "≈ 200 g", "≈ 5 kg", "≈ 12 t"; "< 1 g" for a feather.
String formatWeight(double kg, String code) => kg < 0.001
    ? '< 1 g'
    : kg < 1
    ? '≈ ${_rough(kg * 1000, code)} g'
    : kg < 1000
    ? '≈ ${_rough(kg, code)} kg'
    : '≈ ${_rough(kg / 1000, code)} t';
