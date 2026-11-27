// Handrommé: a card puzzle for one. You get 12 cards and lay them all
// down in one go: first melds worth at least [handRummyOpen] points
// ("Rauslegen", from your hand only), then the other melds, and the rest
// laid off on the melds on the table, those already out at the start
// too. No drawing, no discarding: every deal can be laid out completely
// (it is dealt from a way out, kept in [HandRummyPuzzle.melds] and
// [HandRummyPuzzle.layOffs]).
//
// Pure Dart; the melds and cards are those of Rommé ([Meld], [RummyCard]).
import 'dart:math' as math;

import 'rummy_rules.dart';

const handRummyOpen = 30;
const handRummySize = 12;

/// A deal: the hand and the melds already on the table.
class HandRummyPuzzle {
  const HandRummyPuzzle({
    required this.hand,
    required this.table,
    required this.melds,
    required this.layOffs,
  });

  final List<int> hand;
  final List<Meld> table;

  /// A way out: these melds of the hand (worth [handRummyOpen] together)
  /// ...
  final List<List<int>> melds;

  /// ... then these cards laid off, in this order, on `table[meld]`.
  final List<({int card, int meld})> layOffs;
}

/// A deal of [size] cards with up to [maxTable] melds already out.
HandRummyPuzzle makeHandRummy(
  math.Random rng, {
  int size = handRummySize,
  int open = handRummyOpen,
  int maxTable = 2,
}) {
  for (;;) {
    final p = _deal(rng, size, open, maxTable);
    if (p != null) return p;
  }
}

HandRummyPuzzle? _deal(math.Random rng, int size, int open, int maxTable) {
  final used = <int>{};
  // one of the two cards of [suit] and [rank] (two decks), or null
  int? card(int suit, int rank) {
    final ids = [
      for (var d = 0; d < 2; d++)
        if (!used.contains(d * deckSize + suit * 13 + rank - 1))
          d * deckSize + suit * 13 + rank - 1,
    ];
    if (ids.isEmpty) return null;
    final id = ids[rng.nextInt(ids.length)];
    used.add(id);
    return id;
  }

  int rankAt(int place) => place == 14 ? 1 : place;

  List<int>? run(int length) {
    final suit = rng.nextInt(suitCount);
    final low = 1 + rng.nextInt(14 - length + 1);
    final cards = <int>[];
    for (var p = low; p < low + length; p++) {
      final c = card(suit, rankAt(p));
      if (c == null) return null;
      cards.add(c);
    }
    return cards;
  }

  List<int>? set(int length) {
    final rank = 1 + rng.nextInt(13);
    final suits = [0, 1, 2, 3]..shuffle(rng);
    final cards = <int>[];
    for (final suit in suits.take(length)) {
      final c = card(suit, rank);
      if (c == null) return null;
      cards.add(c);
    }
    return cards;
  }

  // melds already out, and cards of the hand that fit on them
  final table = <Meld>[];
  final layOffs = <({int card, int meld})>[];
  final tableCount = rng.nextInt(maxTable + 1);
  for (var t = 0; t < tableCount; t++) {
    final isRun = rng.nextBool();
    final cards = isRun ? run(3 + rng.nextInt(2)) : set(3);
    if (cards == null) return null;
    var meld = Meld.of(cards)!;
    table.add(meld);
    // cards that fit at its ends (a set: the fourth suit)
    final wanted = isRun ? 1 + rng.nextInt(2) : 1;
    for (var k = 0; k < wanted; k++) {
      final Meld? next;
      final int? c;
      if (isRun) {
        final up = meld.high < 14 && (meld.low == 1 || rng.nextBool());
        if (!up && meld.low == 1) break;
        c = card(meld.suit, rankAt(up ? meld.high + 1 : meld.low - 1));
      } else {
        final suits = [for (final id in meld.cards) RummyCard(id).suit];
        final suit = [0, 1, 2, 3].firstWhere((s) => !suits.contains(s));
        c = card(suit, meld.rank);
      }
      if (c == null) return null;
      next = meld.withCard(c);
      if (next == null) return null;
      meld = next;
      layOffs.add((card: c, meld: t));
    }
  }
  // the rest of the hand: melds of three to five cards
  var left = size - layOffs.length;
  if (left < 3) return null;
  final melds = <List<int>>[];
  while (left > 0) {
    final sizes = [
      for (final n in [3, 4, 5])
        if (n == left || left - n >= 3) n,
    ];
    final n = sizes[rng.nextInt(sizes.length)];
    final cards = n <= 4 && rng.nextInt(5) < 2 ? set(n) : run(n);
    if (cards == null) return null;
    melds.add(cards);
    left -= n;
  }
  // sometimes a joker stands for a card of one of them
  if (rng.nextInt(3) == 0) {
    final m = melds[rng.nextInt(melds.length)];
    final i = rng.nextInt(m.length);
    used.remove(m[i]);
    m[i] = 2 * deckSize + rng.nextInt(6);
  }
  var points = 0;
  for (final m in melds) {
    final meld = Meld.of(m);
    // one meld alone is not enough: laying out takes thinking
    if (meld == null || meld.points >= open) return null;
    points += meld.points;
  }
  if (points < open) return null;
  final hand = [for (final m in melds) ...m, for (final l in layOffs) l.card]
    ..shuffle(rng);
  return HandRummyPuzzle(
    hand: hand,
    table: table,
    melds: melds,
    layOffs: layOffs,
  );
}

