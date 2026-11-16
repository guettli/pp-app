import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/phrases.dart';
import 'data/progress.dart';
import 'game/game_io.dart';
import 'net/feedback.dart';
import 'net/quiz_report.dart';
import 'phonetics/phoneme_distance.dart';
import 'phonetics/recognizer.dart';
import 'quiz/facts.dart';

/// Everything the game needs, loaded once at start.
class AppState {
  AppState(
    this.recognizer,
    this.comparer,
    this.progress,
    this.book, {
    required this.io,
    Facts? facts,
    this.feedback,
    this.quizReports,
  }) : facts = facts ?? Facts(const {});

  final Recognizer recognizer;

  /// Microphone, TTS and players (fakes in tests).
  final GameIo io;
  final PhonemeComparer comparer;
  final Progress progress;
  PhraseBook book;

  /// What the quiz knows about the pictures.
  final Facts facts;

  /// Reports from the feedback screen; null: no feedback (tests).
  final FeedbackOutbox? feedback;

  /// Sends quiz reports (when switched on); null: none (tests).
  final QuizReportSender? quizReports;

  static Future<AppState> load() async {
    final progress = await Progress.load();
    final comparer = PhonemeComparer.fromJson(
      await rootBundle.loadString('assets/panphon/panphon_features.json'),
    );
    final book = await PhraseBook.load(progress.studyLang ?? 'de-DE');
    final recognizer = await PhoneRecognizer.load();
    return AppState(
      recognizer,
      comparer,
      progress,
      book,
      io: GameIo.device(),
      facts: await Facts.load(),
      feedback: FeedbackOutbox(
        await SharedPreferences.getInstance(),
        HttpFeedbackTransport(),
      ),
      quizReports: HttpQuizReportSender(),
    );
  }

  Future<void> switchLanguage(String lang) async {
    book = await PhraseBook.load(lang);
    await progress.setStudyLang(lang);
  }

  int worldStars(int world) => progress.worldStars(book, world);
  bool worldOpen(int world) => progress.worldOpen(book, world);
}
