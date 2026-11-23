// The Hase plays Rommé: it sees only its own view (like a player over the
// link) and makes one move at a time.
import 'rummy_rules.dart';

class _Cand {
  _Cand(this.real, this.jokers, this.points);

  /// (suit, rank) of the real cards.
  final List<(int, int)> real;
  final int jokers;
  final int points;
  int get size => real.length + jokers;
}

/// The melds in [hand] worth most: by points (for the first melds), or
/// by cards when [byCards] (to get rid of them).
List<List<int>> bestMelds(
  List<int> hand, {
  bool byCards = false,
  int maxNodes = 20000,
}) {
  final ids = <(int, int), List<int>>{};
  final jokers = <int>[];
  for (final id in hand) {
    final c = RummyCard(id);
    if (c.isJoker) {
      jokers.add(id);
    } else {
      (ids[(c.suit, c.rank)] ??= []).add(id);
    }
  }
  int count(int s, int r) => ids[(s, r)]?.length ?? 0;
  final maxJ = jokers.length.clamp(0, 2);

  final cands = <_Cand>[];
  for (var r = 1; r <= 13; r++) {
    for (var mask = 1; mask < 16; mask++) {
      final suits = [
        for (var s = 0; s < suitCount; s++)
          if (mask & (1 << s) != 0) s,
      ];
      if (suits.length < 2 || suits.any((s) => count(s, r) == 0)) continue;
      for (var j = 0; j <= maxJ && suits.length + j <= 4; j++) {
        if (suits.length + j < 3 || j > suits.length) continue;
        cands.add(
          _Cand(
            [for (final s in suits) (s, r)],
            j,
            rankPoints(r) * (suits.length + j),
          ),
        );
      }
    }
  }
  for (var s = 0; s < suitCount; s++) {
    bool has(int p) => count(s, p == 14 ? 1 : p) > 0;
    for (var lo = 1; lo <= 12; lo++) {
      for (var hi = lo + 2; hi <= 14; hi++) {
        if (!has(lo) && !has(hi)) continue;
        final real = [
          for (var p = lo; p <= hi; p++)
            if (has(p)) (s, p == 14 ? 1 : p),
        ];
        final m = hi - lo + 1 - real.length;
        if (real.length < 2 || m > real.length || m > maxJ) continue;
        var pts = 0;
        for (var p = lo; p <= hi; p++) {
          pts += placePoints(p);
        }
        cands.add(_Cand(real, m, pts));
      }
    }
  }
  int score(_Cand c) => byCards ? c.size * 100 + c.points : c.points;
  cands.sort((a, b) => score(b).compareTo(score(a)));

  final left = {for (final e in ids.entries) e.key: e.value.length};
  var jLeft = jokers.length;
  var nodes = 0;
  var best = <_Cand>[];
  var bestScore = 0;
  final chosen = <_Cand>[];
  var now = 0;
  void dfs(int from) {
    if (now > bestScore) {
      bestScore = now;
      best = [...chosen];
    }
    for (var i = from; i < cands.length && nodes < maxNodes; i++) {
      nodes++;
      final c = cands[i];
      if (c.jokers > jLeft) continue;
      final need = <(int, int), int>{};
      for (final k in c.real) {
        need[k] = (need[k] ?? 0) + 1;
      }
      if (need.entries.any((e) => (left[e.key] ?? 0) < e.value)) continue;
      for (final e in need.entries) {
        left[e.key] = left[e.key]! - e.value;
      }
      jLeft -= c.jokers;
      chosen.add(c);
      now += score(c);
      dfs(i + 1);
      now -= score(c);
      chosen.removeLast();
      jLeft += c.jokers;
      for (final e in need.entries) {
        left[e.key] = left[e.key]! + e.value;
      }
    }
  }

  dfs(0);
  final take = {
    for (final e in ids.entries) e.key: [...e.value],
  };
  final jTake = [...jokers];
  return [
    for (final c in best)
      [
        for (final k in c.real) take[k]!.removeLast(),
        for (var j = 0; j < c.jokers; j++) jTake.removeLast(),
      ],
  ];
}

