import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/net/match.dart';
import 'package:phoneme_party/net/peer_link.dart';
import 'package:phoneme_party/net/together.dart';
import 'package:phoneme_party/together/codes.dart';
import 'package:phoneme_party/together/together_screen.dart';

/// The meeting point in memory, with the service's rules (match.go) that
/// the app relies on.
class FakeSignal implements MatchSignal {
  final matches = <String, _M>{};
  var nextCode = 0x3f0a;
  var animal = 5;
  var offline = false;
  final calls = <String>[];

  _M _get(String code, String token) {
    final m = matches[code];
    if (m == null || (token != m.host && token != m.guest)) {
      throw const MatchError(MatchFailure.gone);
    }
    return m;
  }

  void _check(String op) {
    calls.add(op);
    if (offline) throw const MatchError(MatchFailure.offline);
  }

  @override
  Future<({String code, String token})> create() async {
    _check('new');
    final code = (nextCode++).toRadixString(16).padLeft(4, '0');
    matches[code] = _M('h-$code');
    return (code: code, token: 'h-$code');
  }

  @override
  Future<({String token, int animal})> join(String code, String nonce) async {
    _check('join');
    final m = matches[code];
    if (m == null) throw const MatchError(MatchFailure.noSuchCode);
    if (m.guest != null) throw const MatchError(MatchFailure.taken);
    m.guest = 'g-$nonce';
    m.base = m.msgs.length;
    m.post('service', {'type': 'joined', 'animal': animal});
    return (token: m.guest!, animal: animal);
  }

  @override
  Future<void> reject(String code, String token) async {
    _check('reject');
    final m = _get(code, token);
    m.guest = null;
    m.post('service', {'type': 'rejected'});
  }

  @override
  Future<void> send(
    String code,
    String token,
    Map<String, dynamic> msg, {
    String? id,
  }) async {
    _check('send');
    final m = _get(code, token);
    m.post(token == m.host ? 'host' : 'guest', msg);
  }

  @override
  Future<({List<SignalMsg> msgs, int next})> recv(
    String code,
    String token,
    int after,
  ) async {
    calls.add('recv');
    for (var i = 0; i < 50; i++) {
      final m = _get(code, token);
      final host = token == m.host;
      final from = host ? 0 : m.base;
      final out = [
        for (final x in m.msgs.skip(after < from ? from : after))
          if (host ? x.from != 'host' : x.from == 'host') x,
      ];
      if (out.isNotEmpty) return (msgs: out, next: m.msgs.length);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return (msgs: <SignalMsg>[], next: matches[code]?.msgs.length ?? after);
  }

  @override
  Future<void> leave(String code, String token) async {
    calls.add('leave');
    final m = matches[code];
    if (m == null) return;
    if (token == m.host) {
      matches.remove(code);
    } else if (token == m.guest) {
      m.guest = null;
      m.post('service', {'type': 'left'});
    }
  }

  @override
  Future<List<Map<String, dynamic>>> iceServers() async => const [];
}

class _M {
  _M(this.host);
  final String host;
  String? guest;
  int base = 0;
  final msgs = <SignalMsg>[];
  void post(String from, Map<String, dynamic> msg) =>
      msgs.add((seq: msgs.length + 1, from: from, msg: msg));
}

/// Links two phones in memory: the answer names its offer.
class FakeLinks implements LinkMaker {
  final _pending = <String, _FakePending>{};
  var n = 0;
  var fail = false;

  @override
  Future<PendingLink> offer(List<Map<String, dynamic>> ice) async {
    final id = 'o${n++}';
    return _pending[id] = _FakePending(this, {'type': 'offer', 'sdp': id});
  }

  @override
  Future<PendingLink> answer(
    List<Map<String, dynamic>> ice,
    Map<String, dynamic> offer,
  ) async {
    final host = _pending[offer['sdp']]!;
    final p = _FakePending(this, {'type': 'answer', 'sdp': offer['sdp']});
    host.peer = p;
    p.peer = host;
    return p;
  }
}

class _FakePending implements PendingLink {
  _FakePending(this.links, this.description);
  final FakeLinks links;
  @override
  final Map<String, dynamic> description;
  _FakePending? peer;
  final link = FakeLink();
  final _ready = Completer<void>();

