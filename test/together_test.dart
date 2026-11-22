import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  /// Joins that fail as offline (the answer got lost) before one works.
  var lostJoins = 0;
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
    if (m.guest == 'g-$nonce') return (token: m.guest!, animal: animal);
    if (m.guest != null) throw const MatchError(MatchFailure.taken);
    m.guest = 'g-$nonce';
    m.base = m.msgs.length;
    m.post('service', {'type': 'joined', 'animal': animal});
    m.joined = m.msgs.length;
    if (lostJoins > 0) {
      lostJoins--;
      throw const MatchError(MatchFailure.offline, 'answer lost');
    }
    return (token: m.guest!, animal: animal);
  }

  @override
  Future<void> reject(String code, String token) async {
    _check('reject');
    final m = _get(code, token);
    m.guest = null;
  }

  @override
  Future<void> send(
    String code,
    String token,
    Map<String, dynamic> msg, {
    String? id,
    int? guest,
  }) async {
    _check('send');
    final m = _get(code, token);
    if (token == m.host &&
        guest != null &&
        (m.guest == null || m.joined != guest)) {
      throw const MatchError(MatchFailure.taken, 'another guest');
    }
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

class _RealHttp extends HttpOverrides {}

class _Broken extends FakeSignal {
  @override
  Future<({List<SignalMsg> msgs, int next})> recv(
    String code,
    String token,
    int after,
  ) async => throw TypeError();
}

class _M {
  _M(this.host);
  final String host;
  String? guest;
  int base = 0;
  int joined = 0;
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

  Map<String, dynamic>? accepted;

  @override
  Future<void> accept(Map<String, dynamic> answer) async {
    if (answer['sdp'] != description['sdp']) {
      throw StateError('an answer to another offer');
    }
    accepted = answer;
  }

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
  final _in = StreamController<Map<String, dynamic>>();
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
    if (!_in.isClosed) unawaited(_in.close());
    if (other != null && !other!._in.isClosed) unawaited(other!._in.close());
  }
}

