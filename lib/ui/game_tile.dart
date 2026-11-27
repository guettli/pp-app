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

  /// Stars (0..3) of the best round, null for games without stars.
  int Function()? best,
});

/// Stars of the best rounds of [games] and the most there are.
(int, int)? groupStars(List<Game> games) {
  var got = 0, max = 0;
  for (final g in games) {
    final best = g.best;
    if (best == null) continue;
    got += best();
    max += 3;
  }
  return max == 0 ? null : (got, max);
}

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
    this.stars,
    this.total,
    this.emojiSize = 48,
  });

  final List<String> emojis;
  final String name;
  final VoidCallback onTap;
  final Audio? audio;

  /// The best round of the game: three stars, the earned ones bright.
  final int? stars;

  /// A group: stars earned of all there are.
  final (int, int)? total;
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
              if (stars case final n?) ...[
                const SizedBox(height: 4),
                Row(
                  key: ValueKey('stars-$n'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Opacity(
                        opacity: i < n ? 1 : 0.25,
                        child: const EmojiImage('⭐', size: 20),
                      ),
                  ],
                ),
              ],
              if (total case (final got, final max)) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const EmojiImage('⭐', size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '$got/$max',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
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

/// Tells screens that list stars when they are on top again (in the
/// app's MaterialApp): 🔁 at a round's end replaces the game with a new
/// one, so the screen that opened the first round does not see the
/// second one end.
final starRoutes = RouteObserver<ModalRoute<void>>();

/// The games of one group, two in a row, each with the stars of its best
/// round.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.group});

  final GameGroup group;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> with RouteAware {
  GameGroup get group => widget.group;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) starRoutes.subscribe(this, route);
  }

  @override
  void dispose() {
    starRoutes.unsubscribe(this);
    super.dispose();
  }

  /// A game (or the one 🔁 started in its place) closed: new stars.
  @override
  void didPopNext() {
    if (mounted) setState(() {});
  }

  Future<void> _open(Game g) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => g.screen()));
    if (mounted) setState(() {}); // new stars
  }

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
                stars: g.best?.call(),
                emojiSize: 64,
                onTap: () => _open(g),
              ),
          ], 2),
        ),
      ),
    );
  }
}
