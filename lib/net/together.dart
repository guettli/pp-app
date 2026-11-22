// Two phones find each other for a two-player game: the host opens a match
// (match.dart) and shows its code; a guest joins with it; the host's child
// accepts the guest's animal; then offer and answer go through the
// meeting point and the phones talk directly (peer_link.dart).
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'match.dart';
import 'peer_link.dart';

/// How long the data channel may take to open (ICE through TURN included).
const linkTimeout = Duration(seconds: 25);

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
  const Together(this.signal, this.links);
  final MatchSignal signal;
  final LinkMaker links;

  Future<List<Map<String, dynamic>>> _ice() async {
    try {
      return await signal.iceServers();
    } on MatchError catch (e) {
      // without a relay the phones still find each other on one Wi-Fi
      debugPrint('no TURN credentials: $e');
      return const [];
    }
  }
}

class HostMatch {
  HostMatch(this.together);
  final Together together;
  MatchSignal get _signal => together.signal;

  late final String code;
  String? _token; // null until open() worked
  SignalReader? _reader;
  final _events = StreamController<HostEvent>.broadcast();
  Completer<Map<String, dynamic>>? _answer;
  var _offers = 0;
  var _closed = false;

  Stream<HostEvent> get events => _events.stream;

  /// Opens the match; returns its code.
  Future<String> open() async {
    final m = await _signal.create();
    code = m.code;
    _token = m.token;
    _reader = SignalReader(_signal, code, m.token)
      ..messages.listen(
        _onMessage,
        onError: (Object e) {
          final err = e is MatchError ? e : MatchError(MatchFailure.offline);
          _answer?.completeError(err);
          if (!_closed) _events.add(MatchOver(err));
        },
      );
    return code;
  }

  void _onMessage(SignalMsg m) {
    final type = m.msg['type'];
    if (m.from == 'service' && type == 'joined') {
      _events.add(Joined(m.msg['animal'] as int? ?? 0));
    } else if (m.from == 'service' && type == 'left') {
      _answer?.completeError(const MatchError(MatchFailure.gone));
      _answer = null;
      _events.add(GuestLeft());
    } else if (m.from == 'guest' && type == 'answer') {
      final a = _answer;
      _answer = null;
      if (a != null && !a.isCompleted) a.complete(m.msg);
    }
  }

  Future<void> reject() => _signal.reject(code, _token!);

  /// The host's child said yes: offer, answer, open the link.
  Future<PeerLink> accept() async {
    final pending = await together.links.offer(await together._ice());
    try {
      final answer = _answer = Completer();
      await _signal.send(code, _token!, {
        'type': 'offer',
        ...pending.description,
      }, id: 'offer-${_offers++}');
      await pending.accept(await answer.future.timeout(linkTimeout));
      final link = await pending.open(linkTimeout);
      await close(); // the meeting point is done
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
    if (_token case final t?) unawaited(_signal.leave(code, t));
    await _events.close();
  }
}

class GuestMatch {
  GuestMatch(this.together);
  final Together together;
  MatchSignal get _signal => together.signal;

  late final String code;
  String? _token; // null until join() worked
  SignalReader? _reader;
  var _closed = false;

  /// Joins; returns the animal both screens show.
  Future<int> join(String code, {String? nonce}) async {
    final j = await _signal.join(code, nonce ?? randomHex(16));
    this.code = code;
    _token = j.token;
    return j.animal;
  }

  /// Waits for the host's child to say yes (the offer), then answers and
  /// opens the link. Fails with [MatchFailure.gone] when the host said no
  /// or went away.
  Future<PeerLink> connect() async {
    final reader = _reader = SignalReader(_signal, code, _token!);
    final offer = await reader.messages
        .firstWhere((m) => m.from == 'host' && m.msg['type'] == 'offer')
        .catchError((Object e) {
          throw e is MatchError ? e : const MatchError(MatchFailure.gone);
        });
    reader.stop();
    final pending = await together.links.answer(
      await together._ice(),
      offer.msg,
    );
    try {
      await _signal.send(code, _token!, {
        'type': 'answer',
        ...pending.description,
      }, id: 'answer');
      final link = await pending.open(linkTimeout);
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
    if (_token case final t?) unawaited(_signal.leave(code, t));
  }
}
