// The collection of a world: one slot per phrase on a planet's surface.
// A well spoken word flies into its slot; missing ones show as a shadow,
// so the child sees what is still to be found.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/emoji_image.dart';

/// An emoji as a flat white shadow (not collected yet).
class EmojiShadow extends StatelessWidget {
  const EmojiShadow(this.emoji, {super.key, required this.size});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) => ColorFiltered(
    colorFilter: const ColorFilter.mode(Color(0x33FFFFFF), BlendMode.srcIn),
    child: EmojiImage(emoji, size: size),
  );
}

/// Slots for [emojis]; [collected] says which are found. [current] gets a
/// glowing ring. [slotKeys] (optional, same length) locate the slots for the
/// flight animation. [bounce] slot jumps once when it changes.
class WorldScene extends StatelessWidget {
  const WorldScene({
    super.key,
    required this.emojis,
    required this.collected,
    this.current,
    this.slotKeys,
    this.bounce,
    this.maxSlot = 44,
  });

  final List<String> emojis;
  final List<bool> collected;
  final int? current;
  final List<GlobalKey>? slotKeys;
  final int? bounce;
  final double maxSlot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final slot = math.min(maxSlot, (c.maxWidth - 24) / emojis.length - 4);
        return Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF5B3FA8), Color(0xFF2E1F66)],
            ),
            borderRadius: BorderRadius.vertical(
              top: Radius.elliptical(400, 40),
              bottom: Radius.circular(16),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < emojis.length; i++)
                Container(
                  key: slotKeys?[i],
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: slot,
                  height: slot,
                  decoration: i == current
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFFD54F),
                            width: 2,
                          ),
                        )
                      : null,
                  alignment: Alignment.center,
                  child: collected[i]
                      ? _Pop(
                          key: ValueKey('slot-$i-${bounce == i}'),
                          active: bounce == i,
                          child: EmojiImage(emojis[i], size: slot * 0.8),
                        )
                      : EmojiShadow(emojis[i], size: slot * 0.7),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Jumps once when built with [active].
class _Pop extends StatelessWidget {
  const _Pop({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.8, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: child,
    );
  }
}

/// The finished world: all found pictures dance in a wave.
class DancingScene extends StatefulWidget {
  const DancingScene({
    super.key,
    required this.emojis,
    required this.collected,
  });

  final List<String> emojis;
  final List<bool> collected;

  @override
  State<DancingScene> createState() => _DancingSceneState();
}

class _DancingSceneState extends State<DancingScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.emojis.length;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 10,
        children: [
          for (var i = 0; i < n; i++)
            Transform.translate(
              offset: widget.collected[i]
                  ? Offset(
                      0,
                      -12 *
                          math.max(
                            0,
                            math.sin((_c.value - i / n) * 2 * math.pi),
                          ),
                    )
                  : Offset.zero,
              child: widget.collected[i]
                  ? EmojiImage(widget.emojis[i], size: 52)
                  : EmojiShadow(widget.emojis[i], size: 52),
            ),
        ],
      ),
    );
  }
}
