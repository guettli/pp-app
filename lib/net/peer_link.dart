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
  /// Messages of the other phone, in order. Ends when the link is lost.
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
    final channel = await pc.createDataChannel(
      'game',
      RTCDataChannelInit()..ordered = true,
    );
    await pc.setLocalDescription(await pc.createOffer());
    final d = await _gathered(pc);
    return _WebRtcPending(pc, Future.value(channel), d.toMap());
  }

  @override
  Future<PendingLink> answer(
    List<Map<String, dynamic>> iceServers,
    Map<String, dynamic> offer,
  ) async {
    final pc = await _pc(iceServers);
    final channel = Completer<RTCDataChannel>();
    pc.onDataChannel = (c) {
      if (!channel.isCompleted) channel.complete(c);
    };
    await pc.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
    );
    await pc.setLocalDescription(await pc.createAnswer());
    final d = await _gathered(pc);
    return _WebRtcPending(pc, channel.future, d.toMap());
  }
}

class _WebRtcPending implements PendingLink {
  _WebRtcPending(this.pc, this.channel, Map<dynamic, dynamic> description)
    : description = description.cast<String, dynamic>();

  final RTCPeerConnection pc;
  final Future<RTCDataChannel> channel;
  @override
  final Map<String, dynamic> description;

  @override
  Future<void> accept(Map<String, dynamic> answer) => pc.setRemoteDescription(
    RTCSessionDescription(answer['sdp'] as String, answer['type'] as String),
  );

  @override
  Future<PeerLink> open(Duration timeout) async {
    final c = await channel.timeout(timeout);
    if (c.state != RTCDataChannelState.RTCDataChannelOpen) {
      final opened = Completer<void>();
      c.onDataChannelState = (s) {
        if (s == RTCDataChannelState.RTCDataChannelOpen &&
            !opened.isCompleted) {
          opened.complete();
        }
      };
      await opened.future.timeout(timeout);
    }
    return _WebRtcLink(pc, c);
  }

  @override
  Future<void> dispose() => pc.close();
}

class _WebRtcLink implements PeerLink {
  _WebRtcLink(this.pc, this.channel) {
    channel.onMessage = (m) {
      if (m.isBinary) return;
      try {
        final j = jsonDecode(m.text);
        if (j is Map) _out.add(j.cast<String, dynamic>());
      } on FormatException catch (e) {
        debugPrint('peer: bad message $e');
      }
    };
    channel.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelClosed) _end();
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _end();
      }
    };
  }

  final RTCPeerConnection pc;
  final RTCDataChannel channel;
  final _out = StreamController<Map<String, dynamic>>();

  @override
  Stream<Map<String, dynamic>> get messages => _out.stream;

  void _end() {
    if (!_out.isClosed) unawaited(_out.close());
  }

  @override
  void send(Map<String, dynamic> msg) {
    if (channel.state != RTCDataChannelState.RTCDataChannelOpen) return;
    unawaited(channel.send(RTCDataChannelMessage(jsonEncode(msg))));
  }

  @override
  Future<void> close() async {
    _end();
    await channel.close();
    await pc.close();
  }
}
