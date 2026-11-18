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
        title: Row(
          children: [
            const EmojiImage('🏆', size: 48),
            const SizedBox(width: 12),
            Flexible(child: Text(s.worldDone)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Opacity(
                    opacity: i < stars ? 1 : 0.25,
                    child: const EmojiImage('⭐', size: 40),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('$right / $total', style: const TextStyle(fontSize: 22)),
            if (record) Text(s.newRecord),
          ],
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