int _points(List<List<int>> melds) =>
    melds.fold(0, (s, m) => s + (Meld.of(m)?.points ?? 0));

int _cards(List<List<int>> melds) => melds.fold(0, (s, m) => s + m.length);

/// The Hase's next move in [v] (its turn).
RummyMove haseMove(RummyView v) {
  final hand = v.hand;
  final opened = v.opened[v.me];
  if (v.phase == RummyPhase.over) return const NextRound();
  if (v.phase == RummyPhase.draw) {
    final top = v.pileTop;
    if (top != null && !v.pileBlocked && _wantsPile(v, top)) {
      return const DrawPile();
    }
    return const DrawStock();
  }
  if (!opened) {
    final melds = bestMelds(hand);
    final enough = melds.isNotEmpty && _points(melds) >= v.rules.openPoints;
    final used = {for (final m in melds) ...m};
    if (v.fromPile case final c? when hand.contains(c)) {
      return enough && used.contains(c) ? OpenMelds(melds) : const PutBack();
    }
    if (enough) return OpenMelds(melds);
    return Discard(_throwAway(v));
  }
  final melds = bestMelds(hand, byCards: true);
  if (melds.isNotEmpty) return LayMeld(melds.first);
  for (final c in hand) {
    // a joker only goes when the hand is nearly empty
    if (RummyCard(c).isJoker && hand.length > 2) continue;
    for (var i = 0; i < v.table.length; i++) {
      if (v.table[i].withCard(c) != null) return LayOff(c, i);
    }
  }
  for (final c in hand) {
    for (var i = 0; i < v.table.length; i++) {
      if (v.table[i].swap(c) != null) return SwapJoker(c, i);
    }
  }
  return Discard(_throwAway(v));
}

bool _wantsPile(RummyView v, int top) {
  final hand = v.hand;
  final opened = v.opened[v.me];
  final more = [...hand, top];
  if (!opened) {
    final melds = bestMelds(more);
    return melds.any((m) => m.contains(top)) &&
        _points(melds) >= v.rules.openPoints;
  }
  if (RummyCard(top).isJoker) return true;
  if (v.table.any((m) => m.withCard(top) != null)) return true;
  return _cards(bestMelds(more, byCards: true)) >
      _cards(bestMelds(hand, byCards: true));
}

/// The card the Hase needs least: no neighbours and worth most.
int _throwAway(RummyView v) {
  final hand = v.hand;
  bool kept(int c) => c == v.fromPile || v.swapped.contains(c);
  var choice = [
    for (final c in hand)
      if (!kept(c) && !RummyCard(c).isJoker) c,
  ];
  if (choice.isEmpty) {
    choice = [
      for (final c in hand)
        if (!kept(c)) c,
    ];
  }
  if (choice.isEmpty) choice = [...hand];
  int useful(int id) {
    final c = RummyCard(id);
    if (c.isJoker) return 1000;
    var u = 0;
    for (final o in hand.map(RummyCard.new)) {
      if (o.id == id || o.isJoker) continue;
      if (o.rank == c.rank && o.suit != c.suit) u += 3;
      if (o.suit == c.suit && o.rank != c.rank) {
        var d = (o.rank - c.rank).abs();
        // the ace is next to the king too
        if (o.rank == 1) d = d < (14 - c.rank) ? d : 14 - c.rank;
        if (c.rank == 1) d = d < (14 - o.rank) ? d : 14 - o.rank;
        if (d == 1) u += 3;
        if (d == 2) u += 1;
      }
    }
    // the other player could lay it off
    if (v.table.any((m) => m.withCard(id) != null)) u += 2;
    return u;
  }

  choice.sort((a, b) {
    final d = useful(a).compareTo(useful(b));
    return d != 0 ? d : RummyCard(b).penalty.compareTo(RummyCard(a).penalty);
  });
  return choice.first;
}
