// Parts every round game shares (quiz, listen, spell): the dots on top
// and the dialog at the end of a round.
import 'package:flutter/material.dart';

import 'emoji_image.dart';
import 'strings.dart';

/// One dot per question: a star when right, grey when wrong, the current
/// one with a thick ring.
class ProgressDots extends StatelessWidget {
  const ProgressDots({super.key, required this.results, required this.index});

  /// Per question: right (true), wrong (false), not yet (null).
  final List<bool?> results;
  final int index;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (i, r) in results.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: r == true
                ? const EmojiImage('⭐', size: 26)
                : Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: r == false ? Colors.white24 : null,
                      border: Border.all(
                        color: i == index ? Colors.white : Colors.white38,
                        width: i == index ? 3 : 2,
                      ),
                    ),
                  ),
          ),
      ],
    ),
  );
}

/// The end of a round: [stars] of 3, [right] of [total], a new record.
/// OK closes the dialog and the game. The back button cannot close it.
///
/// Not a still box: the hare of "Der Hase lacht" jumps for joy (higher
/// and more often the more stars), and the stars pop in one after the
/// other. All of it once, about two seconds (no endless animation).
Future<void> showRoundEnd(
  BuildContext context, {
  required int stars,
  required int right,
  required int total,
  required bool record,
}) {
  final s = S.of(context);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        // a short screen with large text: the content scrolls, the OK
        // button (actions) stays in view
        scrollable: true,
        title: Row(
          children: [
            const EmojiImage('🏆', size: 48),
            const SizedBox(width: 12),
            Flexible(child: Text(s.worldDone)),
          ],
        ),
        content: RoundEndCheer(
          stars: stars,
          right: right,
          total: total,
          record: record ? s.newRecord : null,
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: Text(s.ok),
          ),
        ],
      ),
    ),
  );
}

/// The jumping hare and the stars popping in, for [showRoundEnd].
class RoundEndCheer extends StatefulWidget {
  const RoundEndCheer({
    super.key,
    required this.stars,
    required this.right,
    required this.total,
    this.record,
  });

  final int stars;
  final int right;
  final int total;

  /// "New record!" when it is one.
  final String? record;

  @override
  State<RoundEndCheer> createState() => _RoundEndCheerState();
}

class _RoundEndCheerState extends State<RoundEndCheer>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0..1 while star [i] pops in (a little bounce past full size).
  double _pop(int i) {
    final start = 0.15 + i * 0.18;
    final v = ((_c.value - start) / 0.25).clamp(0.0, 1.0);
    return Curves.elasticOut.transform(v);
  }

  /// How high the hare is: jumps (one more per star), lower each time.
  double _jump() {
    final jumps = widget.stars.clamp(0, 3) + 1;
    final x = _c.value * jumps;
    final n = x.floor();
    if (n >= jumps) return 0;
    final f = x - n;
    return 4 * f * (1 - f) * (1 - n / (jumps + 1));
  }

  Widget _hare(double size, double lift) => Transform.translate(
    offset: Offset(0, -lift * _jump()),
    child: EmojiImage('🐰', key: const ValueKey('cheer-hare'), size: size),
  );

  Widget _stars() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 3; i++)
        Opacity(
          opacity: i < widget.stars ? 1 : 0.25,
          child: Transform.scale(
            scale: i < widget.stars ? _pop(i) : 1,
            child: const EmojiImage('⭐', size: 40),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // landscape: no room above, the hare beside the stars, lower jumps
    final short = MediaQuery.sizeOf(context).height < 500;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (short)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 64,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _hare(44, 18),
                  ),
                ),
                const SizedBox(width: 12),
                _stars(),
              ],
            )
          else ...[
            SizedBox(
              height: 112,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _hare(72, 36),
              ),
            ),
            _stars(),
          ],
          const SizedBox(height: 8),
          Text(
            '${widget.right} / ${widget.total}',
            style: const TextStyle(fontSize: 22),
          ),
          if (widget.record case final r?) Text(r),
        ],
      ),
    );
  }
}
