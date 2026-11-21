// The games besides the worlds: a tile per game (big pictures for the
// child, the name and what it does with sound for the grown-ups), and the
// groups they are sorted into on the home screen (👂 listen, 📖 read,
// 🎤 speak, 🤔 think), each opening a screen with its games.
import 'package:flutter/material.dart';

import 'audio_badge.dart';
import 'emoji_image.dart';

/// A game besides the worlds.
typedef Game = ({
  Widget Function() screen,
  List<String> emojis,
  String name,
  Audio audio,
});

/// Games of one kind on the home screen.
typedef GameGroup = ({String key, String emoji, String name, List<Game> games});

const tileColor = Color(0xFF3B2B7B);

/// Big pictures, the name below, then (if given) the sound badge. Fills
/// the height it gets, so tiles of a row line up.
class GameTile extends StatelessWidget {
  const GameTile({
    super.key,
    required this.emojis,
    required this.name,
    required this.onTap,
    this.audio,
    this.emojiSize = 48,
  });

  final List<String> emojis;
  final String name;
  final VoidCallback onTap;
  final Audio? audio;
  final double emojiSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tileColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              // a narrow tile: the pictures shrink
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in emojis) EmojiImage(e, size: emojiSize),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (audio != null) ...[
                const Spacer(),
                const SizedBox(height: 6),
                AudioBadge(audio!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// [tiles] in rows of [perRow], the tiles of a row as high as the highest
/// (names may wrap); a short last row keeps the tile width.
List<Widget> tileRows(List<Widget> tiles, int perRow, {double gap = 12}) => [
  for (var i = 0; i < tiles.length; i += perRow)
    Padding(
      padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = i; j < i + perRow; j++) ...[
              if (j > i) SizedBox(width: gap),
              Expanded(child: j < tiles.length ? tiles[j] : const SizedBox()),
            ],
          ],
        ),
      ),
    ),
];

/// The games of one group, two in a row.
class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key, required this.group});

  final GameGroup group;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14143A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            EmojiImage(group.emoji, size: 32),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      // a few games: all built at once (no lazy list)
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: tileRows([
            for (final (i, g) in group.games.indexed)
              GameTile(
                key: ValueKey('game-${group.key}-$i'),
                emojis: g.emojis,
                name: g.name,
                audio: g.audio,
                emojiSize: 64,
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => g.screen())),
              ),
          ], 2),
        ),
      ),
    );
  }
}
