// Handrommé ([HandRummy]): the melds on the table at the top, the cards
// set aside for laying out, the hand at the bottom.
//
// Tap cards to pick them, "Auslegen" makes a meld of them: before laying
// out it is set aside until they are worth enough for "Rauslegen"
// (tap one set aside to take it back), after that it goes on the table.
// One picked card: tap a meld on the table to lay it off (a long press
// swaps a joker it stands for). 💡 picks cards for a next step, ↶ takes
// the last move back (laying out taken back: its melds are set aside
// again). When the cards cannot all go down any more, the screen says
// so at once (a small search, [HandRummy.goesOut]). Stars: 3 without
// 💡, 2 with one or two, else 1.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/progress.dart';
import '../ui/round_parts.dart';
import '../ui/strings.dart';
import 'hand_rummy.dart';
import 'rummy_rules.dart';
import 'rummy_table.dart' show PlayingCard;

const _felt = Color(0xFF1B5E20);
const _gold = Color(0xFFFFD54F);

/// Key of the best round in [Progress.thinkBest] (cards: one for all
/// languages).
const handRummyKey = 'handRummy';
const handRummyLang = 'cards';

class HandRummyScreen extends StatefulWidget {
  const HandRummyScreen({super.key, required this.progress, this.rng});

  final Progress progress;

  /// Deals (tests pass a seeded one).
  final math.Random? rng;

  @override
  State<HandRummyScreen> createState() => _HandRummyScreenState();
}

class _HandRummyScreenState extends State<HandRummyScreen> {
  late final math.Random _rng = widget.rng ?? math.Random();
  late HandRummy _game = HandRummy(makeHandRummy(_rng));
  final _picked = <int>{};

  /// Melds set aside for laying out.
  final _staged = <List<int>>[];
  var _bySuit = true;
  var _hints = 0;
  var _over = false;

  /// The cards cannot all go down any more (with [_staged] set aside).
  var _lost = false;

  /// The melds laid out first (back to [_staged] when that is undone).
  var _openedWith = <List<int>>[];

  void _recheck() => _lost = !_game.goesOut(staged: _staged);
  String? _note;
  Timer? _noteTimer;

  @override
  void dispose() {
    _noteTimer?.cancel();
    super.dispose();
  }

