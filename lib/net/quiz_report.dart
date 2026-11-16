// Quiz reports: one quiz question with the child's recordings, sent to
// the developer so a "not understood" can be replayed and the recogniser
// improved. Off unless a grown-up switched them on behind the parent gate
// (feedback screen); then the 🐞 button in the quiz sends the question the
// child just answered. Nothing is kept on the phone: a report that cannot
// be sent now is not sent (no outbox, the recording stays in memory only).
// The service keeps them 90 days (server/feedback/quiz.go).
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'feedback.dart';

final quizReportEndpoint = Uri.parse(
  'https://relaxandplay.de/pp-app/api/quiz-report',
);

/// One try at a question: what the microphone heard and what the app made
/// of it.
class QuizTry {
  QuizTry({
    required this.pcm,
    required this.speech,
    required this.heard,
    required this.said,
    required this.scores,
  });

  /// 16 kHz mono PCM16, as recorded (before any processing).
  final Uint8List pcm;

  /// Whether the endpointer heard someone speak.
  final bool speech;

  /// The recogniser's IPA (empty when there was nothing to recognise).
  final String heard;

  /// The option the app chose, null when not understood.
  final String? said;

  /// Per option: its best score and share of the same sounds.
  final List<({String option, double score, double same})> scores;

  /// The server takes 13 s; the quiz listens 12 s at most.
  static const maxBytes = 12 * 16000 * 2 + 16000;

  Map<String, dynamic> toJson() => {
    'audio': base64Encode(pcmWav(pcm)),
    'speech': speech,
    'heard': heard,
    'said': said ?? '',
    'scores': [
      for (final s in scores)
        {'option': s.option, 'score': s.score, 'same': s.same},
    ],
  };
}

/// A WAV file of the first [QuizTry.maxBytes] of [pcm].
Uint8List pcmWav(Uint8List pcm) {
  final n =
      (pcm.length > QuizTry.maxBytes ? QuizTry.maxBytes : pcm.length) & ~1;
  final b = ByteData(44 + n);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  b.setUint32(4, 36 + n, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, 16000, Endian.little);
  b.setUint32(28, 32000, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  b.setUint32(40, n, Endian.little);
  final out = b.buffer.asUint8List();
  out.setRange(44, 44 + n, pcm);
  return out;
}

class QuizReport {
  QuizReport({
    required this.id,
    required this.created,
    required this.info,
    required this.lang,
    required this.question,
    required this.asked,
    required this.options,
    required this.answer,
    required this.tries,
  });

  final String id;
  final DateTime created;
  final Map<String, String> info;
  final String lang;

  /// As shown, and as the phone said it.
  final String question, asked;

  /// Each option's text and the IPA of every accepted way to say it.
  final List<({String text, List<String> ipa})> options;
  final String answer;

  /// One or two (a question not understood is asked once more).
  final List<QuizTry> tries;

  Map<String, dynamic> toJson() => {
    'id': id,
    'created': created.toUtc().toIso8601String(),
    'info': info,
    'lang': lang,
    'question': question,
    'asked': asked,
    'options': [
      for (final o in options) {'text': o.text, 'ipa': o.ipa},
    ],
    'answer': answer,
    'tries': [for (final t in tries) t.toJson()],
  };
}

/// Sends a quiz report once.
abstract class QuizReportSender {
  Future<SendResult> send(QuizReport report);
}

class HttpQuizReportSender implements QuizReportSender {
  HttpQuizReportSender({Uri? endpoint})
    : endpoint = endpoint ?? quizReportEndpoint;

  final Uri endpoint;

  @override
  Future<SendResult> send(QuizReport report) async {
    // a whole question is up to ~1 MB: built off the UI thread
    final body = await compute(_encode, report);
    return HttpFeedbackTransport(
      endpoint: endpoint,
    ).sendBytes(body, timeout: const Duration(seconds: 90));
  }

  static Uint8List _encode(QuizReport report) =>
      utf8.encode(jsonEncode(report.toJson()));
}
