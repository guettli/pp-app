// The direct link between two phones in a two-player game: a WebRTC data
// channel (game moves as small JSON messages, DTLS encrypted). Directly
// when the phones can reach each other, else through coturn on the vps.
// Only data: no camera, no microphone.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// An open link to the other phone.
abstract class PeerLink {
  /// Messages of the other phone, in order (one listener). Ends when the
  /// link is lost.
  Stream<Map<String, dynamic>> get messages;

  void send(Map<String, dynamic> msg);

  Future<void> close();
}

/// One side of a link being set up: its description (offer or answer, with
/// all its ICE candidates) goes to the other phone through the meeting
/// point.
abstract class PendingLink {
  Map<String, dynamic> get description;

  /// Host: the guest's answer.
  Future<void> accept(Map<String, dynamic> answer);

  /// Waits until the data channel is open.
  Future<PeerLink> open(Duration timeout);

  /// Frees it, unless [open] gave a link (that one is closed with the link).
  Future<void> dispose();
}

/// Makes links (fake in tests).
abstract class LinkMaker {
  Future<PendingLink> offer(List<Map<String, dynamic>> iceServers);
  Future<PendingLink> answer(
    List<Map<String, dynamic>> iceServers,
    Map<String, dynamic> offer,
  );
}

/// A connection that stays "disconnected" this long counts as lost (the
/// other app was closed); ICE alone would take about half a minute.
const disconnectedFor = Duration(seconds: 6);

class WebRtcLinkMaker implements LinkMaker {
  const WebRtcLinkMaker();

  static Future<RTCPeerConnection> _pc(List<Map<String, dynamic>> ice) =>
      createPeerConnection({'iceServers': ice, 'sdpSemantics': 'unified-plan'});

  /// Waits for all ICE candidates (no trickling: one message each way),
  /// at most [timeout]; then what is there.
  static Future<RTCSessionDescription> _gathered(
    RTCPeerConnection pc, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final done = Completer<void>();
    pc.onIceGatheringState = (s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !done.isCompleted) {
        done.complete();
      }
    };
    if (pc.iceGatheringState !=
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      await done.future.timeout(timeout, onTimeout: () {});
    }
    return (await pc.getLocalDescription())!;
  }

  @override
  Future<PendingLink> offer(List<Map<String, dynamic>> iceServers) async {
    final pc = await _pc(iceServers);
    final p = _WebRtcPending(pc);
    try {
      p.channel(
        await pc.createDataChannel(
          'game',
          RTCDataChannelInit()..ordered = true,
        ),
      );
      await pc.setLocalDescription(await pc.createOffer());
      p.description = (await _gathered(pc)).toMap().cast<String, dynamic>();
      return p;
    } catch (e) {
      await p.dispose();
      throw _wrap(e);
    }
  }

  @override
  Future<PendingLink> answer(
    List<Map<String, dynamic>> iceServers,
    Map<String, dynamic> offer,
  ) async {
    final pc = await _pc(iceServers);
    final p = _WebRtcPending(pc);
    pc.onDataChannel = p.channel;
    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
      );
      await pc.setLocalDescription(await pc.createAnswer());
      p.description = (await _gathered(pc)).toMap().cast<String, dynamic>();
      return p;
    } catch (e) {
      await p.dispose();
      throw _wrap(e);
    }
  }
}

/// flutter_webrtc throws strings from failed platform calls.
Exception _wrap(Object e) => e is Exception ? e : Exception('webrtc: $e');

class _WebRtcPending implements PendingLink {
  _WebRtcPending(this.pc) {
    pc.onConnectionState = (s) {
      _state = s;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
          !_opened.isCompleted) {
        _opened.completeError(TimeoutException('no connection'));
      }
      _link?._connection(s);
    };
  }

  final RTCPeerConnection pc;
  @override
  late final Map<String, dynamic> description;
  RTCDataChannel? _channel;
  final _opened = Completer<void>();
  // messages from the moment the channel exists, so none is lost before
  // the game listens
  final _in = StreamController<Map<String, dynamic>>();
  _WebRtcLink? _link;
  RTCPeerConnectionState? _state;
  var _disposed = false;

  void channel(RTCDataChannel c) {
    if (_channel != null) return;
    _channel = c;
    c.onMessage = (m) {
      if (m.isBinary) return;
      try {
        final j = jsonDecode(m.text);
        if (j is Map && !_in.isClosed) _in.add(j.cast<String, dynamic>());
      } on FormatException catch (e) {
        debugPrint('peer: bad message $e');
      }
    };
    c.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen && !_opened.isCompleted) {
        _opened.complete();
      }
      if (s == RTCDataChannelState.RTCDataChannelClosed) _link?._end();
    };
    if (c.state == RTCDataChannelState.RTCDataChannelOpen &&
        !_opened.isCompleted) {
      _opened.complete();
    }
  }

  @override
  Future<void> accept(Map<String, dynamic> answer) async {
    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(
          answer['sdp'] as String,
          answer['type'] as String,
        ),
      );
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<PeerLink> open(Duration timeout) async {
    await _opened.future.timeout(timeout);
    final link = _link = _WebRtcLink(this);
    if (_state != null) link._connection(_state!);
    return link;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (!_in.isClosed) unawaited(_in.close());
    try {
      // dispose, not only close: it frees the native connection and its
      // event channels
      await pc.dispose();
    } catch (e) {
      debugPrint('peer: dispose $e');
    }
  }
}

class _WebRtcLink implements PeerLink {
  _WebRtcLink(this._p);
  final _WebRtcPending _p;
  Timer? _lost;

  @override
  Stream<Map<String, dynamic>> get messages => _p._in.stream;

  void _connection(RTCPeerConnectionState s) {
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _end();
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _lost ??= Timer(disconnectedFor, _end);
      default:
        _lost?.cancel();
        _lost = null;
    }
  }

  void _end() {
    _lost?.cancel();
    if (!_p._in.isClosed) unawaited(_p._in.close());
  }

  @override
  void send(Map<String, dynamic> msg) {
    final c = _p._channel;
    if (c == null || c.state != RTCDataChannelState.RTCDataChannelOpen) return;
    c.send(RTCDataChannelMessage(jsonEncode(msg))).catchError((Object e) {
      debugPrint('peer: send $e');
    });
  }

  @override
  Future<void> close() async {
    _end();
    await _p.dispose();
  }
}