/// Playing a deal: what is in the hand and on the table, each move can
/// be taken back.
class HandRummy {
  HandRummy(this.puzzle, {this.open = handRummyOpen})
    : hand = [...puzzle.hand],
      table = [...puzzle.table],
      mine = List.filled(puzzle.table.length, false, growable: true);

  final HandRummyPuzzle puzzle;
  final int open;
  final List<int> hand;
  final List<Meld> table;

  /// Which melds of [table] were laid in this game (not out at the start).
  final List<bool> mine;
  var opened = false;

  final _history = <(List<int>, List<Meld>, List<bool>, bool)>[];

  bool get done => hand.isEmpty;
  bool get canUndo => _history.isNotEmpty;

  void _save() => _history.add(([...hand], [...table], [...mine], opened));

  /// Takes the last move back.
  bool undo() {
    if (_history.isEmpty) return false;
    final (h, t, m, o) = _history.removeLast();
    hand
      ..clear()
      ..addAll(h);
    table
      ..clear()
      ..addAll(t);
    mine
      ..clear()
      ..addAll(m);
    opened = o;
    return true;
  }

  /// The first melds, worth at least [open] together.
  RummyNo? openWith(List<List<int>> melds) {
    if (opened) return RummyNo.notAMeld;
    final all = [for (final m in melds) ...m];
    if (all.isEmpty) return RummyNo.notAMeld;
    if (all.toSet().length != all.length || !all.every(hand.contains)) {
      return RummyNo.notInHand;
    }
    final made = [for (final m in melds) Meld.of(m)];
    if (made.contains(null)) return RummyNo.notAMeld;
    if (made.fold(0, (s, m) => s + m!.points) < open) {
      return RummyNo.tooFewPoints;
    }
    _save();
    for (final m in made) {
      table.add(m!);
      mine.add(true);
    }
    hand.removeWhere(all.contains);
    opened = true;
    return null;
  }

  RummyNo? lay(List<int> cards) {
    if (!opened) return RummyNo.openFirst;
    if (cards.toSet().length != cards.length || !cards.every(hand.contains)) {
      return RummyNo.notInHand;
    }
    final made = Meld.of(cards);
    if (made == null) return RummyNo.notAMeld;
    _save();
    table.add(made);
    mine.add(true);
    hand.removeWhere(cards.contains);
    return null;
  }

  /// [card] laid off on `table[meld]`, or (if it is the card a joker
  /// there stands for) swapped for the joker.
  RummyNo? layOff(int card, int meld, {bool swap = false}) {
    if (!opened) return RummyNo.openFirst;
    if (!hand.contains(card)) return RummyNo.notInHand;
    if (meld < 0 || meld >= table.length) return RummyNo.doesNotFit;
    final on = table[meld].withCard(card);
    final swapped = table[meld].swap(card);
    if (on != null && (!swap || swapped == null)) {
      _save();
      table[meld] = on;
      hand.remove(card);
      return null;
    }
    if (swapped == null) return RummyNo.doesNotFit;
    _save();
    table[meld] = swapped.$1;
    hand
      ..remove(card)
      ..add(swapped.$2);
    return null;
  }

