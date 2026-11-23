// Rommé (German rummy) for two players: 110 cards (two decks and six
// jokers), 13 cards each. On your turn you draw a card (from the stock or
// the discard pile), may lay melds, lay cards off and swap jokers, and end
// by discarding one card. Whoever has no card left wins the round; the
// others count the points left in their hand.
//
// Melds: a set (three or four cards of one rank, all suits different) or
// a run (three or more cards of one suit in a row; the ace is low in
// A-2-3 and high in Q-K-A, a run does not go round the corner). Jokers
// stand for any card; a meld needs at least two real cards and no more
// jokers than real ones.
//
// Your first melds ("Rauslegen") must be worth [RummyRules.openPoints]
// together (ace 11, or 1 in A-2-3; jack, queen, king 10; a joker the card
// it stands for), laid in one go. Before that you may take the top of the
// discard pile only to lay it out at once; otherwise it goes back.
// After you are out you may lay off on any meld and swap a joker on the
// table for the card it stands for (the joker goes to your hand and may
// not be discarded that turn). The card taken from the discard pile may
// not be thrown back in the same turn.
//
// Pure Dart: the same engine runs against the Hase and, on the host's
// phone, in a game over the link (the guest only sees its view).
import 'dart:math' as math;

const suitCount = 4;
const deckSize = 52;

/// Suits, in the order the hand is sorted (colours alternate).
const suitSymbols = ['♣', '♥', '♠', '♦'];
bool isRedSuit(int suit) => suit == 1 || suit == 3;

/// A card by its id: ids below 52 × decks are real cards, the rest jokers.
class RummyCard {
  const RummyCard._(this.id, this.suit, this.rank);

  factory RummyCard(int id) {
    if (id >= 2 * deckSize) return RummyCard._(id, -1, 0);
    final c = id % deckSize;
    return RummyCard._(id, c ~/ 13, c % 13 + 1);
  }

  final int id;

  /// 0..3 ([suitSymbols]); -1 for a joker.
  final int suit;

  /// 1 (ace) .. 13 (king); 0 for a joker.
  final int rank;

  bool get isJoker => suit < 0;

  /// What it costs left in a hand at the end of a round.
  int get penalty => isJoker ? 20 : rankPoints(rank);

  String get label => isJoker
      ? '★'
      : switch (rank) {
          1 => 'A',
          11 => 'J',
          12 => 'Q',
          13 => 'K',
          _ => '$rank',
        };

  @override
  String toString() => isJoker ? '★' : '$label${suitSymbols[suit]}';
}

/// Points of a rank in a set or a hand: ace 11, pictures 10.
int rankPoints(int rank) => rank == 1
    ? 11
    : rank >= 10
    ? 10
    : rank;

/// Points of a place in a run: 1 is the low ace, 14 the high one.
int placePoints(int place) => place == 1
    ? 1
    : place == 14
    ? 11
    : place >= 10
    ? 10
    : place;

int _rankAt(int place) => place == 14 ? 1 : place;

class RummyRules {
  const RummyRules({this.openPoints = 30, this.handSize = 13, this.jokers = 6});

  /// What the first melds must be worth together; 0: no minimum.
  final int openPoints;
  final int handSize;
  final int jokers;

  int get cardCount => 2 * deckSize + jokers;

  Map<String, dynamic> toJson() => {
    'open': openPoints,
    'hand': handSize,
    'jokers': jokers,
  };

  factory RummyRules.fromJson(Map<String, dynamic> j) => RummyRules(
    openPoints: (j['open'] as int).clamp(0, 200),
    handSize: (j['hand'] as int).clamp(3, 20),
    jokers: (j['jokers'] as int).clamp(0, 8),
  );
}

/// A set or a run on the table (or one being laid).
class Meld {
  const Meld._(this.isRun, this.cards, this.suit, this.rank, this.low);

  final bool isRun;

  /// In order: the run from [low] up; a set as laid.
  final List<int> cards;

  /// The run's suit.
  final int suit;

  /// The set's rank.
  final int rank;

  /// The run's first place (1..14, see [placePoints]).
  final int low;

  int get high => low + cards.length - 1;

  int get points {
    if (isRun) {
      return [
        for (var p = low; p <= high; p++) placePoints(p),
      ].fold(0, (a, b) => a + b);
    }
    return rankPoints(rank) * cards.length;
  }

  Iterable<RummyCard> get _real =>
      cards.map(RummyCard.new).where((c) => !c.isJoker);

  int get _jokers => cards.where((id) => RummyCard(id).isJoker).length;

