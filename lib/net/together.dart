// Two phones find each other for a two-player game: the host opens a match
// (match.dart) and shows its code; a guest joins with it; the host's child
// accepts the guest's animal; then offer and answer go through the
// meeting point and the phones talk directly (peer_link.dart).
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'match.dart';
import 'peer_link.dart';

/// How long the other phone may take to answer and the data channel to
/// open (TURN credentials, ICE gathering and long-poll latency included).
const linkTimeout = Duration(seconds: 40);

sealed class HostEvent {}

/// Someone joined; the screen shows their animal and asks.
class Joined extends HostEvent {
  Joined(this.animal);
  final int animal;
}

/// The guest went away before the link was up; the code is open again.
class GuestLeft extends HostEvent {}

/// The match is over (expired, or no internet).
class MatchOver extends HostEvent {
  MatchOver(this.error);
  final MatchError error;
}

/// Everything a two-player screen needs from the network (fakes in tests).
class Together {
  Together(this.signal, this.links, {this.retryPause});
  final MatchSignal signal;
  final LinkMaker links;

  /// For [SignalReader] (tests make it short).
  final Duration Function(int n)? retryPause;

  /// TURN credentials, fetched once while the children are busy with the
  /// code (they live an hour).
  Future<List<Map<String, dynamic>>> ice() async {
    try {
      return await signal.iceServers();
    } on MatchError catch (e) {
      // without a relay the phones still find each other on one Wi-Fi
      debugPrint('no TURN credentials: $e');
      return const [];
    }
  }
}

/// A match was closed while a step was still under way.
const _closedError = MatchError(MatchFailure.gone, 'closed');

class HostMatch {
  HostMatch(this.together);
  final Together together;
  MatchSignal get _signal => together.signal;

  String? _code;
  String? _token; // null until open() worked
  SignalReader? _reader;
  final _events = StreamController<HostEvent>.broadcast();
  Future<List<Map<String, dynamic>>>? _ice;

  /// The seq of the "joined" the screen shows (the guest the child may say
  /// yes to); 0: nobody.
  var _guest = 0;
  Completer<Map<String, dynamic>>? _answer;
  var _offers = 0;
  var _closed = false;

  Stream<HostEvent> get events => _events.stream;
  String get code => _code!;

  /// The animal of the guest waiting for a yes, if one is.
  int? get waiting => _guest == 0 || _closed ? null : _animal;

  bool get closed => _closed;
  var _animal = 0;

  /// Opens the match; returns its code.
  Future<String> open() async {
    final m = await _signal.create();
    if (_closed) {
      unawaited(_signal.leave(m.code, m.token)); // left while it opened
      throw _closedError;
    }
    _code = m.code;
    _token = m.token;
    _ice = together.ice();
    _reader =
        SignalReader(_signal, m.code, m.token, retryPause: together.retryPause)
          ..messages.listen(
            _onMessage,
            onError: (Object e) {
              final err = e is MatchError
                  ? e
                  : MatchError(MatchFailure.offline);
              _failAnswer(err);
              if (!_closed) _events.add(MatchOver(err));
            },
          );
    return m.code;
  }

  void _failAnswer(MatchError e) {
    final a = _answer;
    _answer = null;
    if (a != null && !a.isCompleted) a.completeError(e);
  }

  void _onMessage(SignalMsg m) {
    if (_closed) return;
    final type = m.msg['type'];
    if (m.from == 'service' && type == 'joined') {
      _guest = m.seq;
      _animal = m.msg['animal'] as int? ?? 0;
      _events.add(Joined(_animal));
    } else if (m.from == 'service' && type == 'left') {
      _guest = 0;
      _failAnswer(const MatchError(MatchFailure.guestLeft));
      _events.add(GuestLeft());
    } else if (m.from == 'guest' && type == 'answer') {
      final a = _answer;
      _answer = null;
      if (a != null && !a.isCompleted) a.complete(m.msg);
    }
  }

  Future<void> reject() async {
    _guest = 0;
    await _signal.reject(code, _token!);
  }

