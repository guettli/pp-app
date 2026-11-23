// The Rommé table: the other player at the top, the melds in the middle,
// the stock and the discard pile, your hand at the bottom.
//
// Tap cards to pick them. Picked cards make a meld ("Auslegen"); before
// you are out the melds are gathered first and laid together
// ("Rauslegen") once they are worth enough. One picked card: tap a meld
// on the table to lay it off (or to swap the joker it stands for), or
// throw it away ("Abwerfen").
import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/emoji_image.dart';
import '../ui/round_button.dart';
import '../ui/strings.dart';
import 'rummy_rules.dart';
import 'rummy_seat.dart';

const _felt = Color(0xFF1B5E20);
const _gold = Color(0xFFFFD54F);

class RummyTable extends StatefulWidget {
  const RummyTable({
    super.key,
    required this.seat,
    required this.me,
    required this.friend,
    required this.onGone,
  });

  final RummySeat seat;

  /// The pictures of this phone's player and the other.
  final String me;
  final String friend;

  /// The other phone is gone; back to the start.
  final VoidCallback onGone;

  @override
  State<RummyTable> createState() => _RummyTableState();
}

class _RummyTableState extends State<RummyTable> {
  final _picked = <int>{};

  /// Melds gathered for laying out (before you are out).
  final _staged = <List<int>>[];
  var _bySuit = true;

  /// A note of the table itself (not a refusal of the game).
  String? _note;
  Timer? _noteTimer;
  int? _round;

  @override
  void initState() {
    super.initState();
    widget.seat.addListener(_changed);
  }

