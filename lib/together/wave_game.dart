// The first game two linked phones play: wave at each other. A tap on the
// hand waves on the other phone too; it shows that the link works.
import 'dart:async';

import 'package:flutter/material.dart';

import '../net/peer_link.dart';
import '../ui/emoji_image.dart';
import '../ui/strings.dart';

class WaveGame extends StatefulWidget {
  const WaveGame({
    super.key,
    required this.link,
    required this.me,
    required this.friend,
    required this.onGone,
  });

  final PeerLink link;

  /// The pictures of this phone's player and the other.
  final String me;
  final String friend;

  /// The link was lost.
  final VoidCallback onGone;

  @override
  State<WaveGame> createState() => _WaveGameState();
}

class _WaveGameState extends State<WaveGame> {
  late final StreamSubscription<Map<String, dynamic>> _sub;
  var _friendWaves = 0;
  var _myWaves = 0;
  var _gone = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.link.messages.listen(
      (m) {
        if (m['t'] == 'wave' && mounted) setState(() => _friendWaves++);
      },
      onDone: () {
        if (mounted) setState(() => _gone = true);
      },
    );
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }

  void _wave() {
    widget.link.send({'t': 'wave'});
    setState(() => _myWaves++);
  }

  Widget _player(String emoji, int waves, String key) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      EmojiImage(emoji, size: 88),
      // a new hand on every wave: the switcher animates it in
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, a) => RotationTransition(
          turns: Tween(begin: -0.1, end: 0.0).animate(a),
          child: ScaleTransition(scale: a, child: child),
        ),
        child: waves == 0
            ? const SizedBox(width: 72, height: 72)
            : EmojiImage('👋', key: ValueKey('$key-$waves'), size: 72),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (_gone) {
      return Center(
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
            FilledButton(
              key: const ValueKey('together-again'),
              onPressed: widget.onGone,
              child: Text(s.tryAgain),
            ),
          ],
        ),
      );
    }
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _player(widget.me, _myWaves, 'wave-me'),
                _player(widget.friend, _friendWaves, 'wave-friend'),
              ],
            ),
            const SizedBox(height: 24),
            Material(
              color: const Color(0xFFFFD54F),
              shape: const CircleBorder(),
              child: InkWell(
                key: const ValueKey('wave-button'),
                customBorder: const CircleBorder(),
                onTap: _wave,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Tooltip(
                    message: s.wave,
                    child: const EmojiImage('👋', size: 72),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