  @override
  Future<void> accept(Map<String, dynamic> answer) async {}

  @override
  Future<PeerLink> open(Duration timeout) async {
    if (links.fail) throw TimeoutException('no link');
    final p = peer!;
    link.other = p.link;
    p.link.other = link;
    if (!_ready.isCompleted) _ready.complete();
    if (!p._ready.isCompleted) await p._ready.future.timeout(timeout);
    return link;
  }

  @override
  Future<void> dispose() async {}
}

class FakeLink implements PeerLink {
  FakeLink? other;
  final _in = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];
  @override
  Stream<Map<String, dynamic>> get messages => _in.stream;
  @override
  void send(Map<String, dynamic> msg) {
    sent.add(msg);
    other?._in.add(msg);
  }

  @override
  Future<void> close() async {
    await _in.close();
    await other?._in.close();
  }
}

void main() {
  group('codes', () {
    test('a code is four distinct-looking pictures and back', () {
      expect(codePictures.toSet(), hasLength(16));
      expect(animals.toSet(), hasLength(16));
      expect(codeToPictures('3f0a'), ['🌙', '🚲', '🍎', '🌈']);
      expect(picturesToCode([3, 15, 0, 10]), '3f0a');
    });
  });

  group('match flow', () {
    test('host and guest get linked after the host says yes', () async {
      final signal = FakeSignal();
      final t = Together(signal, FakeLinks());
      final host = HostMatch(t);
      final code = await host.open();
      final joined = host.events.firstWhere((e) => e is Joined);

      final guest = GuestMatch(t);
      expect(await guest.join(code), 5);
      expect((await joined as Joined).animal, 5);
      final guestLink = guest.connect();
      final hostLink = await host.accept();
      final g = await guestLink;
      final got = g.messages.first;
      hostLink.send({'t': 'wave'});
      expect(await got, {'t': 'wave'});
      // both left the meeting point
      await pumpEventQueue();
      expect(signal.matches, isEmpty);
    });

    test('a rejected guest learns it', () async {
      final signal = FakeSignal();
      final t = Together(signal, FakeLinks());
      final host = HostMatch(t);
      final code = await host.open();
      final guest = GuestMatch(t);
      await guest.join(code);
      final linked = guest.connect();
      await host.reject();
      await expectLater(
        linked,
        throwsA(
          isA<MatchError>().having(
            (e) => e.failure,
            'failure',
            MatchFailure.gone,
          ),
        ),
      );
      await host.close();
    });

    test('a wrong code', () async {
      final t = Together(FakeSignal(), FakeLinks());
      await expectLater(
        GuestMatch(t).join('ffff'),
        throwsA(
          isA<MatchError>().having(
            (e) => e.failure,
            'f',
            MatchFailure.noSuchCode,
          ),
        ),
      );
    });
  });

  group('screen', () {
    Future<void> openScreen(WidgetTester tester, Together t) async {
      await tester.pumpWidget(MaterialApp(home: TogetherScreen(together: t)));
      await tester.pump();
    }

    testWidgets('host shows the code, sees the animal, says yes, waves', (
      tester,
    ) async {
      final signal = FakeSignal();
      final links = FakeLinks();
      final t = Together(signal, links);
      await tester.runAsync(() async {
        await openScreen(tester, t);
        await tester.tap(find.byKey(const ValueKey('together-open')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        expect(find.text('Show your friend these pictures!'), findsOneWidget);
        expect(find.byKey(const ValueKey('code-3')), findsOneWidget);

        // a friend joins with the code
        final guest = GuestMatch(t);
        await guest.join('3f0a');
        final guestLink = guest.connect();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        expect(find.text('wants to play'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('together-yes')));
        final g = await guestLink;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        expect(find.byKey(const ValueKey('wave-button')), findsOneWidget);

        final waved = g.messages.first;
        await tester.tap(find.byKey(const ValueKey('wave-button')));
        await tester.pump();
        expect(await waved, {'t': 'wave'});
        // the friend waves back
        g.send({'t': 'wave'});
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('wave-friend-1')), findsOneWidget);
      });
    });

    testWidgets('host says no: the code waits for the next friend', (
      tester,
    ) async {
      final signal = FakeSignal();
      final t = Together(signal, FakeLinks());
      await tester.runAsync(() async {
        await openScreen(tester, t);
        await tester.tap(find.byKey(const ValueKey('together-open')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        final stranger = GuestMatch(t);
        await stranger.join('3f0a');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('together-no')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        expect(find.text('Show your friend these pictures!'), findsOneWidget);
        expect(signal.matches['3f0a']!.guest, isNull);
        expect(
          signal.calls,
          isNot(contains('send')),
          reason: 'no offer to a stranger',
        );
      });
    });

    testWidgets('guest types the code, waits for yes, gets linked', (
      tester,
    ) async {
      final signal = FakeSignal();
      final t = Together(signal, FakeLinks());
      await tester.runAsync(() async {
        final host = HostMatch(t);
        await host.open(); // 3f0a
        await openScreen(tester, t);
        await tester.tap(find.byKey(const ValueKey('together-join')));
        await tester.pump();
        // a wrong picture first, then undo
        await tester.tap(find.byKey(const ValueKey('together-pic-1')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('together-back')));
        await tester.pump();
        for (final i in [3, 15, 0, 10]) {
          await tester.tap(find.byKey(ValueKey('together-pic-$i')));
          await tester.pump();
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        expect(find.text('Wait until your friend says yes.'), findsOneWidget);
        final link = await host.accept();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        expect(find.byKey(const ValueKey('wave-button')), findsOneWidget);
        await link.close();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        expect(find.text('Your friend is not there any more.'), findsOneWidget);
      });
    });

    testWidgets('a mistyped code: try again right there', (tester) async {
      final t = Together(FakeSignal(), FakeLinks());
      await tester.runAsync(() async {
        await openScreen(tester, t);
        await tester.tap(find.byKey(const ValueKey('together-join')));
        await tester.pump();
        for (final i in [1, 1, 1, 1]) {
          await tester.tap(find.byKey(ValueKey('together-pic-$i')));
          await tester.pump();
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        expect(
          find.text("Those pictures don't match. Try again!"),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('together-pic-0')), findsOneWidget);
      });
    });

    testWidgets('offline: says so and offers to try again', (tester) async {
      final signal = FakeSignal()..offline = true;
      final t = Together(signal, FakeLinks());
      await tester.runAsync(() async {
        await openScreen(tester, t);
        await tester.tap(find.byKey(const ValueKey('together-open')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        expect(find.text('No internet connection.'), findsOneWidget);
        signal.offline = false;
        await tester.tap(find.byKey(const ValueKey('together-again')));
        await tester.pump();
        expect(find.byKey(const ValueKey('together-open')), findsOneWidget);
      });
    });
  });

  group('layout', () {
    for (final (name, size, text) in [
      ('small portrait', const Size(320, 568), 1.0),
      ('tiny landscape', const Size(568, 320), 1.0),
      ('large text', const Size(360, 640), 2.0),
      ('tablet landscape', const Size(1280, 800), 1.0),
    ]) {
      testWidgets('every step fits: $name', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final signal = FakeSignal();
        final t = Together(signal, FakeLinks());
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(text),
                ),
                child: TogetherScreen(together: t),
              ),
            ),
          );
          await tester.pump();
          // the code, then a guest's animal
          await tester.tap(find.byKey(const ValueKey('together-open')));
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
          expect(find.byKey(const ValueKey('code-3')), findsOneWidget);
          await GuestMatch(t).join('3f0a');
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          expect(find.byKey(const ValueKey('together-yes')), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('together-yes')));
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        });
        // typing a code
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(text),
              ),
              child: TogetherScreen(
                key: const ValueKey('second'),
                together: Together(FakeSignal(), FakeLinks()),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('together-join')));
        await tester.pump();
        for (var i = 0; i < 16; i++) {
          expect(find.byKey(ValueKey('together-pic-$i')), findsOneWidget);
        }
        await tester.tap(
          find.byKey(const ValueKey('together-pic-15')),
          warnIfMissed: true,
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('typed-0')), findsOneWidget);
      });
    }
  });
}
