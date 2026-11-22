// The meeting point of the two-player games (server/feedback/match.go):
// one phone opens a match and shows its code, the other joins with it;
// then both swap their WebRTC offer and answer here and talk directly
// (peer_link.dart). TURN credentials for phones that cannot reach each
// other come from the same service (server/feedback/turn.go).
//
// Like everything that talks to the internet, this lives in lib/net/.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The service's base; the routes are below it.
final matchBase = Uri.parse('https://relaxandplay.de/pp-app/api/');

enum MatchFailure {
  /// No match with this code (mistyped, or it expired).
  noSuchCode,

  /// Someone joined already.
  taken,

  /// The match is gone (the other phone left, or it expired).
  gone,

  /// No internet, or the service is busy.
  offline,
}

class MatchError implements Exception {
  const MatchError(this.failure, [this.detail = '']);
  final MatchFailure failure;
  final String detail;
  @override
  String toString() => 'MatchError($failure $detail)';
}

/// A message from the other phone or ("service") the meeting point.
typedef SignalMsg = ({int seq, String from, Map<String, dynamic> msg});

/// The meeting point's routes (fake in tests).
abstract class MatchSignal {
  Future<({String code, String token})> create();
  Future<({String token, int animal})> join(String code, String nonce);
  Future<void> reject(String code, String token);
  Future<void> send(
    String code,
    String token,
    Map<String, dynamic> msg, {
    String? id,
  });

  /// Waits a while for messages after [after]; may return none.
  Future<({List<SignalMsg> msgs, int next})> recv(
    String code,
    String token,
    int after,
  );
  Future<void> leave(String code, String token);

  /// STUN and TURN servers, as RTCConfiguration.iceServers.
  Future<List<Map<String, dynamic>>> iceServers();
}

class HttpMatchSignal implements MatchSignal {
  HttpMatchSignal({Uri? base}) : base = base ?? matchBase;
  final Uri base;

  Future<(int, Object?)> _post(
    String route,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(base.resolve(route)).timeout(timeout);
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      final b = utf8.encode(jsonEncode(body));
      req.contentLength = b.length;
      req.add(b);
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      Object? json;
      if (res.headers.contentType?.mimeType == 'application/json') {
        json = jsonDecode(text);
      }
      return (res.statusCode, json);
    } on MatchError {
      rethrow;
    } catch (e) {
      debugPrint('match $route: $e');
      throw MatchError(MatchFailure.offline, '$e');
    } finally {
      client.close(force: true);
    }
  }

  Never _fail(int status, String route) {
    throw MatchError(switch (status) {
      404 =>
        route == 'match/join' ? MatchFailure.noSuchCode : MatchFailure.gone,
      409 => MatchFailure.taken,
      _ => MatchFailure.offline,
    }, '$route $status');
  }

  @override
  Future<({String code, String token})> create() async {
    final (st, j) = await _post('match/new', {});
    if (st != 201 || j is! Map) _fail(st, 'match/new');
    return (code: j['code'] as String, token: j['token'] as String);
  }

  @override
  Future<({String token, int animal})> join(String code, String nonce) async {
    final (st, j) = await _post('match/join', {'code': code, 'nonce': nonce});
    if (st != 200 || j is! Map) _fail(st, 'match/join');
    return (token: j['token'] as String, animal: j['animal'] as int);
  }

  @override
  Future<void> reject(String code, String token) async {
    final (st, _) = await _post('match/reject', {'code': code, 'token': token});
    if (st != 204) _fail(st, 'match/reject');
  }

  @override
  Future<void> send(
    String code,
    String token,
    Map<String, dynamic> msg, {
    String? id,
  }) async {
    final (st, _) = await _post('match/send', {
      'code': code,
      'token': token,
      'msg': msg,
      'id': ?id,
    });
    if (st != 204) _fail(st, 'match/send');
  }

  @override
  Future<({List<SignalMsg> msgs, int next})> recv(
    String code,
    String token,
    int after,
  ) async {
    final (st, j) = await _post('match/recv', {
      'code': code,
      'token': token,
      'after': after,
    }, timeout: const Duration(seconds: 25));
    if (st != 200 || j is! Map) _fail(st, 'match/recv');
    return (
      msgs: [
        for (final m in j['msgs'] as List)
          (
            seq: m['seq'] as int,
            from: m['from'] as String,
            msg: (m['msg'] as Map).cast<String, dynamic>(),
          ),
      ],
      next: j['next'] as int,
    );
  }

  @override
  Future<void> leave(String code, String token) async {
    try {
      await _post('match/leave', {'code': code, 'token': token});
    } on MatchError {
      // gone anyway after a minute
    }
  }

  @override
  Future<List<Map<String, dynamic>>> iceServers() async {
    final (st, j) = await _post('turn', {});
    if (st != 200 || j is! Map) _fail(st, 'turn');
    return [
      for (final s in j['iceServers'] as List)
        (s as Map).cast<String, dynamic>(),
    ];
  }
}

/// Reads the messages of one phone in a match, one recv after the other,
/// until [stop] or the match is gone (then the stream ends with a
/// [MatchError]).
class SignalReader {
  SignalReader(this.signal, this.code, this.token) {
    unawaited(_run());
  }

  final MatchSignal signal;
  final String code;
  final String token;
  final _out = StreamController<SignalMsg>();
  var _stopped = false;

  Stream<SignalMsg> get messages => _out.stream;

  Future<void> _run() async {
    var after = 0;
    var failures = 0;
    while (!_stopped) {
      try {
        final r = await signal.recv(code, token, after);
        failures = 0;
        after = r.next;
        for (final m in r.msgs) {
          if (_stopped) break;
          _out.add(m);
        }
      } on MatchError catch (e) {
        if (_stopped) break;
        // a short dead spot (tunnel, Wi-Fi to mobile): try again; the
        // match waits a minute
        if (e.failure == MatchFailure.offline && ++failures < 6) {
          await Future<void>.delayed(Duration(seconds: 2 * failures));
          continue;
        }
        _out.addError(e);
        break;
      }
    }
    await _out.close();
  }

  void stop() => _stopped = true;
}

/// A random hex string, for join nonces and message ids.
String randomHex(int bytes, [math.Random? rng]) {
  final r = rng ?? math.Random.secure();
  return [
    for (var i = 0; i < bytes; i++)
      r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}