  /// A next step on the way out: cards to pick (a meld, or one card for
  /// the table), or `open` when the melds set aside ([staged], before
  /// laying out) are to be laid out now. Null: from here (with [staged]
  /// set aside) the cards cannot all go down any more.
  ({List<int> cards, bool open})? next({List<List<int>> staged = const []}) {
    if (done) return null;
    if (!opened) {
      final more = _opening(staged);
      if (more == null) return null;
      if (more.isEmpty) return (cards: const [], open: true);
      return (cards: more.first, open: false);
    }
    for (final m in _moves(hand, table)) {
      if (_out(m.hand, m.table)) return (cards: m.cards, open: false);
    }
    return null;
  }

  /// Whether all cards can still go down (with [staged] set aside).
  bool goesOut({List<List<int>> staged = const []}) =>
      done || next(staged: staged) != null;

  /// Melds to set aside besides [staged] for a laying out from which the
  /// rest goes down ([] if [staged] is enough), or null.
  List<List<int>>? _opening(List<List<int>> staged) {
    final aside = {for (final m in staged) ...m};
    if (!aside.every(hand.contains)) return null;
    final base = [for (final m in staged) Meld.of(m)];
    if (base.contains(null)) return null;
    final basePoints = base.fold(0, (s, m) => s + m!.points);
    final rest = [
      for (final c in hand)
        if (!aside.contains(c)) c,
    ];
    final melds = [
      for (final m in _subsets(rest, 3, rest.length))
        if (Meld.of(m) case final made?) (cards: m, meld: made),
    ];
    final chosen = <({List<int> cards, Meld meld})>[];
    List<List<int>>? go(int from, Set<int> used, int points) {
      if (points >= open) {
        final left = [
          for (final c in rest)
            if (!used.contains(c)) c,
        ];
        if (_out(left, [
          ...table,
          for (final m in base) m!,
          for (final m in chosen) m.meld,
        ])) {
          return [for (final m in chosen) m.cards];
        }
      }
      for (var i = from; i < melds.length; i++) {
        final m = melds[i];
        if (m.cards.any(used.contains)) continue;
        chosen.add(m);
        final found = go(i + 1, {...used, ...m.cards}, points + m.meld.points);
        chosen.removeLast();
        if (found != null) return found;
      }
      return null;
    }

    return go(0, {}, basePoints);
  }

  final _memo = <String, bool>{};

  /// Whether, laid out, [hand] can all go down on and next to [table].
  bool _out(List<int> hand, List<Meld> table) {
    if (hand.isEmpty) return true;
    final key = [
      ([...hand]..sort()).join(','),
      ...[
        for (final m in table) ([...m.cards]..sort()).join(','),
      ]..sort(),
    ].join('|');
    if (_memo[key] case final known?) return known;
    _memo[key] = false; // (a joker swapped back and forth: no way)
    for (final m in _moves(hand, table)) {
      if (_out(m.hand, m.table)) return _memo[key] = true;
    }
    return false;
  }
}

typedef _Move = ({List<int> cards, List<int> hand, List<Meld> table});

/// The moves from [hand] and [table] (laid out): a meld of three (a
/// longer one is three and then cards laid off), or a card laid off or
/// swapped for a joker.
Iterable<_Move> _moves(List<int> hand, List<Meld> table) sync* {
  for (final m in _subsets(hand, 3, 3)) {
    if (Meld.of(m) case final made?) {
      yield (
        cards: m,
        hand: [
          for (final c in hand)
            if (!m.contains(c)) c,
        ],
        table: [...table, made],
      );
    }
  }
  for (final c in hand.toSet()) {
    for (var i = 0; i < table.length; i++) {
      final rest = [...hand]..remove(c);
      if (table[i].withCard(c) case final on?) {
        yield (cards: [c], hand: rest, table: [...table]..[i] = on);
      }
      if (table[i].swap(c) case (final on, final joker)) {
        yield (cards: [c], hand: [...rest, joker], table: [...table]..[i] = on);
      }
    }
  }
}

/// The subsets of [cards] with [min] to [max] cards, smaller first.
Iterable<List<int>> _subsets(List<int> cards, int min, int max) sync* {
  final pick = <int>[];
  Iterable<List<int>> go(int from, int size) sync* {
    if (pick.length == size) {
      yield [...pick];
      return;
    }
    for (var i = from; i <= cards.length - (size - pick.length); i++) {
      pick.add(cards[i]);
      yield* go(i + 1, size);
      pick.removeLast();
    }
  }

  for (var size = min; size <= math.min(max, cards.length); size++) {
    yield* go(0, size);
  }
}
