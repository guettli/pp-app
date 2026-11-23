import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/net/peer_link.dart';
import 'package:phoneme_party/rummy/rummy_rules.dart';
import 'package:phoneme_party/rummy/rummy_seat.dart';
import 'package:phoneme_party/rummy/rummy_table.dart';

int c(int suit, int rank, [int deck = 0]) =>
    deck * deckSize + suit * 13 + rank - 1;

/// Two ends of a link in memory.
class PairLink implements PeerLink {
  PairLink._();
  static (PairLink, PairLink) make() {
    final a = PairLink._();
    final b = PairLink._();
    a._other = b;
    b._other = a;
    return (a, b);
  }

  late PairLink _other;
  final _in = StreamController<Map<String, dynamic>>();
  @override
  Stream<Map<String, dynamic>> get messages => _in.stream;
  @override
  void send(Map<String, dynamic> msg) {
    if (!_other._in.isClosed) _other._in.add(msg);
  }

  @override
  Future<void> close() async {
    unawaited(_in.close());
    unawaited(_other._in.close());
  }
}

/// Gives player 0 [hand] and [nextDraw] on top of the stock; the cards
/// in [away] are nowhere (the test puts them on the table).
void rig(
  RummyGame g,
  List<int> hand, {
  int? nextDraw,
  List<int> away = const [],
}) {
  final others = [
    for (var i = 0; i < g.rules.cardCount; i++)
      if (!hand.contains(i) && i != nextDraw && !away.contains(i)) i,
  ]..shuffle(math.Random(1));
  g.hands[0]
    ..clear()
    ..addAll(hand);
  g.hands[1]
    ..clear()
    ..addAll(others.take(13));
  others.removeRange(0, 13);
  g.pile
    ..clear()
    ..add(others.removeLast());
  g.stock
    ..clear()
    ..addAll(others);
  if (nextDraw != null) g.stock.add(nextDraw);
}

Widget app(RummySeat seat, {Size? size, double text = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      size: size ?? const Size(400, 800),
      textScaler: TextScaler.linear(text),
    ),
    child: Scaffold(
      backgroundColor: const Color(0xFF14143A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: RummyTable(seat: seat, me: '🏠', friend: '🐰', onGone: () {}),
        ),
      ),
    ),
  ),
);

Future<void> tapKey(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(ValueKey(key)));
  await t.pump();
  await t.tap(find.byKey(ValueKey(key)));
  await t.pump();
}

String status(WidgetTester t) =>
    t.widget<Text>(find.byKey(const ValueKey('rummy-status'))).data!;

