import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/data/progress.dart';
import 'package:phoneme_party/rummy/hand_rummy.dart';
import 'package:phoneme_party/rummy/hand_rummy_screen.dart';
import 'package:phoneme_party/rummy/rummy_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

// suits: 0 ♣, 1 ♥, 2 ♠, 3 ♦
int c(int suit, int rank, [int deck = 0]) =>
    deck * deckSize + suit * 13 + rank - 1;

HandRummyPuzzle puzzle(
  List<int> hand, {
  List<List<int>> table = const [],
  List<List<int>> melds = const [],
}) => HandRummyPuzzle(
  hand: hand,
  table: [for (final m in table) Meld.of(m)!],
  melds: melds,
  layOffs: const [],
);

void main() {
  test('every deal goes out: its melds first, then its lay-offs', () {
    final rng = math.Random(7);
    var withTable = 0, withJoker = 0;
    for (var i = 0; i < 2000; i++) {
      final p = makeHandRummy(rng);
      expect(p.hand, hasLength(handRummySize));
      final all = [...p.hand, for (final m in p.table) ...m.cards];
      expect(all.toSet(), hasLength(all.length), reason: 'a card twice');
      if (p.table.isNotEmpty) withTable++;
      if (p.hand.any((c) => RummyCard(c).isJoker)) withJoker++;
      final g = HandRummy(p);
      expect(g.openWith(p.melds), isNull, reason: '${p.melds}');
      for (final l in p.layOffs) {
        expect(g.layOff(l.card, l.meld), isNull);
      }
      expect(g.done, isTrue);
    }
    // the kinds of deals all come up
    expect(withTable, greaterThan(1000));
    expect(withTable, lessThan(1800));
    expect(withJoker, greaterThan(400));
  });

  test('first melds of 30 points, from the hand; then lay off', () {
    final run = [c(1, 2), c(1, 3), c(1, 4)]; // 9 points
    final set = [c(0, 13), c(1, 13), c(2, 13)]; // 30
    final g = HandRummy(
      puzzle(
        [...run, ...set, c(1, 5)],
        table: [
          [c(3, 7), c(3, 8), c(3, 9)],
        ],
      ),
    );
    expect(g.lay(run), RummyNo.openFirst);
    expect(g.layOff(c(1, 5), 0), RummyNo.openFirst);
    expect(g.openWith([run]), RummyNo.tooFewPoints);
    expect(g.openWith([run, set]), isNull);
    expect(g.opened, isTrue);
    expect(g.mine, [false, true, true]);
    expect(g.layOff(c(1, 5), 0), RummyNo.doesNotFit);
    expect(g.layOff(c(1, 5), 1), isNull);
    expect(g.done, isTrue);
  });

  test('undo takes moves back, laying out too', () {
    final set = [c(0, 13), c(1, 13), c(2, 13)];
    final g = HandRummy(puzzle([...set, c(3, 13)]));
    expect(g.canUndo, isFalse);
    expect(g.openWith([set]), isNull);
    expect(g.layOff(c(3, 13), 0), isNull);
    expect(g.done, isTrue);
    expect(g.undo(), isTrue);
    expect(g.hand, [c(3, 13)]);
    expect(g.undo(), isTrue);
    expect(g.opened, isFalse);
    expect(g.table, isEmpty);
    expect(g.hand, hasLength(4));
    expect(g.undo(), isFalse);
  });

  test('the hint before laying out: melds, then "lay out now"', () {
    final p = makeHandRummy(math.Random(3));
    final g = HandRummy(p);
    final staged = <List<int>>[];
    for (var k = 0; k < 6; k++) {
      final n = g.next(staged: staged)!;
      if (n.open) break;
      expect(Meld.of(n.cards), isNotNull);
      expect(n.cards.any({for (final m in staged) ...m}.contains), isFalse);
      staged.add(n.cards);
    }
    expect(g.next(staged: staged)!.open, isTrue);
    expect(g.openWith(staged), isNull);
    expect(g.goesOut(), isTrue);
  });

  test('the hint after laying out keeps the way out open', () {
    // 5♥ 6♥ 7♥ 8♥ and 8♣ 8♠: 6-7-8♥ would leave the eights alone
    final out = [c(0, 13), c(1, 13), c(2, 13)];
    final g = HandRummy(
      puzzle([...out, c(1, 5), c(1, 6), c(1, 7), c(1, 8), c(0, 8), c(2, 8)]),
    );
    expect(g.openWith([out]), isNull);
    for (var k = 0; k < 6 && !g.done; k++) {
      final n = g.next()!;
      expect(n.open, isFalse);
      if (n.cards.length == 1) {
        final i = [
          for (var m = 0; m < g.table.length; m++)
            if (g.table[m].withCard(n.cards.single) != null) m,
        ].first;
        expect(g.layOff(n.cards.single, i), isNull);
      } else {
        expect(g.lay(n.cards), isNull);
      }
      expect(g.goesOut(), isTrue);
    }
    expect(g.done, isTrue);
    // the wrong way: lost at once, though moves are left
    while (g.hand.length < 6) {
      g.undo();
    }
    expect(g.lay([c(1, 6), c(1, 7), c(1, 8)]), isNull);
    expect(g.goesOut(), isFalse);
    expect(g.next(), isNull);
  });

  test('set aside the wrong way: lost before laying out', () {
    // 4-5-6-7♥ and 4♣ 4♠: the 4♥ is needed for the fours
    final kings = [c(0, 13), c(1, 13), c(2, 13)];
    final g = HandRummy(
      puzzle([...kings, c(1, 4), c(1, 5), c(1, 6), c(1, 7), c(0, 4), c(2, 4)]),
    );
    expect(g.goesOut(), isTrue);
    expect(
      g.goesOut(
        staged: [
          [c(1, 4), c(1, 5), c(1, 6)],
        ],
      ),
      isFalse,
    );
    expect(
      g.goesOut(
        staged: [
          [c(1, 5), c(1, 6), c(1, 7)],
        ],
      ),
      isTrue,
    );
  });

  test('stuck: laid out, and a card fits nowhere', () {
    final set = [c(0, 13), c(1, 13), c(2, 13)];
    final g = HandRummy(puzzle([...set, c(1, 5)]));
    expect(g.goesOut(), isFalse);
    expect(g.openWith([set]), isNull);
    expect(g.next(), isNull);
  });

  test('the search is quick, also off the way', () {
    final rng = math.Random(9);
    final watch = Stopwatch()..start();
    var checks = 0;
    for (var d = 0; d < 150; d++) {
      final p = makeHandRummy(rng);
      final g = HandRummy(p);
      expect(g.goesOut(), isTrue);
      expect(g.openWith(p.melds), isNull);
      // then random moves, checked each time
      for (var k = 0; k < 12 && !g.done; k++) {
        checks++;
        final can = g.goesOut();
        final n = g.next();
        expect(n != null, can);
        final cards = [...g.hand]..shuffle(rng);
        final card = cards.first;
        final m = rng.nextInt(g.table.length);
        if (g.layOff(card, m) != null && n != null) {
          if (n.cards.length == 1) {
            final i = [
              for (var t = 0; t < g.table.length; t++)
                if (g.table[t].withCard(n.cards.single) != null ||
                    g.table[t].swap(n.cards.single) != null)
                  t,
            ].first;
            expect(g.layOff(n.cards.single, i), isNull);
          } else {
            expect(g.lay(n.cards), isNull);
          }
        }
      }
    }
    // ignore: avoid_print
    print('$checks checks in ${watch.elapsedMilliseconds} ms');
    expect(watch.elapsedMilliseconds, lessThan(checks * 50));
  });

  testWidgets('a deal laid out by taps: three stars without hints', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final progress = await Progress.load();
    // the same deal as the screen's
    final p = makeHandRummy(math.Random(11));
    await t.pumpWidget(
      MaterialApp(
        home: HandRummyScreen(progress: progress, rng: math.Random(11)),
      ),
    );
    Future<void> tap(String key) async {
      await t.ensureVisible(find.byKey(ValueKey(key)));
      await t.tap(find.byKey(ValueKey(key)));
      await t.pump();
    }

    expect(find.textContaining('30'), findsWidgets);
    for (final m in p.melds) {
      for (final id in m) {
        await tap('hr-card-$id');
      }
      await tap('hr-meld');
    }
    await tap('hr-open');
    for (final l in p.layOffs) {
      await tap('hr-card-${l.card}');
      await tap('hr-meld-${l.meld}');
    }
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('round-again')), findsOneWidget);
    expect(progress.thinkBest(handRummyKey, handRummyLang), 3);
  });

  testWidgets('too few points: laying out is not offered', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final progress = await Progress.load();
    final rng = math.Random(5);
    final p = makeHandRummy(math.Random(5));
    await t.pumpWidget(
      MaterialApp(
        home: HandRummyScreen(progress: progress, rng: rng),
      ),
    );
    // the smallest meld of the way out (they are worth 30 together)
    final small = [...p.melds]
      ..sort((a, b) => Meld.of(a)!.points.compareTo(Meld.of(b)!.points));
    expect(Meld.of(small.first)!.points, lessThan(handRummyOpen));
    for (final id in small.first) {
      await t.tap(find.byKey(ValueKey('hr-card-$id')));
      await t.pump();
    }
    await t.tap(find.byKey(const ValueKey('hr-meld')));
    await t.pump();
    final open = t.widget<FilledButton>(find.byKey(const ValueKey('hr-open')));
    expect(open.onPressed, isNull);
    // 💡 picks another meld of the way out
    await t.tap(find.byKey(const ValueKey('hr-hint')));
    await t.pump();
    final meld = t.widget<FilledButton>(find.byKey(const ValueKey('hr-meld')));
    expect(meld.onPressed, isNotNull);
    // the rest set aside: 💡 says to lay out now
    for (var k = 0; k < 5; k++) {
      await t.tap(find.byKey(const ValueKey('hr-meld')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('hr-hint')));
      await t.pump();
      if (find.text('Enough points: lay out now!').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.text('Enough points: lay out now!'), findsOneWidget);
    // laying out taken back: the melds are set aside again
    await t.tap(find.byKey(const ValueKey('hr-open')));
    await t.pump();
    final aside = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('hr-staged-'),
    );
    expect(aside, findsNothing);
    await t.tap(find.byKey(const ValueKey('hr-undo')));
    await t.pump();
    expect(aside, findsWidgets);
    await t.pump(const Duration(seconds: 5));
  });
}
