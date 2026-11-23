// Where the table gets its view and sends its moves: a game against the
// Hase on this phone, or a game over the link. Over the link the host's
// phone runs the game and sends the guest its view after every change;
// the guest sends its moves (so the guest never sees the host's hand).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../net/peer_link.dart';
import 'rummy_hase.dart';
import 'rummy_rules.dart';

abstract class RummySeat extends ChangeNotifier {
  /// Null until the first view arrived (guest).
  RummyView? get view;

  /// Why my last move was refused, until the next view.
  RummyNo? get refused;

  /// The other phone is gone.
  bool get gone;

  /// A move is on its way (guest): the table waits.
  bool get busy => false;

  void move(RummyMove m);
}

abstract class _EngineSeat extends RummySeat {
  _EngineSeat(RummyRules rules, math.Random? rng)
    : game = RummyGame(rules, rng: rng);

  final RummyGame game;
  RummyNo? _refused;
  var _disposed = false;

  @override
  RummyView get view => game.view(0);
  @override
  RummyNo? get refused => _refused;

  @override
  void move(RummyMove m) {
    _refused = game.apply(0, m);
    changed();
  }

  /// The game changed.
  @protected
  void changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Against the Hase: it moves one card at a time, so you can follow.
class HaseSeat extends _EngineSeat {
  HaseSeat(
    RummyRules rules, {
    math.Random? rng,
    this.pause = const Duration(milliseconds: 700),
  }) : super(rules, rng);

  final Duration pause;
  Timer? _timer;
  var _moves = 0;

  @override
  bool get gone => false;

  @override
  void changed() {
    super.changed();
    _next();
  }

  void _next() {
    if (_disposed || _timer != null) return;
    if (game.turn != 1 || game.phase == RummyPhase.over) {
      _moves = 0;
      return;
    }
    _timer = Timer(pause, () {
      _timer = null;
      if (_disposed) return;
      final v = game.view(1);
      // (a refused move would be a bug in the Hase: play safe then)
      if (++_moves > 60 || game.apply(1, haseMove(v)) != null) {
        _safeMove(v);
      }
      changed();
    });
  }

  void _safeMove(RummyView v) {
    if (v.phase == RummyPhase.draw) {
      game.apply(1, const DrawStock());
    } else if (v.fromPile != null && !v.opened[1]) {
      game.apply(1, const PutBack());
    } else {
      for (final c in v.hand) {
        if (game.apply(1, Discard(c)) == null) return;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The host's phone: runs the game; the guest plays player 1.
class HostSeat extends _EngineSeat {
  HostSeat(this.link, RummyRules rules, {math.Random? rng})
    : super(rules, rng) {
    _sub = link.messages.listen(_onMessage, onDone: _lost);
    _send();
  }

  final PeerLink link;
  late final StreamSubscription<Map<String, dynamic>> _sub;
  var _gone = false;

  @override
  bool get gone => _gone;

  void _onMessage(Map<String, dynamic> msg) {
    if (msg['t'] != 'move') return;
    final m = RummyMove.fromJson(msg);
    final no = m == null ? RummyNo.notAMeld : game.apply(1, m);
    if (no != null) link.send({'t': 'no', 'why': no.name});
    changed();
  }

  void _send() => link.send({'t': 'state', 'v': game.view(1).toJson()});

  @override
  void changed() {
    if (!_gone) _send();
    super.changed();
  }

  void _lost() {
    _gone = true;
    super.changed();
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

/// The guest's phone: shows what the host sends.
class GuestSeat extends RummySeat {
  GuestSeat(this.link) {
    _sub = link.messages.listen(_onMessage, onDone: _lost);
  }

  final PeerLink link;
  late final StreamSubscription<Map<String, dynamic>> _sub;
  RummyView? _view;
  RummyNo? _refused;
  var _gone = false;
  var _busy = false;
  var _disposed = false;

  @override
  RummyView? get view => _view;
  @override
  RummyNo? get refused => _refused;
  @override
  bool get gone => _gone;
  @override
  bool get busy => _busy;

  void _onMessage(Map<String, dynamic> msg) {
    switch (msg['t']) {
      case 'state':
        final v = RummyView.fromJson(
          (msg['v'] as Map? ?? const {}).cast<String, dynamic>(),
        );
        if (v == null) return;
        // a refusal stays shown until the next move
        if (_busy) _refused = null;
        _view = v;
        _busy = false;
      case 'no':
        _refused = RummyNo.values.asNameMap()[msg['why']] ?? RummyNo.notAMeld;
        _busy = false;
      default:
        return;
    }
    _changed();
  }

  @override
  void move(RummyMove m) {
    if (_busy || _gone) return; // one at a time (a double tap)
    _busy = true;
    _refused = null;
    link.send({'t': 'move', ...m.toJson()});
    _changed();
  }

  void _lost() {
    _gone = true;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sub.cancel());
    super.dispose();
  }
}
