import 'package:flutter/services.dart';

import 'data/phrases.dart';
import 'data/progress.dart';
import 'phonetics/phoneme_distance.dart';
import 'phonetics/recognizer.dart';

/// Everything the game needs, loaded once at start.
class AppState {
  AppState._(this.recognizer, this.comparer, this.progress, this.book);

  final PhoneRecognizer recognizer;
  final PhonemeComparer comparer;
  final Progress progress;
  PhraseBook book;

  static Future<AppState> load() async {
    final progress = await Progress.load();
    final comparer = PhonemeComparer.fromJson(
      await rootBundle.loadString('assets/panphon/panphon_features.json'),
    );
    final book = await PhraseBook.load(progress.studyLang ?? 'de-DE');
    final recognizer = await PhoneRecognizer.load();
    return AppState._(recognizer, comparer, progress, book);
  }

  Future<void> switchLanguage(String lang) async {
    book = await PhraseBook.load(lang);
    await progress.setStudyLang(lang);
  }

  int worldStars(int world) => progress.worldStars(book, world);
  bool worldOpen(int world) => progress.worldOpen(book, world);
}
