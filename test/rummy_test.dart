import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/rummy/rummy_hase.dart';
import 'package:phoneme_party/rummy/rummy_rules.dart';

// suits: 0 ♣, 1 ♥, 2 ♠, 3 ♦
int c(int suit, int rank, [int deck = 0]) =>
    deck * deckSize + suit * 13 + rank - 1;
int joker([int i = 0]) => 2 * deckSize + i;

/// A game with these hands and this pile; the stock is the rest.
RummyGame rigged(
  List<int> p0,
  List<int> p1, {
  List<int> pile = const [],
  RummyRules rules = const RummyRules(),
  int turn = 0,
}) {
  final g = RummyGame(rules, rng: math.Random(1));
  final used = {...p0, ...p1, ...pile};
  g.hands = [
    [...p0],
    [...p1],
  ];
  g.pile
    ..clear()
    ..addAll(pile);
  g.stock
    ..clear()
    ..addAll([
      for (var i = 0; i < rules.cardCount; i++)
        if (!used.contains(i)) i,
    ]);
  g.turn = turn;
  return g;
}

void checkCards(RummyGame g) {
  final all = [
    ...g.stock,
    ...g.pile,
    for (final h in g.hands) ...h,
    for (final m in g.table) ...m.cards,
  ];
  expect(all.length, g.rules.cardCount);
  expect(all.toSet().length, g.rules.cardCount);
}