  /// The meld [cards] make, or null. A joker at the end of a run goes
  /// above it if it can.
  static Meld? of(List<int> ids) {
    if (ids.length < 3 || ids.toSet().length != ids.length) return null;
    final cards = ids.map(RummyCard.new).toList();
    final real = cards.where((c) => !c.isJoker).toList();
    final jokers = [
      for (final c in cards)
        if (c.isJoker) c.id,
    ];
    if (real.length < 2 || jokers.length > real.length) return null;
    if (real.every((c) => c.rank == real.first.rank)) {
      if (ids.length > 4) return null;
      if (real.map((c) => c.suit).toSet().length != real.length) return null;
      return Meld._(
        false,
        [for (final c in real) c.id, ...jokers],
        -1,
        real.first.rank,
        0,
      );
    }
    if (real.any((c) => c.suit != real.first.suit)) return null;
    // aces may be low or high: try each way, keep the one worth most
    final aces = real.where((c) => c.rank == 1).toList();
    if (aces.length > 2) return null;
    Meld? best;
    for (var mask = 0; mask < (1 << aces.length); mask++) {
      final at = <int, int>{}; // place -> card
      var ok = true;
      for (final c in real) {
        var p = c.rank;
        if (c.rank == 1) {
          p = (mask >> aces.indexOf(c)) & 1 == 1 ? 14 : 1;
        }
        if (at.containsKey(p)) {
          ok = false;
          break;
        }
        at[p] = c.id;
      }
      if (!ok) continue;
      final places = at.keys.toList()..sort();
      var lo = places.first;
      var hi = places.last;
      final gaps = hi - lo + 1 - at.length;
      var extra = jokers.length - gaps;
      if (extra < 0) continue;
      final up = math.min(extra, 14 - hi);
      hi += up;
      extra -= up;
      lo -= extra;
      if (lo < 1) continue;
      var j = 0;
      final run = Meld._(
        true,
        [for (var p = lo; p <= hi; p++) at[p] ?? jokers[j++]],
        real.first.suit,
        0,
        lo,
      );
      if (best == null || run.points > best.points) best = run;
    }
    return best;
  }

  /// This meld with [id] laid off on it, or null.
  Meld? withCard(int id) {
    final c = RummyCard(id);
    if (cards.contains(id) || cards.length >= (isRun ? 14 : 4)) return null;
    if (c.isJoker) {
      if (_jokers + 1 > cards.length - _jokers) return null;
      if (!isRun) return Meld._(false, [...cards, id], suit, rank, low);
      if (high < 14) return Meld._(true, [...cards, id], suit, rank, low);
      return Meld._(true, [id, ...cards], suit, rank, low - 1);
    }
    if (!isRun) {
      if (c.rank != rank || _real.any((r) => r.suit == c.suit)) return null;
      return Meld._(false, [...cards, id], suit, rank, low);
    }
    if (c.suit != suit) return null;
    if (high < 14 && _rankAt(high + 1) == c.rank) {
      return Meld._(true, [...cards, id], suit, rank, low);
    }
    if (low > 1 && _rankAt(low - 1) == c.rank) {
      return Meld._(true, [id, ...cards], suit, rank, low - 1);
    }
    return null;
  }

