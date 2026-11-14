import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/emoji_image.dart';

/// A rocket on the right edge. When [target] (0..1) is set, it launches and
/// climbs to that height; the planet at the top is reached at 3 stars.
class RocketLaunch extends StatefulWidget {
  const RocketLaunch({super.key, required this.target, required this.stars});

  final double? target;
  final int stars;

  @override
  State<RocketLaunch> createState() => _RocketLaunchState();
}

class _RocketLaunchState extends State<RocketLaunch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.target != null) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const rocket = 56.0;
        final bottom = box.maxHeight * 0.38; // above the buttons and the scene
        final top = 70.0;
        final track = math.max(0.0, box.maxHeight - bottom - top - rocket);
        // Map similarity so that 3 stars (>= 0.85) reaches the planet.
        final goal = ((widget.target ?? 0) / 0.85).clamp(0.0, 1.0);
        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Curves.easeOutBack.transform(_c.value).clamp(0.0, 1.1);
            final y = bottom + track * goal * t;
            final shake = _c.isAnimating ? math.sin(_c.value * 60) * 2 : 0.0;
            final done = _c.isCompleted;
            return Stack(
              children: [
                Positioned(
                  right: 12,
                  top: top - 64,
                  child: const EmojiImage('🪐', size: 64),
                ),
                Positioned(
                  right: 24 + shake,
                  bottom: y,
                  child: Column(
                    children: [
                      Transform.rotate(
                        angle: -math.pi / 4,
                        child: const EmojiImage('🚀', size: rocket),
                      ),
                      if (_c.isAnimating)
                        Container(
                          width: 14,
                          height: 30 * (1 - _c.value) + 6,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.orangeAccent, Colors.transparent],
                            ),
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                    ],
                  ),
                ),
                if (done && widget.target != null)
                  Positioned(
                    right: 8,
                    bottom: y + rocket + 8,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.elasticOut,
                      builder: (_, v, _) => Transform.scale(
                        scale: v,
                        child: Row(
                          children: List.generate(
                            3,
                            (i) => Opacity(
                              opacity: i < widget.stars ? 1 : 0.2,
                              child: const EmojiImage('⭐', size: 28),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Slowly twinkling stars in the background.
class Starfield extends StatefulWidget {
  const Starfield({super.key});

  @override
  State<Starfield> createState() => _StarfieldState();
}

class _StarfieldState extends State<Starfield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();
  final _stars = List.generate(70, (i) {
    final r = math.Random(i);
    return (
      r.nextDouble(),
      r.nextDouble(),
      r.nextDouble() * 2 + 0.5,
      r.nextDouble(),
    );
  });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(child: CustomPaint(painter: _StarPainter(_stars, _c)));
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.stars, this.anim) : super(repaint: anim);

  final List<(double, double, double, double)> stars;
  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final (x, y, r, phase) in stars) {
      final a =
          0.4 +
          0.6 * (0.5 + 0.5 * math.sin((anim.value + phase) * 2 * math.pi));
      p.color = Colors.white.withValues(alpha: a);
      canvas.drawCircle(Offset(x * size.width, y * size.height), r, p);
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => false;
}