void main() {
  group('melds', () {
    test('sets', () {
      expect(Meld.of([c(0, 7), c(1, 7), c(2, 7)])?.points, 21);
      expect(Meld.of([c(0, 1), c(1, 1), c(2, 1), c(3, 1)])?.points, 44);
      expect(Meld.of([c(0, 12), c(1, 12), joker()])?.points, 30);
      // the same suit twice, five cards, two cards only
      expect(Meld.of([c(0, 7), c(0, 7, 1), c(2, 7)]), isNull);
      expect(Meld.of([c(0, 7), c(1, 7), c(2, 7), c(3, 7), joker()]), isNull);
      expect(Meld.of([c(0, 7), c(1, 7)]), isNull);
    });

    test('runs', () {
      final r = Meld.of([c(1, 5), c(1, 3), c(1, 4)])!;
      expect(r.isRun, isTrue);
      expect(r.cards, [c(1, 3), c(1, 4), c(1, 5)]);
      expect(r.points, 12);
      expect(Meld.of([c(1, 1), c(1, 2), c(1, 3)])?.points, 6);
      expect(Meld.of([c(1, 12), c(1, 13), c(1, 1)])?.points, 31);
      // no corner, no mixed suits, no gaps without a joker
      expect(Meld.of([c(1, 13), c(1, 1), c(1, 2)]), isNull);
      expect(Meld.of([c(1, 3), c(1, 4), c(2, 5)]), isNull);
      expect(Meld.of([c(1, 3), c(1, 4), c(1, 6)]), isNull);
    });

    test('jokers fill gaps, then go above, then below', () {
      final gap = Meld.of([c(1, 3), joker(), c(1, 5)])!;
      expect(gap.cards, [c(1, 3), joker(), c(1, 5)]);
      final up = Meld.of([c(1, 3), c(1, 4), joker()])!;
      expect((up.low, up.high), (3, 5));
      final down = Meld.of([c(1, 13), c(1, 1), joker()])!;
      expect((down.low, down.high), (12, 14));
      // more jokers than real cards
      expect(Meld.of([c(1, 3), joker(0), joker(1)]), isNull);
      expect(Meld.of([c(1, 3), c(1, 4), joker(0), joker(1)])?.points, 18);
    });

    test('lay off', () {
      final r = Meld.of([c(1, 3), c(1, 4), c(1, 5)])!;
      expect(r.withCard(c(1, 6))?.high, 6);
      expect(r.withCard(c(1, 2))?.low, 2);
      expect(r.withCard(c(1, 7)), isNull);
      expect(r.withCard(c(2, 6)), isNull);
      expect(r.withCard(joker())?.high, 6);
      final low = Meld.of([c(1, 2), c(1, 3), c(1, 4)])!;
      expect(low.withCard(c(1, 1))?.low, 1);
      final high = Meld.of([c(1, 11), c(1, 12), c(1, 13)])!;
      expect(high.withCard(c(1, 1))?.high, 14);
      final s = Meld.of([c(0, 9), c(1, 9), c(2, 9)])!;
      expect(s.withCard(c(3, 9))?.cards.length, 4);
      expect(s.withCard(c(0, 9, 1)), isNull);
      expect(s.withCard(c(3, 9))!.withCard(joker()), isNull);
    });

    test('swap a joker', () {
      final r = Meld.of([c(1, 3), joker(), c(1, 5)])!;
      final (m, j) = r.swap(c(1, 4))!;
      expect(j, joker());
      expect(m.cards, [c(1, 3), c(1, 4), c(1, 5)]);
      expect(r.swap(c(1, 6)), isNull);
      final s = Meld.of([c(0, 9), c(1, 9), joker()])!;
      expect(s.swap(c(3, 9)), isNotNull);
      expect(s.swap(c(0, 9, 1)), isNull);
    });

    test('json', () {
      final r = Meld.of([c(1, 3), joker(), c(1, 5)])!;
      expect(Meld.fromJson(r.toJson()).toJson(), r.toJson());
      for (final m in <RummyMove>[
        const DrawStock(),
        const DrawPile(),
        const PutBack(),
        const OpenMelds([
          [1, 2, 3],
        ]),
        const LayMeld([4, 5, 6]),
        const LayOff(1, 2),
        const SwapJoker(3, 0),
        const Discard(7),
        const NextRound(),
      ]) {
        expect(RummyMove.fromJson(m.toJson())?.toJson(), m.toJson());
      }
      expect(RummyMove.fromJson({'m': 'lay', 'card': 'x'}), isNull);
      expect(RummyMove.fromJson({'m': 'fly'}), isNull);
    });
  });

  group('game', () {
    test('deals 13 each and one on the pile', () {
      final g = RummyGame(const RummyRules(), rng: math.Random(3));
      expect(g.hands.map((h) => h.length), [13, 13]);
      expect(g.pile.length, 1);
      expect(g.stock.length, 110 - 27);
      checkCards(g);
    });

    test('a turn: draw, then discard', () {
      final g = rigged([c(0, 2), c(1, 9)], [c(2, 2), c(3, 9)]);
      expect(g.apply(0, const Discard(0)), RummyNo.drawFirst);
      expect(g.apply(1, const DrawStock()), RummyNo.notYourTurn);
      expect(g.apply(0, const DrawStock()), isNull);
      expect(g.apply(0, const DrawStock()), RummyNo.drewAlready);
      expect(g.apply(0, Discard(c(1, 9))), isNull);
      expect(g.turn, 1);
      expect(g.pile.last, c(1, 9));
      checkCards(g);
    });

    test('the first melds need 30 points', () {
      final low = [c(1, 2), c(1, 3), c(1, 4)]; // 9
      final kings = [c(0, 13), c(1, 13), c(2, 13)]; // 30
      final g = rigged([...low, ...kings, c(1, 5)], [c(0, 5)]);
      g.apply(0, const DrawStock());
      expect(g.apply(0, OpenMelds([low])), RummyNo.tooFewPoints);
      expect(g.apply(0, LayMeld(low)), RummyNo.openFirst);
      expect(g.apply(0, OpenMelds([low, kings])), isNull);
      expect(g.opened[0], isTrue);
      expect(g.table.length, 2);
      // now single melds and lay offs are fine
      expect(g.apply(0, LayOff(c(1, 5), 0)), isNull);
      expect(g.table[0].cards.length, 4);
      checkCards(g);
    });

    test('a different minimum, or none', () {
      final low = [c(1, 2), c(1, 3), c(1, 4)];
      final none = rigged(
        [...low, c(3, 5)],
        [c(0, 5)],
        rules: const RummyRules(openPoints: 0),
      );
      none.apply(0, const DrawStock());
      expect(none.apply(0, OpenMelds([low])), isNull);
      final kings = [c(0, 13), c(1, 13), c(2, 13)];
      final forty = rigged(
        [...kings, c(3, 5)],
        [c(0, 5)],
        rules: const RummyRules(openPoints: 40),
      );
      forty.apply(0, const DrawStock());
      expect(forty.apply(0, OpenMelds([kings])), RummyNo.tooFewPoints);
    });

    test('the card from the pile must be laid out before you are out', () {
      final kings = [c(0, 13), c(1, 13)];
      final g = rigged(
        [...kings, c(3, 5), c(3, 6)],
        [c(0, 5)],
        pile: [c(2, 13)],
      );
      expect(g.apply(0, const DrawPile()), isNull);
      expect(g.apply(0, Discard(c(3, 5))), RummyNo.mustUsePile);
      expect(
        g.apply(
          0,
          OpenMelds([
            [c(0, 13), c(1, 13), c(2, 13)],
          ]),
        ),
        isNull,
      );
      expect(g.apply(0, Discard(c(3, 5))), isNull);
      checkCards(g);
    });

    test('a card from the pile that does not fit goes back', () {
      final g = rigged([c(3, 5), c(3, 6)], [c(0, 5)], pile: [c(2, 13)]);
      g.apply(0, const DrawPile());
      expect(
        g.apply(
          0,
          OpenMelds([
            [c(3, 5), c(3, 6), c(2, 13)],
          ]),
        ),
        RummyNo.notAMeld,
      );
      expect(g.apply(0, const PutBack()), isNull);
      expect(g.pile.last, c(2, 13));
      expect(g.apply(0, const DrawPile()), RummyNo.pileEmpty);
      expect(g.apply(0, const DrawStock()), isNull);
      expect(g.apply(0, Discard(c(3, 5))), isNull);
      checkCards(g);
    });

    test('once out, the pile card may not be thrown back', () {
      final g = rigged([c(3, 5), c(3, 6)], [c(0, 5)], pile: [c(2, 13)]);
      g.opened[0] = true;
      g.apply(0, const DrawPile());
      expect(g.apply(0, Discard(c(2, 13))), RummyNo.keepThatCard);
      expect(g.apply(0, const PutBack()), RummyNo.keepThatCard);
      expect(g.apply(0, Discard(c(3, 5))), isNull);
    });

    test('swap a joker on the table', () {
      final g = rigged([c(1, 4), c(0, 2), c(0, 9)], [c(0, 5)]);
      g.table.add(Meld.of([c(1, 3), joker(), c(1, 5)])!);
      g.owners.add(1);
      g.stock.remove(c(1, 3));
      g.stock.remove(c(1, 5));
      g.stock.remove(joker());
      g.apply(0, const DrawStock());
      expect(g.apply(0, SwapJoker(c(1, 4), 0)), RummyNo.openFirst);
      g.opened[0] = true;
      expect(g.apply(0, SwapJoker(c(0, 2), 0)), RummyNo.doesNotFit);
      expect(g.apply(0, SwapJoker(c(1, 4), 0)), isNull);
      expect(g.hands[0], contains(joker()));
      expect(g.apply(0, Discard(joker())), RummyNo.keepThatCard);
      expect(g.apply(0, Discard(c(0, 9))), isNull);
      checkCards(g);
    });

    test('the last card thrown ends the round', () {
      final g = rigged([c(3, 2)], [c(0, 5), c(1, 1), joker()]);
      g.opened[0] = true;
      g.table.add(Meld.of([c(3, 3), c(3, 4), c(3, 5)])!);
      g.owners.add(1);
      g.stock.removeWhere([c(3, 3), c(3, 4), c(3, 5)].contains);
      g.apply(0, const DrawStock());
      final drawn = g.hands[0].last;
      expect(g.apply(0, LayOff(c(3, 2), 0)), isNull);
      expect(g.phase, RummyPhase.play);
      expect(g.apply(0, Discard(drawn)), isNull);
      expect(g.phase, RummyPhase.over);
      expect(g.winner, 0);
      expect(g.scores, [0, 5 + 11 + 20]);
      expect(g.apply(1, const DrawStock()), RummyNo.notYourTurn);
      expect(g.view(0).shownHands[1].length, 3);
      expect(g.apply(1, const NextRound()), isNull);
      expect(g.round, 2);
      expect(g.turn, 1); // the other starts now
      expect(g.scores, [0, 36]);
      checkCards(g);
    });

    test('the view hides the other hand', () {
      final g = RummyGame(const RummyRules(), rng: math.Random(5));
      final v = g.view(1);
      expect(v.hand, g.hands[1]);
      expect(v.handCounts, [13, 13]);
      expect(v.shownHands, isEmpty);
      final back = RummyView.fromJson(v.toJson())!;
      expect(back.toJson(), v.toJson());
      expect(RummyView.fromJson({'me': 'x'}), isNull);
    });

    test('an empty stock is the pile shuffled', () {
      final g = rigged([c(0, 2)], [c(0, 5)], pile: [c(1, 2), c(1, 3), c(1, 4)]);
      g.pile.addAll(g.stock);
      g.stock.clear();
      final top = g.pile.last;
      expect(g.apply(0, const DrawStock()), isNull);
      expect(g.pile, [top]);
      checkCards(g);
    });
  });

  group('hase', () {
    test('finds the melds worth most', () {
      final hand = [
        c(0, 13), c(1, 13), c(2, 13), //
        c(1, 9), c(1, 10), c(1, 11),
        c(3, 2), c(0, 6),
      ];
      final m = bestMelds(hand);
      expect(m.length, 2);
      expect(m.fold(0, (s, x) => s + Meld.of(x)!.points), 59);
    });

    test('uses the joker', () {
      final m = bestMelds([c(0, 1), c(1, 1), joker(), c(3, 4)]);
      expect(m.single.length, 3);
      expect(Meld.of(m.single)!.points, 33);
    });

    for (final open in [0, 30, 40]) {
      test('two hasen play to the end (out at $open)', () {
        for (var seed = 0; seed < 40; seed++) {
          final g = RummyGame(
            RummyRules(openPoints: open),
            rng: math.Random(seed),
          );
          var moves = 0;
          while (g.phase != RummyPhase.over) {
            final v = g.view(g.turn);
            final m = haseMove(v);
            final no = g.apply(g.turn, m);
            expect(no, isNull, reason: 'seed $seed: ${m.toJson()} $no');
            checkCards(g);
            expect(++moves, lessThan(3000), reason: 'seed $seed');
            for (final meld in g.table) {
              expect(Meld.of(meld.cards), isNotNull);
            }
          }
        }
      });
    }
  });
}