void main() {
  testWidgets('against the Hase: draw, lay out 30 points, discard', (
    tester,
  ) async {
    final seat = HaseSeat(
      const RummyRules(),
      rng: math.Random(7),
      pause: const Duration(milliseconds: 10),
    );
    addTearDown(seat.dispose);
    final kings = [c(0, 13), c(1, 13), c(2, 13)];
    final low = [c(1, 2), c(1, 3), c(1, 4)];
    final rest = [
      c(0, 5),
      c(2, 8),
      c(3, 10),
      c(0, 2),
      c(2, 4),
      c(3, 6),
      c(0, 9),
    ];
    rig(seat.game, [...kings, ...low, ...rest], nextDraw: c(3, 7));
    await tester.pumpWidget(app(seat));
    expect(status(tester), startsWith('Draw a card'));

    // nothing to do with cards before drawing
    await tapKey(tester, 'rummy-card-${c(0, 5)}');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('rummy-discard')))
          .onPressed,
      isNull,
    );
    await tapKey(tester, 'rummy-card-${c(0, 5)}');

    await tapKey(tester, 'rummy-stock');
    expect(find.byKey(ValueKey('rummy-card-${c(3, 7)}')), findsOneWidget);
    expect(status(tester), startsWith('Lay out cards worth 30'));

    // the low run alone is not enough
    for (final x in low) {
      await tapKey(tester, 'rummy-card-$x');
    }
    await tapKey(tester, 'rummy-meld');
    expect(find.text('To lay out: 9 of 30 points'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('rummy-open')))
          .onPressed,
      isNull,
    );
    // not a meld
    await tapKey(tester, 'rummy-card-${c(0, 5)}');
    await tapKey(tester, 'rummy-card-${c(2, 8)}');
    await tapKey(tester, 'rummy-card-${c(3, 10)}');
    await tapKey(tester, 'rummy-meld');
    expect(status(tester), 'That is not a set or a run.');
    for (final x in [c(0, 5), c(2, 8), c(3, 10)]) {
      await tapKey(tester, 'rummy-card-$x');
    }
    for (final x in kings) {
      await tapKey(tester, 'rummy-card-$x');
    }
    await tapKey(tester, 'rummy-meld');
    expect(find.text('To lay out: 39 of 30 points'), findsOneWidget);
    await tapKey(tester, 'rummy-open');
    expect(seat.game.opened[0], isTrue);
    expect(seat.game.table, hasLength(2));
    expect(find.byKey(const ValueKey('rummy-meld-1')), findsOneWidget);

    // lay off: the 5♥ is not in the hand, the ♥ run takes no ♣
    await tapKey(tester, 'rummy-card-${c(0, 5)}');
    await tapKey(tester, 'rummy-meld-0');
    expect(status(tester), 'That does not fit here.');
    await tapKey(tester, 'rummy-discard');
    expect(seat.game.pile.last, c(0, 5));
    expect(seat.game.turn, 1);
    expect(status(tester), 'Wait\u00a0…');

    // the Hase plays its turn
    for (var i = 0; i < 100 && seat.game.turn == 1; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(seat.game.turn, 0);
    expect(status(tester), startsWith('Draw a card'));
  });

  testWidgets('the card from the pile goes back when it does not fit', (
    tester,
  ) async {
    final seat = HaseSeat(const RummyRules(), rng: math.Random(3));
    addTearDown(seat.dispose);
    final g = seat.game;
    rig(g, [c(0, 2), c(1, 9), c(2, 4)]);
    final top = g.pile.last;
    await tester.pumpWidget(app(seat));
    await tapKey(tester, 'rummy-pile');
    expect(g.hands[0], contains(top));
    await tapKey(tester, 'rummy-card-${c(0, 2)}');
    await tapKey(tester, 'rummy-discard');
    expect(status(tester), startsWith('The card from the discard pile'));
    await tapKey(tester, 'rummy-back');
    expect(g.pile.last, top);
    await tapKey(tester, 'rummy-pile'); // not again
    expect(g.hands[0], isNot(contains(top)));
    await tapKey(tester, 'rummy-stock');
    expect(g.hands[0], hasLength(4));
  });

  testWidgets('the round is over: the hands, the points, another round', (
    tester,
  ) async {
    final seat = HaseSeat(const RummyRules(), rng: math.Random(4));
    addTearDown(seat.dispose);
    final g = seat.game;
    final run = [c(0, 3, 1), c(0, 4, 1), c(0, 5, 1)];
    rig(g, [c(0, 2)], away: run);
    g.opened[0] = true;
    g.table.add(Meld.of(run)!);
    g.owners.add(1);
    await tester.pumpWidget(app(seat));
    await tapKey(tester, 'rummy-stock');
    final drawn = g.hands[0].last;
    await tapKey(tester, 'rummy-card-${c(0, 2)}');
    await tapKey(tester, 'rummy-meld-0');
    expect(g.table[0].cards.first, c(0, 2));
    await tapKey(tester, 'rummy-card-$drawn');
    await tapKey(tester, 'rummy-discard');
    expect(find.text('You won!'), findsOneWidget);
    expect(g.scores[1], greaterThan(0));
    await tapKey(tester, 'rummy-next');
    expect(g.round, 2);
    expect(find.byKey(const ValueKey('rummy-stock')), findsOneWidget);
    // the Hase starts this one
    expect(status(tester), 'Wait\u00a0…');
    await tester.pump(const Duration(seconds: 30));
    expect(g.turn, 0);
  });

  testWidgets('over the link: the guest sees its view and moves', (
    tester,
  ) async {
    final (a, b) = PairLink.make();
    late HostSeat host;
    late GuestSeat guest;
    await tester.runAsync(() async {
      host = HostSeat(a, const RummyRules(), rng: math.Random(9));
      guest = GuestSeat(b);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    addTearDown(host.dispose);
    addTearDown(guest.dispose);
    expect(guest.view!.hand, host.game.hands[1]);
    expect(guest.view!.me, 1);
    // the host's turn: the guest waits
    await tester.pumpWidget(app(guest));
    expect(status(tester), 'Wait\u00a0…');
    await tester.runAsync(() async {
      host.move(const DrawStock());
      host.move(Discard(host.game.hands[0].first));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    expect(status(tester), startsWith('Draw a card'));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('rummy-stock')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    expect(host.game.hands[1], hasLength(14));
    expect(guest.view!.hand, hasLength(14));
    // a refused move says why
    await tester.runAsync(() async {
      guest.move(const DrawPile());
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    expect(status(tester), 'You drew already.');
    // the host's hand never goes to the guest
    expect(guest.view!.shownHands, isEmpty);
    await tester.runAsync(() async {
      await a.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    expect(guest.gone, isTrue);
    expect(find.byKey(const ValueKey('together-again')), findsOneWidget);
  });

  group('layout', () {
    for (final (name, size, text) in [
      ('small portrait', const Size(320, 568), 1.0),
      ('tiny landscape', const Size(568, 320), 1.0),
      ('large text', const Size(360, 640), 2.0),
      ('tablet landscape', const Size(1280, 800), 1.0),
    ]) {
      testWidgets('the table fits: $name', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final seat = HaseSeat(const RummyRules(), rng: math.Random(2));
        addTearDown(seat.dispose);
        final g = seat.game;
        // a full table and a big hand
        final melds = [
          for (var r = 1; r <= 8; r++) [c(0, r, 1), c(1, r, 1), c(2, r, 1)],
        ];
        rig(
          g,
          [for (var r = 1; r <= 13; r++) c(3, r)],
          away: [for (final m in melds) ...m],
        );
        for (final m in melds) {
          g.table.add(Meld.of(m)!);
          g.owners.add(m.length % 2);
        }
        await tester.pumpWidget(app(seat, size: size, text: text));
        await tapKey(tester, 'rummy-stock');
        expect(tester.takeException(), isNull);
        final hand = g.hands[0];
        for (final x in hand.take(3)) {
          await tester.ensureVisible(find.byKey(ValueKey('rummy-card-$x')));
          await tapKey(tester, 'rummy-card-$x');
        }
        await tester.ensureVisible(find.byKey(const ValueKey('rummy-meld')));
        expect(find.byKey(const ValueKey('rummy-discard')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
