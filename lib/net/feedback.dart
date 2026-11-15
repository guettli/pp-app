// Feedback and bug reports, sent by a grown-up from the feedback screen.
// This directory (lib/net/) is the only place where the app talks to the
// internet (CI checks that). Recordings never leave the phone: a report is
// the typed text plus what the screen shows before sending (app version,
// languages, phone model, Android version).
//
// Reports go into an outbox first, so one written without internet is
// sent later (on the next start, or the next report).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The pp-app feedback service on the vps (server/feedback; deployed from
/// guettli/gitops, k8s/plain/vps/pp-app). It stores the report there; it is
/// not published.
final feedbackEndpoint = Uri.parse(
  'https://relaxandplay.de/pp-app/api/feedback',
);

enum FeedbackKind { bug, idea, word, other }

class FeedbackReport {
  FeedbackReport({
    required this.id,
    required this.kind,
    required this.text,
    required this.info,
    required this.created,
  });

  factory FeedbackReport.fromJson(Map<String, dynamic> j) => FeedbackReport(
    id: j['id'] as String,
    kind: FeedbackKind.values.byName(j['kind'] as String),
    text: j['text'] as String,
    info: (j['info'] as Map<String, dynamic>).cast<String, String>(),
    created: DateTime.parse(j['created'] as String),
  );

  /// Random; the service files a report only once, however often it
  /// arrives (a retry after a lost answer).
  final String id;
  final FeedbackKind kind;
  final String text;

  /// What else is sent, shown on the screen before sending.
  final Map<String, String> info;
  final DateTime created;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'text': text,
    'info': info,
    'created': created.toUtc().toIso8601String(),
  };

  /// Longest text the screen allows (characters as the user sees them; the
  /// service takes more code points, emoji are several).
  static const maxText = 2000;

  static String newId(math.Random rng) => List.generate(
    16,
    (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Delivers one report.
abstract class FeedbackTransport {
  Future<SendResult> send(Map<String, dynamic> json);
}

enum SendResult {
  /// Stored by the service (or stored before).
  done,

  /// No internet, server down, too many reports: keep and try later.
  later,

  /// The service says the report is malformed (400, 413): it will never
  /// take it, drop it.
  rejected,
}

class HttpFeedbackTransport implements FeedbackTransport {
  HttpFeedbackTransport({Uri? endpoint})
    : endpoint = endpoint ?? feedbackEndpoint;

  final Uri endpoint;

  @override
  Future<SendResult> send(Map<String, dynamic> json) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      // the whole exchange: a stalled answer must not hold the outbox
      return await _send(client, json).timeout(const Duration(seconds: 40));
    } catch (e) {
      debugPrint('feedback not sent: $e');
      return SendResult.later;
    } finally {
      client.close(force: true);
    }
  }

  Future<SendResult> _send(HttpClient client, Map<String, dynamic> json) async {
    final req = await client.postUrl(endpoint);
    req.followRedirects = false;
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode(json)));
    final res = await req.close();
    await res.drain<void>();
    final code = res.statusCode;
    if (code >= 200 && code < 300) return SendResult.done;
    // Only the service's own "malformed" drops a report. Anything else (a
    // captive portal, a redirect, 404 while the route is being set up,
    // 429, 5xx) may work later.
    if (code == 400 || code == 413) return SendResult.rejected;
    return SendResult.later;
  }
}

/// What became of a report the user just sent.
enum ReportState { sent, waiting, rejected }

/// Reports waiting to be sent, on the phone.
class FeedbackOutbox {
  FeedbackOutbox(this._prefs, this._transport);

  final SharedPreferences _prefs;
  final FeedbackTransport _transport;
  Future<void>? _flushing;

  /// Ids of reports the service rejected (since the app started).
  final _rejected = <String>{};

  static const _key = 'feedback|outbox';

  /// More are not kept (the oldest go first).
  static const maxWaiting = 20;

  /// Older ones are given up.
  static const maxAge = Duration(days: 30);

  List<FeedbackReport> get waiting => [
    for (final s in _prefs.getStringList(_key) ?? const <String>[]) ?_parse(s),
  ];

  static FeedbackReport? _parse(String s) {
    try {
      return FeedbackReport.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _store(List<FeedbackReport> reports) => _prefs.setStringList(
    _key,
    [for (final r in reports) jsonEncode(r.toJson())],
  );

  /// Keeps [report] and tries to send everything, waiting at most [wait];
  /// after that the sending goes on in the background.
  Future<ReportState> add(
    FeedbackReport report, {
    Duration wait = const Duration(seconds: 15),
  }) async {
    final all = [...waiting, report];
    await _store(all.sublist(math.max(0, all.length - maxWaiting)));
    try {
      await flush().timeout(wait);
    } on TimeoutException {
      // still sending: it stays in the outbox until it went out
    }
    if (_rejected.contains(report.id)) return ReportState.rejected;
    return waiting.any((r) => r.id == report.id)
        ? ReportState.waiting
        : ReportState.sent;
  }

  /// Sends what is waiting, oldest first, also reports added meanwhile;
  /// stops at the first "later".
  Future<void> flush() {
    // one flush at a time: two would send the same report twice
    return _flushing ??= _flush().whenComplete(() => _flushing = null);
  }

  Future<void> _flush() async {
    while (true) {
      final next = waiting.firstOrNull;
      if (next == null) return;
      if (DateTime.now().difference(next.created) > maxAge) {
        await _remove(next.id);
        continue;
      }
      final result = await _transport.send(next.toJson());
      if (result == SendResult.later) return;
      if (result == SendResult.rejected) _rejected.add(next.id);
      await _remove(next.id);
    }
  }

  Future<void> _remove(String id) => _store([
    for (final r in waiting)
      if (r.id != id) r,
  ]);
}