  /// The host's child said yes to the guest it sees: offer, answer, open
  /// the link. Fails with [MatchFailure.guestLeft] when that guest left,
  /// and with [MatchFailure.taken] when another one is in the match by
  /// now; the code is still open then ([waiting] may name the next guest).
  /// Any other failure ends the match.
  Future<PeerLink> accept() async {
    final guest = _guest;
    if (guest == 0) throw const MatchError(MatchFailure.guestLeft);
    if (_answer != null) throw StateError('accept() runs already');
    // listen before anything can fail it (a "left" during the offer)
    final answer = _answer = Completer();
    final answered = answer.future.timeout(linkTimeout);
    unawaited(answered.then((_) {}, onError: (_) {}));
    final pending = await together.links.offer(await _ice!);
    try {
      if (_closed) throw _closedError;
      if (_guest != guest) throw const MatchError(MatchFailure.guestLeft);
      await _signal.send(
        code,
        _token!,
        {'type': 'offer', ...pending.description},
        id: 'offer-${_offers++}',
        guest: guest,
      );
      await pending.accept(await answered);
      final link = await pending.open(linkTimeout);
      if (_closed) {
        unawaited(link.close());
        throw _closedError;
      }
      await close(); // the meeting point is done
      return link;
    } catch (e) {
      if (identical(_answer, answer)) _answer = null; // e.g. a timeout
      await pending.dispose();
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _reader?.stop();
    _failAnswer(_closedError);
    if (_token case final t?) unawaited(_signal.leave(code, t));
    await _events.close();
  }
}

class GuestMatch {
  GuestMatch(this.together);
  final Together together;
  MatchSignal get _signal => together.signal;

  String? _code;
  String? _token; // null until join() worked
  SignalReader? _reader;
  Future<List<Map<String, dynamic>>>? _ice;
  var _closed = false;

  /// Joins; returns the animal both screens show. A lost answer is asked
  /// again with the same nonce (the service gives the same token).
  Future<int> join(String code, {String? nonce}) async {
    final n = nonce ?? randomHex(16);
    ({String token, int animal}) j;
    for (var tries = 1; ; tries++) {
      try {
        j = await _signal.join(code, n);
        break;
      } on MatchError catch (e) {
        // a lost answer is asked again; not when the service said "busy"
        // (that would only use up the joins it allows)
        if (e.failure != MatchFailure.offline ||
            e.detail.endsWith(' 429') ||
            tries >= 3 ||
            _closed) {
          rethrow;
        }
        await Future<void>.delayed(
          together.retryPause?.call(tries) ?? Duration(seconds: tries),
        );
      }
    }
    if (_closed) {
      unawaited(_signal.leave(code, j.token)); // left while it joined
      throw _closedError;
    }
    _code = code;
    _token = j.token;
    _ice = together.ice();
    return j.animal;
  }

  /// Waits for the host's child to say yes (the offer), then answers and
  /// opens the link. Fails with [MatchFailure.gone] when the host said no
  /// or went away.
  Future<PeerLink> connect() async {
    final reader = _reader = SignalReader(
      _signal,
      _code!,
      _token!,
      retryPause: together.retryPause,
    );
    SignalMsg offer;
    try {
      offer = await reader.messages.firstWhere(
        (m) => m.from == 'host' && m.msg['type'] == 'offer',
      );
    } on MatchError {
      rethrow;
    } catch (_) {
      throw const MatchError(MatchFailure.gone); // stopped or ended
    } finally {
      reader.stop();
    }
    if (_closed) throw _closedError;
    final pending = await together.links.answer(await _ice!, offer.msg);
    try {
      if (_closed) throw _closedError;
      await _signal.send(_code!, _token!, {
        'type': 'answer',
        ...pending.description,
      }, id: 'answer');
      final link = await pending.open(linkTimeout);
      if (_closed) {
        unawaited(link.close());
        throw _closedError;
      }
      await close();
      return link;
    } catch (e) {
      await pending.dispose();
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _reader?.stop();
    if (_token case final t?) unawaited(_signal.leave(_code!, t));
  }
}