Duration _short(int n) => const Duration(milliseconds: 5);

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
      final t = Together(signal, FakeLinks(), retryPause: _short);
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
      final t = Together(signal, FakeLinks(), retryPause: _short);
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
      final t = Together(FakeSignal(), FakeLinks(), retryPause: _short);
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

    test(
      'the guest leaves while the host connects: no link, code open',
      () async {
        final signal = FakeSignal();
        final t = Together(signal, FakeLinks(), retryPause: _short);
        final host = HostMatch(t);
        final code = await host.open();
        final guest = GuestMatch(t);
        await guest.join(code);
        while (host.waiting == null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final accepting = host.accept();
        await guest.close(); // gone before it answered
        // gone (it heard "left") or taken (the service refused the offer)
        await expectLater(
          accepting,
          throwsA(
            isA<MatchError>().having(
              (e) => e.failure,
              'f',
              isNot(MatchFailure.offline),
            ),
          ),
        );
        while (host.waiting != null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(signal.matches[code]!.guest, isNull, reason: 'code open again');
        await host.close();
      },
    );

    test('another guest came meanwhile: the offer is not for it', () async {
      final signal = FakeSignal();
      final t = Together(signal, FakeLinks(), retryPause: _short);
      final host = HostMatch(t);
      final code = await host.open();
      await GuestMatch(t).join(code, nonce: 'a' * 32);
      while (host.waiting == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // the first guest goes and a stranger joins before the host's
      // phone heard of it
      final m = signal.matches[code]!;
      m.guest = null;
      await GuestMatch(t).join(code, nonce: 'b' * 32);
      // taken (the service refused it) or gone (the phone heard of it)
      await expectLater(host.accept(), throwsA(isA<MatchError>()));
      expect(
        m.msgs.where((x) => x.from == 'host'),
        isEmpty,
        reason: 'no offer sent',
      );
      await host.close();
    });

    test('closed while opening: the match is left, no reader stays', () async {
      final signal = FakeSignal();
      final t = Together(signal, FakeLinks(), retryPause: _short);
      final host = HostMatch(t);
      final opening = expectLater(host.open(), throwsA(isA<MatchError>()));
      await host.close();
      await opening;
      await pumpEventQueue();
      expect(signal.matches, isEmpty);
      final recvs = signal.calls.where((c) => c == 'recv').length;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(signal.calls.where((c) => c == 'recv').length, recvs);
    });

    test('a lost join answer: asked again, same guest', () async {
      final signal = FakeSignal()..lostJoins = 1;
      final t = Together(signal, FakeLinks(), retryPause: _short);
      final host = HostMatch(t);
      final code = await host.open();
      expect(await GuestMatch(t).join(code), 5);
      expect(signal.calls.where((c) => c == 'join'), hasLength(2));
      await host.close();
    });

    test('odd answers from the service end in a MatchError', () async {
      final r = SignalReader(_Broken(), 'abcd', 't', retryPause: _short);
      await expectLater(
        r.messages.toList(),
        throwsA(
          isA<MatchError>().having((e) => e.failure, 'f', MatchFailure.offline),
        ),
      );
    });
  });

  group('http', () {
    late HttpServer server;
    late HttpMatchSignal signal;
    final answers = <String, (int, Object?)>{};
    HttpOverrides? before;
    setUp(() async {
      // flutter_test answers every HttpClient with 400; this test talks to
      // a real server on localhost
      before = HttpOverrides.current;
      HttpOverrides.global = _RealHttp();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body = jsonDecode(await utf8.decoder.bind(req).join());
        final route = req.uri.path.replaceFirst('/pp-app/api/', '');
        final (st, json) = answers[route] ?? (404, null);
        req.response.statusCode = st;
        if (json != null) {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(json));
        }
        if (route == 'match/send') answers['seen'] = (0, body);
        await req.response.close();
      });
      signal = HttpMatchSignal(
        base: Uri.parse('http://127.0.0.1:${server.port}/pp-app/api/'),
      );
    });
    tearDown(() async {
      HttpOverrides.global = before;
      await server.close(force: true);
    });

    test('routes, bodies and status codes', () async {
      answers['match/new'] = (201, {'code': '3f0a', 'token': 'h'});
      expect((await signal.create()).code, '3f0a');
      answers['match/join'] = (200, {'token': 'g', 'animal': 7});
      expect((await signal.join('3f0a', 'n' * 32)).animal, 7);
      answers['match/send'] = (204, null);
      await signal.send('3f0a', 'h', {'type': 'offer'}, id: 'o', guest: 3);
      expect(answers['seen']!.$2, {
        'code': '3f0a',
        'token': 'h',
        'msg': {'type': 'offer'},
        'id': 'o',
        'guest': 3,
      });
      answers['match/recv'] = (
        200,
        {
          'msgs': [
            {
              'seq': 1,
              'from': 'service',
              'msg': {'type': 'joined', 'animal': 2},
            },
          ],
          'next': 1,
        },
      );
      final r = await signal.recv('3f0a', 'h', 0);
      expect(r.msgs.single.msg['animal'], 2);
      expect(r.next, 1);
      answers['turn'] = (
        200,
        {
          'iceServers': [
            {
              'urls': ['stun:x'],
            },
          ],
          'ttl': 3600,
        },
      );
      expect(await signal.iceServers(), hasLength(1));
    });

    test('failures', () async {
      Future<MatchFailure> failure(Future<void> f) async {
        try {
          await f;
        } on MatchError catch (e) {
          return e.failure;
        }
        fail('no error');
      }

      answers.clear();
      expect(
        await failure(signal.join('ffff', 'n' * 32)),
        MatchFailure.noSuchCode,
      );
      expect(await failure(signal.send('ffff', 't', {})), MatchFailure.gone);
      answers['match/join'] = (409, null);
      expect(await failure(signal.join('ffff', 'n' * 32)), MatchFailure.taken);
      answers['match/new'] = (503, null);
      expect(await failure(signal.create()), MatchFailure.offline);
      // a captive portal answers 200 with HTML
      answers['match/recv'] = (200, null);
      expect(await failure(signal.recv('ffff', 't', 0)), MatchFailure.offline);
      // odd JSON
      answers['match/recv'] = (200, {'msgs': 'no'});
      expect(await failure(signal.recv('ffff', 't', 0)), MatchFailure.offline);
      await server.close(force: true);
      expect(await failure(signal.create()), MatchFailure.offline);
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
      final t = Together(signal, links, retryPause: _short);
      await tester.runAsync(() async {
        await openScreen(tester, t);
        await tester.tap(find.byKey(const ValueKey('together-open')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        expect(
          find.text('Show these pictures to the other child!'),
          findsOneWidget,
        );
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

    testWidgets('the match ends while connecting: the screen says so', (
      tester,
    ) async {
      final signal = FakeSignal();
      final t = Together(signal, FakeLinks(), retryPause: _short);
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(home: TogetherScreen(together: t)));
        await tester.tap(find.byKey(const ValueKey('together-open')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        final guest = GuestMatch(t);
        await guest.join('3f0a');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        // yes, twice (a double tap), and the match expires right then
        await tester.tap(find.byKey(const ValueKey('together-yes')));
        await tester.tap(
          find.byKey(const ValueKey('together-yes')),
          warnIfMissed: false,
        );
        signal.matches.remove('3f0a');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
        expect(
          find.text('These pictures are too old. Start a new game!'),
          findsOneWidget,
        );
        expect(signal.calls.where((c) => c == 'send').length, lessThan(2));
        // and stays there
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
        expect(find.byKey(const ValueKey('together-again')), findsOneWidget);
      });
    });

    testWidgets('host says no: the code waits for the next friend', (
      tester,
    ) async {
      final signal = FakeSignal();
      final t = Together(signal, FakeLinks(), retryPause: _short);
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
        expect(
          find.text('Show these pictures to the other child!'),
          findsOneWidget,
        );
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
      final t = Together(signal, FakeLinks(), retryPause: _short);
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
        expect(
          find.text('Wait until the other child says yes.'),
          findsOneWidget,
        );
        while (host.waiting == null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final link = await host.accept();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        expect(find.byKey(const ValueKey('wave-button')), findsOneWidget);
        await link.close();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        expect(
          find.text('The other child is not there any more.'),
          findsOneWidget,
        );
      });
    });

    testWidgets('a mistyped code: try again right there', (tester) async {
      final t = Together(FakeSignal(), FakeLinks(), retryPause: _short);
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
      final t = Together(signal, FakeLinks(), retryPause: _short);
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
        final t = Together(signal, FakeLinks(), retryPause: _short);
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
                together: Together(
                  FakeSignal(),
                  FakeLinks(),
                  retryPause: _short,
                ),
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