  void _say(String note) {
    _noteTimer?.cancel();
    setState(() => _note = note);
    _noteTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _note = null);
    });
  }

  /// Applies a move of the game; a refusal is said.
  void _do(RummyNo? Function() move, S s) {
    final no = move();
    if (no != null) {
      _say(s.rummyNo(no, _game.open));
      return;
    }
    _noteTimer?.cancel();
    setState(() {
      _note = null;
      _picked.clear();
      if (_game.opened) _staged.clear();
      _recheck();
    });
    if (_game.done) unawaited(_finished());
  }

  Future<void> _finished() async {
    if (_over) return;
    _over = true;
    final stars = _hints == 0
        ? 3
        : _hints <= 2
        ? 2
        : 1;
    var record = false;
    try {
      record = await widget.progress.recordThink(
        handRummyKey,
        handRummyLang,
        stars,
      );
    } catch (e, st) {
      debugPrint('saving the Handrommé record failed: $e\n$st');
    }
    if (!mounted) return;
    await showRoundEnd(
      context,
      stars: stars,
      right: _game.puzzle.hand.length,
      total: _game.puzzle.hand.length,
      record: record,
      again: (_) => HandRummyScreen(progress: widget.progress, rng: _rng),
    );
  }

  void _newDeal() => setState(() {
    _game = HandRummy(makeHandRummy(_rng));
    _picked.clear();
    _staged.clear();
    _hints = 0;
    _note = null;
    _lost = false;
  });

  void _undo() => setState(() {
    final wasOpen = _game.opened;
    _game.undo();
    _picked.clear();
    _staged.clear();
    // laying out taken back: the melds are set aside again
    if (wasOpen && !_game.opened) _staged.addAll(_openedWith);
    _note = null;
    _recheck();
  });

  void _hint(S s) {
    final next = _game.next(staged: _staged);
    if (next == null) {
      _say(_game.opened ? s.handRummyStuck : s.handRummyBack);
      return;
    }
    if (next.open) {
      _say(s.handRummyOpenNow);
      return;
    }
    setState(() {
      _hints++;
      _picked
        ..clear()
        ..addAll(next.cards);
    });
  }

  List<int> _handShown() {
    final staged = {for (final m in _staged) ...m};
    final cards = [
      for (final c in _game.hand)
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

  void _meld(S s) {
    final cards = _picked.toList();
    if (Meld.of(cards) == null) {
      _say(s.rummyNo(RummyNo.notAMeld, _game.open));
      return;
    }
    if (_game.opened) {
      _do(() => _game.lay(cards), s);
    } else {
      setState(() {
        _staged.add(cards);
        _picked.clear();
        _recheck();
      });
    }
  }

  int _stagedPoints() =>
      _staged.fold(0, (s, m) => s + (Meld.of(m)?.points ?? 0));

  void _tapMeld(int i, S s, {bool swap = false}) {
    if (_picked.length != 1) {
      _say(s.pickOne);
      return;
    }
    final card = _picked.single;
    _do(() => _game.layOff(card, i, swap: swap), s);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF14143A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(s.handRummy),
        actions: [
          IconButton(
            key: const ValueKey('hr-hint'),
            tooltip: s.cardHint,
            onPressed: _game.done ? null : () => _hint(s),
            icon: const Icon(Icons.lightbulb_outline, color: _gold),
          ),
          IconButton(
            key: const ValueKey('hr-undo'),
            tooltip: s.undo,
            onPressed: _game.canUndo && !_game.done ? _undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            key: const ValueKey('hr-new'),
            tooltip: s.newCards,
            onPressed: _game.done ? null : _newDeal,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final cardW = ((c.maxWidth - 16) / 6.6).clamp(34.0, 64.0);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _status(s),
                  const SizedBox(height: 6),
                  _tableArea(s, cardW * 0.72),
                  if (!_game.opened) _stagedRow(s, cardW * 0.72),
                  const SizedBox(height: 10),
                  _hand(cardW),
                  const SizedBox(height: 8),
                  _buttons(s),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _status(S s) {
    final String line;
    if (_game.done) {
      line = s.handRummyDone;
    } else if (_lost) {
      line = _game.opened ? s.handRummyStuck : s.handRummyBack;
    } else if (_game.opened) {
      line = s.handRummyRest;
    } else {
      line = s.handRummyStart(_game.open);
    }
    final note = _note;
    return Text(
      note ?? line,
      key: const ValueKey('hr-status'),
      style: TextStyle(
        color: note != null ? _gold : Colors.white,
        fontSize: 17,
        fontWeight: note != null ? FontWeight.bold : null,
      ),
    );
  }

  Widget _tableArea(S s, double w) {
    final fits = _picked.length == 1 && _game.opened ? _picked.single : null;
    final table = _game.table;
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      decoration: BoxDecoration(
        color: _felt,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(8),
      child: table.isEmpty
          ? Center(
              child: Text(
                s.handRummyEmpty,
                style: const TextStyle(color: Colors.white54, fontSize: 15),
              ),
            )
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < table.length; i++)
                  _meldView(
                    table[i].cards,
                    w,
                    key: ValueKey('hr-meld-$i'),
                    mine: _game.mine[i],
                    hint:
                        fits != null &&
                        (table[i].withCard(fits) != null ||
                            table[i].swap(fits) != null),
                    onTap: () => _tapMeld(i, s),
                    onLongPress: () => _tapMeld(i, s, swap: true),
                  ),
              ],
            ),
    );
  }

  Widget _meldView(
    List<int> cards,
    double w, {
    Key? key,
    bool mine = false,
    bool hint = false,
    int? points,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) => GestureDetector(
    key: key,
    onTap: onTap,
    onLongPress: onLongPress,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
          if (points != null)
            Text(
              '$points',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
        ],
      ),
    ),
  );

  Widget _stagedRow(S s, double w) {
    final points = _stagedPoints();
    final enough = _staged.isNotEmpty && points >= _game.open;
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
                  child: Text(
                    s.stagedPoints(points, _game.open),
                    key: const ValueKey('hr-points'),
                    style: TextStyle(
                      color: enough ? const Color(0xFFA5D6A7) : Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ),
                FilledButton(
                  key: const ValueKey('hr-open'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF66BB6A),
                  ),
                  onPressed: enough
                      ? () {
                          _openedWith = [..._staged];
                          _do(() => _game.openWith([..._staged]), s);
                        }
                      : null,
                  child: Text(s.openBtn),
                ),
              ],
            ),
            Text(
              s.handRummyRules,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
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
                      key: ValueKey('hr-staged-$i'),
                      points: Meld.of(_staged[i])?.points,
                      onTap: () => setState(() {
                        _staged.removeAt(i);
                        _recheck();
                      }),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _hand(double w) => Wrap(
    spacing: 4,
    runSpacing: 8,
    alignment: WrapAlignment.center,
    children: [
      for (final id in _handShown())
        GestureDetector(
          key: ValueKey('hr-card-$id'),
          onTap: () => setState(
            () => _picked.contains(id) ? _picked.remove(id) : _picked.add(id),
          ),
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 120),
            offset: _picked.contains(id) ? const Offset(0, -0.12) : Offset.zero,
            child: PlayingCard(id, width: w, picked: _picked.contains(id)),
          ),
        ),
    ],
  );

  Widget _buttons(S s) => Row(
    children: [
      IconButton(
        key: const ValueKey('hr-sort'),
        tooltip: s.sortCards,
        onPressed: () => setState(() => _bySuit = !_bySuit),
        icon: const Icon(Icons.sort, color: Colors.white),
      ),
      const Spacer(),
      FilledButton(
        key: const ValueKey('hr-meld'),
        onPressed: _picked.length >= 3 ? () => _meld(s) : null,
        child: Text(_game.opened ? s.meldBtn : s.setAside),
      ),
    ],
  );
}