  /// This meld with a joker replaced by [id] (the card it stands for),
  /// and the joker; or null.
  (Meld, int)? swap(int id) {
    final c = RummyCard(id);
    if (c.isJoker) return null;
    for (var i = 0; i < cards.length; i++) {
      if (!RummyCard(cards[i]).isJoker) continue;
      final fits = isRun
          ? c.suit == suit && _rankAt(low + i) == c.rank
          : c.rank == rank && !_real.any((r) => r.suit == c.suit);
      if (fits) {
        return (Meld._(isRun, [...cards]..[i] = id, suit, rank, low), cards[i]);
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'run': isRun,
    'cards': cards,
    'suit': suit,
    'rank': rank,
    'low': low,
  };

  factory Meld.fromJson(Map<String, dynamic> j) => Meld._(
    j['run'] as bool,
    (j['cards'] as List).cast<int>(),
    j['suit'] as int,
    j['rank'] as int,
    j['low'] as int,
  );

  @override
  String toString() => cards.map(RummyCard.new).join(' ');
}

/// What a player does; [RummyGame.apply] checks it.
sealed class RummyMove {
  const RummyMove();

  Map<String, dynamic> toJson();

  static RummyMove? fromJson(Map<String, dynamic> j) {
    try {
      return switch (j['m']) {
        'stock' => const DrawStock(),
        'pile' => const DrawPile(),
        'back' => const PutBack(),
        'open' => OpenMelds([
          for (final m in j['melds'] as List) (m as List).cast<int>(),
        ]),
        'meld' => LayMeld((j['cards'] as List).cast<int>()),
        'lay' => LayOff(j['card'] as int, j['meld'] as int),
        'swap' => SwapJoker(j['card'] as int, j['meld'] as int),
        'discard' => Discard(j['card'] as int),
        'next' => const NextRound(),
        _ => null,
      };
    } on TypeError {
      return null;
    }
  }
}

class DrawStock extends RummyMove {
  const DrawStock();
  @override
  Map<String, dynamic> toJson() => {'m': 'stock'};
}

/// The top card of the discard pile.
class DrawPile extends RummyMove {
  const DrawPile();
  @override
  Map<String, dynamic> toJson() => {'m': 'pile'};
}

/// Not out yet and the card from the pile does not fit: it goes back and
/// the player draws from the stock.
class PutBack extends RummyMove {
  const PutBack();
  @override
  Map<String, dynamic> toJson() => {'m': 'back'};
}

/// The first melds, worth at least [RummyRules.openPoints].
class OpenMelds extends RummyMove {
  const OpenMelds(this.melds);
  final List<List<int>> melds;
  @override
  Map<String, dynamic> toJson() => {'m': 'open', 'melds': melds};
}

class LayMeld extends RummyMove {
  const LayMeld(this.cards);
  final List<int> cards;
  @override
  Map<String, dynamic> toJson() => {'m': 'meld', 'cards': cards};
}

class LayOff extends RummyMove {
  const LayOff(this.card, this.meld);
  final int card;
  final int meld;
  @override
  Map<String, dynamic> toJson() => {'m': 'lay', 'card': card, 'meld': meld};
}

class SwapJoker extends RummyMove {
  const SwapJoker(this.card, this.meld);
  final int card;
  final int meld;
  @override
  Map<String, dynamic> toJson() => {'m': 'swap', 'card': card, 'meld': meld};
}

class Discard extends RummyMove {
  const Discard(this.card);
  final int card;
  @override
  Map<String, dynamic> toJson() => {'m': 'discard', 'card': card};
}

/// After a round: deal the next.
class NextRound extends RummyMove {
  const NextRound();
  @override
  Map<String, dynamic> toJson() => {'m': 'next'};
}

/// Why a move was refused (the screen explains it).
enum RummyNo {
  notYourTurn,
  drawFirst,
  drewAlready,
  notInHand,
  notAMeld,
  tooFewPoints,
  mustUsePile,
  openFirst,
  doesNotFit,
  keepThatCard,
  pileEmpty,
  notOver,
}

enum RummyPhase { draw, play, over }

/// One player's view of the game: the own hand, the table, the other
/// hands only counted (shown when the round is over).
class RummyView {
  const RummyView({
    required this.me,
    required this.rules,
    required this.hand,
    required this.handCounts,
    required this.table,
    required this.owners,
    required this.pileTop,
    required this.pileCount,
    required this.stockCount,
    required this.turn,
    required this.phase,
    required this.opened,
    required this.fromPile,
    required this.swapped,
    required this.pileBlocked,
    required this.winner,
    required this.scores,
    required this.round,
    required this.shownHands,
  });

  final int me;
  final RummyRules rules;
  final List<int> hand;
  final List<int> handCounts;
  final List<Meld> table;

  /// Who laid each meld of [table].
  final List<int> owners;
  final int? pileTop;
  final int pileCount;
  final int stockCount;
  final int turn;
  final RummyPhase phase;
  final List<bool> opened;

  /// The card taken from the pile this turn, if any.
  final int? fromPile;

  /// Jokers swapped from the table this turn (not to be discarded).
  final List<int> swapped;

  /// The card from the pile went back: draw from the stock.
  final bool pileBlocked;

  /// Who went out (null: nobody yet, or the cards ran out).
  final int? winner;

  /// Penalty points so far, per player (lowest is best).
  final List<int> scores;
  final int round;

  /// After a round: everybody's hand ([] while it runs).
  final List<List<int>> shownHands;

  bool get myTurn => turn == me && phase != RummyPhase.over;

  Map<String, dynamic> toJson() => {
    'me': me,
    'rules': rules.toJson(),
    'hand': hand,
    'counts': handCounts,
    'table': [for (final m in table) m.toJson()],
    'owners': owners,
    'top': pileTop,
    'pile': pileCount,
    'stock': stockCount,
    'turn': turn,
    'phase': phase.name,
    'opened': opened,
    'fromPile': fromPile,
    'swapped': swapped,
    'blocked': pileBlocked,
    'winner': winner,
    'scores': scores,
    'round': round,
    'shown': shownHands,
  };

  /// Null when [j] is not a view (a newer or broken app).
  static RummyView? fromJson(Map<String, dynamic> j) {
    try {
      return RummyView(
        me: j['me'] as int,
        rules: RummyRules.fromJson((j['rules'] as Map).cast()),
        hand: (j['hand'] as List).cast<int>(),
        handCounts: (j['counts'] as List).cast<int>(),
        table: [
          for (final m in j['table'] as List) Meld.fromJson((m as Map).cast()),
        ],
        owners: (j['owners'] as List).cast<int>(),
        pileTop: j['top'] as int?,
        pileCount: j['pile'] as int,
        stockCount: j['stock'] as int,
        turn: j['turn'] as int,
        phase: RummyPhase.values.byName(j['phase'] as String),
        opened: (j['opened'] as List).cast<bool>(),
        fromPile: j['fromPile'] as int?,
        swapped: (j['swapped'] as List).cast<int>(),
        pileBlocked: j['blocked'] as bool,
        winner: j['winner'] as int?,
        scores: (j['scores'] as List).cast<int>(),
        round: j['round'] as int,
        shownHands: [
          for (final h in j['shown'] as List) (h as List).cast<int>(),
        ],
      );
    } on Object {
      return null;
    }
  }
}

class RummyGame {
  RummyGame(this.rules, {this.players = 2, math.Random? rng, int starter = 0})
    : _rng = rng ?? math.Random(),
      scores = List.filled(players, 0) {
    _deal(starter);
  }

  final RummyRules rules;
  final int players;
  final math.Random _rng;

  final List<int> scores;
  var round = 1;
  late int starter;
  final stock = <int>[];
  final pile = <int>[];
  late List<List<int>> hands;
  final table = <Meld>[];
  final owners = <int>[];
  late List<bool> opened;
  var turn = 0;
  var phase = RummyPhase.draw;
  int? fromPile;
  final swapped = <int>[];
  var pileBlocked = false;
  int? winner;

  void _deal(int first) {
    starter = first;
    stock
      ..clear()
      ..addAll(List.generate(rules.cardCount, (i) => i))
      ..shuffle(_rng);
    pile.clear();
    table.clear();
    owners.clear();
    hands = [
      for (var p = 0; p < players; p++)
        [for (var i = 0; i < rules.handSize; i++) stock.removeLast()],
    ];
    pile.add(stock.removeLast());
    opened = List.filled(players, false);
    turn = first;
    phase = RummyPhase.draw;
    _newTurn();
    winner = null;
  }

  void _newTurn() {
    fromPile = null;
    swapped.clear();
    pileBlocked = false;
  }

  RummyView view(int me) => RummyView(
    me: me,
    rules: rules,
    hand: List.unmodifiable(hands[me]),
    handCounts: [for (final h in hands) h.length],
    table: List.unmodifiable(table),
    owners: List.unmodifiable(owners),
    pileTop: pile.lastOrNull,
    pileCount: pile.length,
    stockCount: stock.length,
    turn: turn,
    phase: phase,
    opened: List.unmodifiable(opened),
    fromPile: turn == me ? fromPile : null,
    swapped: turn == me ? List.unmodifiable(swapped) : const [],
    pileBlocked: turn == me && pileBlocked,
    winner: winner,
    scores: List.unmodifiable(scores),
    round: round,
    shownHands: phase == RummyPhase.over
        ? [for (final h in hands) List.unmodifiable(h)]
        : const [],
  );

  /// Applies [m] for [player]; returns why not (and changes nothing).
  RummyNo? apply(int player, RummyMove m) {
    if (m is NextRound) {
      if (phase != RummyPhase.over) return RummyNo.notOver;
      round++;
      _deal((starter + 1) % players);
      return null;
    }
    if (phase == RummyPhase.over || player != turn) return RummyNo.notYourTurn;
    final hand = hands[player];
    switch (m) {
      case DrawStock():
        if (phase != RummyPhase.draw) return RummyNo.drewAlready;
        if (stock.isEmpty && !_refill()) {
          _end(null);
          return null;
        }
        hand.add(stock.removeLast());
        phase = RummyPhase.play;
      case DrawPile():
        if (phase != RummyPhase.draw) return RummyNo.drewAlready;
        if (pile.isEmpty || pileBlocked) return RummyNo.pileEmpty;
        final c = pile.removeLast();
        hand.add(c);
        fromPile = c;
        phase = RummyPhase.play;
      case PutBack():
        final c = fromPile;
        if (c == null || opened[player] || !hand.contains(c)) {
          return RummyNo.keepThatCard;
        }
        hand.remove(c);
        pile.add(c);
        fromPile = null;
        pileBlocked = true;
        phase = RummyPhase.draw;
      case OpenMelds(:final melds):
        if (phase != RummyPhase.play) return RummyNo.drawFirst;
        if (opened[player]) return RummyNo.notAMeld;
        final all = [for (final x in melds) ...x];
        if (all.isEmpty) return RummyNo.notAMeld;
        if (all.toSet().length != all.length || !all.every(hand.contains)) {
          return RummyNo.notInHand;
        }
        final made = [for (final x in melds) Meld.of(x)];
        if (made.contains(null)) return RummyNo.notAMeld;
        final points = made.fold(0, (s, x) => s + x!.points);
        if (points < rules.openPoints) return RummyNo.tooFewPoints;
        if (fromPile case final c? when !all.contains(c)) {
          return RummyNo.mustUsePile;
        }
        for (final x in made) {
          table.add(x!);
          owners.add(player);
        }
        hand.removeWhere(all.contains);
        opened[player] = true;
        _wonIfEmpty(player);
      case LayMeld(:final cards):
        if (phase != RummyPhase.play) return RummyNo.drawFirst;
        if (!opened[player]) return RummyNo.openFirst;
        if (cards.toSet().length != cards.length ||
            !cards.every(hand.contains)) {
          return RummyNo.notInHand;
        }
        final made = Meld.of(cards);
        if (made == null) return RummyNo.notAMeld;
        table.add(made);
        owners.add(player);
        hand.removeWhere(cards.contains);
        _wonIfEmpty(player);
      case LayOff(:final card, :final meld):
        if (phase != RummyPhase.play) return RummyNo.drawFirst;
        if (!opened[player]) return RummyNo.openFirst;
        if (!hand.contains(card)) return RummyNo.notInHand;
        if (meld < 0 || meld >= table.length) return RummyNo.doesNotFit;
        final made = table[meld].withCard(card);
        if (made == null) return RummyNo.doesNotFit;
        table[meld] = made;
        hand.remove(card);
        _wonIfEmpty(player);
      case SwapJoker(:final card, :final meld):
        if (phase != RummyPhase.play) return RummyNo.drawFirst;
        if (!opened[player]) return RummyNo.openFirst;
        if (!hand.contains(card)) return RummyNo.notInHand;
        if (meld < 0 || meld >= table.length) return RummyNo.doesNotFit;
        final made = table[meld].swap(card);
        if (made == null) return RummyNo.doesNotFit;
        table[meld] = made.$1;
        hand
          ..remove(card)
          ..add(made.$2);
        swapped.add(made.$2);
      case Discard(:final card):
        if (phase != RummyPhase.play) return RummyNo.drawFirst;
        if (!hand.contains(card)) return RummyNo.notInHand;
        if (fromPile case final c? when !opened[player] && hand.contains(c)) {
          return RummyNo.mustUsePile;
        }
        bool kept(int c) => c == fromPile || swapped.contains(c);
        // (unless nothing else is left to throw)
        if (kept(card) && hand.any((c) => !kept(c))) {
          return RummyNo.keepThatCard;
        }
        hand.remove(card);
        pile.add(card);
        if (!_wonIfEmpty(player)) {
          turn = (turn + 1) % players;
          phase = RummyPhase.draw;
          _newTurn();
        }
      case NextRound():
        break; // handled above
    }
    return null;
  }

  /// The discard pile but its top card, shuffled, is the new stock.
  bool _refill() {
    if (pile.length < 2) return false;
    final top = pile.removeLast();
    stock
      ..addAll(pile)
      ..shuffle(_rng);
    pile
      ..clear()
      ..add(top);
    return true;
  }

  bool _wonIfEmpty(int player) {
    if (hands[player].isNotEmpty) return false;
    _end(player);
    return true;
  }

  void _end(int? who) {
    winner = who;
    phase = RummyPhase.over;
    for (var p = 0; p < players; p++) {
      if (p == who) continue;
      scores[p] += hands[p].fold(0, (s, c) => s + RummyCard(c).penalty);
    }
  }
}

/// Points still in [hand].
int handPenalty(Iterable<int> hand) =>
    hand.fold(0, (s, c) => s + RummyCard(c).penalty);
