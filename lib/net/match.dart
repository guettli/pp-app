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

  /// Someone joined already (or, for the host's offer: another guest is
  /// in the match by now).
  taken,

  /// The match is gone (the other phone left or said no, or it expired).
  gone,

  /// Host: the guest the child said yes to went away before the link was
  /// up; the code is open for the next one.
  guestLeft,

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

  /// [guest]: the host's offer names the guest its child said yes to (the
  /// seq of its "joined"); the service refuses it ([MatchFailure.taken])
  /// when another guest is in the match by now.
  Future<void> send(
    String code,
    String token,
    Map<String, dynamic> msg, {
    String? id,
    int? guest,
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

  /// Posts [body] to [route] and gives the answer to [read], which checks
  /// the status and reads the JSON. Anything unexpected (no internet, a
  /// captive portal, odd JSON) is [MatchFailure.offline].
  Future<T> _post<T>(
    String route,
    Map<String, dynamic> body,
    T Function(int status, Object? json) read, {
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
      final json = res.headers.contentType?.mimeType == 'application/json'
          ? jsonDecode(text)
          : null;
      return read(res.statusCode, json);
    } on MatchError {
      rethrow;
    } catch (e) {
      debugPrint('match $route: $e');
      throw MatchError(MatchFailure.offline, '$e');
    } finally {
      client.close(force: true);
    }
  }

  static Never _fail(int status, String route) {
    throw MatchError(switch (status) {
      404 when route == 'match/join' => MatchFailure.noSuchCode,
      404 => MatchFailure.gone,
      409 => MatchFailure.taken,
      _ => MatchFailure.offline,
    }, '$route $status');
  }

  @override
  Future<({String code, String token})> create() =>
      _post('match/new', {}, (st, j) {
        if (st != 201 || j is! Map) _fail(st, 'match/new');
        return (code: j['code'] as String, token: j['token'] as String);
      });

  @override
  Future<({String token, int animal})> join(String code, String nonce) =>
      _post('match/join', {'code': code, 'nonce': nonce}, (st, j) {
        if (st != 200 || j is! Map) _fail(st, 'match/join');
        return (token: j['token'] as String, animal: j['animal'] as int);
      });

  @override
  Future<void> reject(String code, String token) =>
      _post('match/reject', {'code': code, 'token': token}, (st, _) {
        if (st != 204) _fail(st, 'match/reject');
      });

  @override
  Future<void> send(
    String code,
    String token,
    Map<String, dynamic> msg, {
    String? id,
    int? guest,
  }) => _post(
    'match/send',
    {'code': code, 'token': token, 'msg': msg, 'id': ?id, 'guest': ?guest},
    (st, _) {
      if (st != 204) _fail(st, 'match/send');
    },
  );

  @override
  Future<({List<SignalMsg> msgs, int next})> recv(
    String code,
    String token,
    int after,
  ) => _post('match/recv', {'code': code, 'token': token, 'after': after}, (
    st,
    j,
  ) {
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
  }, timeout: const Duration(seconds: 25));

  @override
  Future<void> leave(String code, String token) async {
    try {
      await _post('match/leave', {'code': code, 'token': token}, (_, _) {});
    } on MatchError {
      // gone anyway after a minute
    }
  }

  @override
  Future<List<Map<String, dynamic>>> iceServers() => _post('turn', {}, (st, j) {
    if (st != 200 || j is! Map) _fail(st, 'turn');
    return [
      for (final s in j['iceServers'] as List)
        (s as Map).cast<String, dynamic>(),
    ];
  });
}

/// Reads the messages of one phone in a match, one recv after the other,
/// until [stop] or the match is gone (then the stream ends with a
/// [MatchError]). A short dead spot (a tunnel, Wi-Fi to mobile) is retried.
class SignalReader {
  SignalReader(this.signal, this.code, this.token, {this.retryPause}) {
    unawaited(_run());
  }

  final MatchSignal signal;
  final String code;
  final String token;

  /// The pause before the nth retry (tests make it short).
  final Duration Function(int n)? retryPause;
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
      } catch (e) {
        if (_stopped) break;
        final err = e is MatchError
            ? e
            : MatchError(MatchFailure.offline, '$e');
        // the match waits a minute for a phone that does not ask
        if (err.failure == MatchFailure.offline && ++failures < 6) {
          await Future<void>.delayed(
            retryPause?.call(failures) ?? Duration(seconds: 2 * failures),
          );
          continue;
        }
        _out.addError(err);
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