  @override
  void didUpdateWidget(RummyTable old) {
    super.didUpdateWidget(old);
    if (!identical(old.seat, widget.seat)) {
      old.seat.removeListener(_changed);
      widget.seat.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.seat.removeListener(_changed);
    _noteTimer?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final v = widget.seat.view;
    setState(() {
      if (v == null) return;
      if (_round != v.round) {
        _round = v.round;
        _picked.clear();
        _staged.clear();
      }
      final hand = v.hand.toSet();
      _picked.retainWhere(hand.contains);
      if (v.opened[v.me]) _staged.clear();
      _staged.removeWhere((m) => !m.every(hand.contains));
    });
  }

  void _say(String note) {
    _noteTimer?.cancel();
    setState(() => _note = note);
    _noteTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _note = null);
    });
  }

  void _move(RummyMove m) {
    _noteTimer?.cancel();
    setState(() => _note = null);
    widget.seat.move(m);
  }

  List<int> _handShown(RummyView v) {
    final staged = {for (final m in _staged) ...m};
    final cards = [
      for (final c in v.hand)
        if (!staged.contains(c)) c,
    ];
    int key(int id) {
      final c = RummyCard(id);
      if (c.isJoker) return 1000 + id;
      return _bySuit ? c.suit * 100 + c.rank : c.rank * 10 + c.suit;
    }

    cards.sort((a, b) => key(a).compareTo(key(b)));
    return cards;
  }

  bool _canAct(RummyView v) =>
      v.myTurn && !widget.seat.busy && v.phase == RummyPhase.play;

  void _tapCard(int id) => setState(
    () => _picked.contains(id) ? _picked.remove(id) : _picked.add(id),
  );

  void _meld(RummyView v, S s) {
    final cards = _picked.toList();
    if (Meld.of(cards) == null) {
      _say(s.rummyNo(RummyNo.notAMeld, v.rules.openPoints));
      return;
    }
    if (v.opened[v.me]) {
      _move(LayMeld(cards));
    } else {
      setState(() {
        _staged.add(cards);
        _picked.clear();
      });
    }
  }

  int _stagedPoints() =>
      _staged.fold(0, (s, m) => s + (Meld.of(m)?.points ?? 0));

  void _tapMeld(RummyView v, int i, S s) {
    if (!_canAct(v)) return;
    if (_picked.length != 1) {
      _say(s.pickOne);
      return;
    }
    if (!v.opened[v.me]) {
      _say(s.rummyNo(RummyNo.openFirst, v.rules.openPoints));
      return;
    }
    final card = _picked.single;
    final meld = v.table[i];
    // the last card goes on the meld (that wins); else a joker is better
    final last = v.hand.length == 1;
    if (!last && meld.swap(card) != null) {
      _move(SwapJoker(card, i));
    } else if (meld.withCard(card) != null) {
      _move(LayOff(card, i));
    } else if (meld.swap(card) != null) {
      _move(SwapJoker(card, i));
    } else {
      _say(s.rummyNo(RummyNo.doesNotFit, v.rules.openPoints));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final seat = widget.seat;
    if (seat.gone) return _gone(s);
    final v = seat.view;
    if (v == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight * 1.2;
        final handWidth = wide ? c.maxWidth * 0.55 : c.maxWidth;
        final cardW = ((handWidth - 16) / 9).clamp(34.0, 60.0);
        final top = _status(v, s);
        final table = _tableArea(v, s, cardW * 0.72);
        final bottom = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!v.opened[v.me] && v.phase != RummyPhase.over)
              _stagedRow(v, s, cardW * 0.72),
            _piles(v, s, cardW),
            const SizedBox(height: 8),
            _hand(v, cardW),
            const SizedBox(height: 8),
            _buttons(v, s),
          ],
        );
        // the table scrolls by itself, up to part of the screen; the
        // rest scrolls when big text or a small screen needs it
        Widget felt(double max) => ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: max < 160 ? max : 160,
            maxHeight: max,
          ),
          child: table,
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [top, felt(c.maxHeight * 0.8)],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: handWidth,
                child: SingleChildScrollView(child: bottom),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [top, felt(c.maxHeight * 0.42), bottom],
          ),
        );
      },
    );
  }

  Widget _text(String t, {double size = 16, Color color = Colors.white}) =>
      Text(
        t,
        style: TextStyle(color: color, fontSize: size),
      );

  /// Who plays, the other's cards and the scores; or a note.
  Widget _status(RummyView v, S s) {
    final other = 1 - v.me;
    final refused = widget.seat.refused;
    final note =
        _note ??
        (refused == null ? null : s.rummyNo(refused, v.rules.openPoints));
    final String line;
    if (v.phase == RummyPhase.over) {
      line = '';
    } else if (!v.myTurn) {
      line = s.waitPlease;
    } else if (v.phase == RummyPhase.draw) {
      line = s.rummyDraw;
    } else if (v.opened[v.me]) {
      line = s.rummyPlay;
    } else {
      line = s.rummyPlayOpen(v.rules.openPoints);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              EmojiImage(widget.friend, size: 32),
              const SizedBox(width: 6),
              Flexible(
                child: _text(
                  '${s.cardsLeft(v.handCounts[other])}'
                  '${v.opened[other] ? ' ✓' : ''}',
                ),
              ),
              const Spacer(),
              Flexible(
                child: _text(
                  '${s.penaltyPoints}: ${v.scores[v.me]} : ${v.scores[other]}',
                  size: 14,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              EmojiImage(v.myTurn ? widget.me : widget.friend, size: 24),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  note ?? line,
                  key: const ValueKey('rummy-status'),
                  style: TextStyle(
                    color: note != null ? _gold : Colors.white,
                    fontSize: 16,
                    fontWeight: note != null ? FontWeight.bold : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableArea(RummyView v, S s, double w) {
    if (v.phase == RummyPhase.over) return _roundOver(v, s, w);
    final fits = _picked.length == 1 && v.opened[v.me] && _canAct(v)
        ? _picked.single
        : null;
    return Container(
      decoration: BoxDecoration(
        color: _felt,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < v.table.length; i++)
              _meldView(
                v.table[i].cards,
                w,
                key: ValueKey('rummy-meld-$i'),
                mine: v.owners[i] == v.me,
                hint:
                    fits != null &&
                    (v.table[i].withCard(fits) != null ||
                        v.table[i].swap(fits) != null),
                onTap: () => _tapMeld(v, i, s),
              ),
          ],
        ),
      ),
    );
  }

  Widget _meldView(
    List<int> cards,
    double w, {
    Key? key,
    bool mine = false,
    bool hint = false,
    VoidCallback? onTap,
  }) => GestureDetector(
    key: key,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hint
              ? _gold
              : mine
              ? Colors.white38
              : Colors.transparent,
          width: hint ? 3 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cards.length; i++)
            Align(
              widthFactor: i == cards.length - 1 ? 1 : 0.62,
              alignment: Alignment.centerLeft,
              child: PlayingCard(cards[i], width: w),
            ),
        ],
      ),
    ),
  );

  Widget _stagedRow(RummyView v, S s, double w) {
    final points = _stagedPoints();
    final enough = _staged.isNotEmpty && points >= v.rules.openPoints;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF2B2B6B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _text(
                    s.stagedPoints(points, v.rules.openPoints),
                    size: 14,
                  ),
                ),
                FilledButton(
                  key: const ValueKey('rummy-open'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF66BB6A),
                  ),
                  onPressed: enough && _canAct(v)
                      ? () => _move(OpenMelds([..._staged]))
                      : null,
                  child: Text(s.openBtn),
                ),
              ],
            ),
            if (_staged.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _staged.length; i++)
                    _meldView(
                      Meld.of(_staged[i])?.cards ?? _staged[i],
                      w,
                      key: ValueKey('rummy-staged-$i'),
                      onTap: () => setState(() => _staged.removeAt(i)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _piles(RummyView v, S s, double w) {
    final draw = v.myTurn && !widget.seat.busy && v.phase == RummyPhase.draw;
    return Row(
      children: [
        GestureDetector(
          key: const ValueKey('rummy-stock'),
          onTap: draw ? () => _move(const DrawStock()) : null,
          child: _glow(draw, CardBack(width: w, count: v.stockCount)),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          key: const ValueKey('rummy-pile'),
          onTap: draw && !v.pileBlocked && v.pileTop != null
              ? () => _move(const DrawPile())
              : null,
          child: _glow(
            draw && !v.pileBlocked,
            v.pileTop == null
                ? SizedBox(width: w, height: w * 1.45)
                : PlayingCard(v.pileTop!, width: w),
          ),
        ),
        const Spacer(),
        if (v.fromPile != null && !v.opened[v.me] && _canAct(v))
          TextButton(
            key: const ValueKey('rummy-back'),
            onPressed: () => _move(const PutBack()),
            child: Text(s.putBack, style: const TextStyle(color: _gold)),
          ),
        IconButton(
          key: const ValueKey('rummy-sort'),
          tooltip: s.sortCards,
          onPressed: () => setState(() => _bySuit = !_bySuit),
          icon: const Icon(Icons.sort, color: Colors.white),
        ),
      ],
    );
  }

  Widget _glow(bool on, Widget child) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: on ? _gold : Colors.transparent, width: 3),
    ),
    child: child,
  );

  Widget _hand(RummyView v, double w) => Wrap(
    spacing: 3,
    runSpacing: 6,
    children: [
      for (final id in _handShown(v))
        GestureDetector(
          key: ValueKey('rummy-card-$id'),
          onTap: () => _tapCard(id),
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 120),
            offset: _picked.contains(id) ? const Offset(0, -0.12) : Offset.zero,
            child: PlayingCard(id, width: w, picked: _picked.contains(id)),
          ),
        ),
    ],
  );

  Widget _buttons(RummyView v, S s) {
    final act = _canAct(v);
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 4,
      children: [
        FilledButton(
          key: const ValueKey('rummy-meld'),
          onPressed: _picked.length >= 3 && (act || !v.opened[v.me])
              ? () => _meld(v, s)
              : null,
          child: Text(s.meldBtn),
        ),
        FilledButton(
          key: const ValueKey('rummy-discard'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE57373),
          ),
          onPressed: _picked.length == 1 && act
              ? () => _move(Discard(_picked.single))
              : null,
          child: Text(s.discardBtn),
        ),
      ],
    );
  }

  Widget _roundOver(RummyView v, S s, double w) {
    final other = 1 - v.me;
    final won = v.winner == v.me;
    final left = v.shownHands.length > other ? v.shownHands[other] : <int>[];
    final mine = v.shownHands.length > v.me ? v.shownHands[v.me] : <int>[];
    return SingleChildScrollView(
      child: Column(
        children: [
          if (v.winner != null)
            EmojiImage(won ? widget.me : widget.friend, size: 72),
          const SizedBox(height: 8),
          Text(
            v.winner == null
                ? s.noWinner
                : won
                ? s.youWon
                : s.friendWon,
            key: const ValueKey('rummy-result'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 24),
          ),
          const SizedBox(height: 8),
          for (final (who, cards) in [(widget.friend, left), (widget.me, mine)])
            if (cards.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EmojiImage(who, size: 28),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Wrap(
                        spacing: 2,
                        runSpacing: 2,
                        children: [
                          for (final c in cards) PlayingCard(c, width: w * 0.8),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    _text('−${handPenalty(cards)}'),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          _text('${s.penaltyPoints}: ${v.scores[v.me]} : ${v.scores[other]}'),
          const SizedBox(height: 16),
          RoundButton(
            key: const ValueKey('rummy-next'),
            tooltip: s.nextRound,
            color: const Color(0xFF66BB6A),
            size: 80,
            onTap: () => _move(const NextRound()),
            child: const Icon(Icons.replay, color: Colors.white, size: 48),
          ),
        ],
      ),
    );
  }

  Widget _gone(S s) => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const EmojiImage('😕', size: 96),
          const SizedBox(height: 16),
          Text(
            s.friendGone,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 22),
          ),
          const SizedBox(height: 24),
          RoundButton(
            key: const ValueKey('together-again'),
            tooltip: s.tryAgain,
            color: const Color(0xFF5C6BC0),
            size: 96,
            onTap: widget.onGone,
            child: const Icon(Icons.refresh, color: Colors.white, size: 56),
          ),
        ],
      ),
    ),
  );
}

/// A card face: rank and suit (red or black), or a joker star.
class PlayingCard extends StatelessWidget {
  const PlayingCard(this.id, {super.key, this.width = 44, this.picked = false});

  final int id;
  final double width;
  final bool picked;

  @override
  Widget build(BuildContext context) {
    final c = RummyCard(id);
    final color = c.isJoker
        ? const Color(0xFF7B1FA2)
        : isRedSuit(c.suit)
        ? const Color(0xFFD32F2F)
        : const Color(0xFF212121);
    return Container(
      width: width,
      height: width * 1.45,
      padding: EdgeInsets.all(width * 0.06),
      decoration: BoxDecoration(
        color: picked ? const Color(0xFFFFF59D) : Colors.white,
        borderRadius: BorderRadius.circular(width * 0.14),
        border: Border.all(
          color: picked ? _gold : Colors.black26,
          width: picked ? 2.5 : 1,
        ),
        boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)],
      ),
      child: Semantics(
        label: '$c',
        child: FittedBox(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  height: 1,
                ),
              ),
              Text(
                c.isJoker ? 'J' : suitSymbols[c.suit],
                style: TextStyle(color: color, fontSize: 20, height: 1.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The back of the stock, with how many cards are left.
class CardBack extends StatelessWidget {
  const CardBack({super.key, this.width = 44, required this.count});

  final double width;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: width * 1.45,
    decoration: BoxDecoration(
      color: const Color(0xFF3949AB),
      borderRadius: BorderRadius.circular(width * 0.14),
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: Center(
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            '$count',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    ),
  );
}
