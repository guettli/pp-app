import 'package:flutter/material.dart';

/// Asset key for an emoji: lowercase hex code points without FE0F, "-"-joined.
/// Must match tool/fetch_emoji.py.
String emojiKey(String emoji) => emoji.runes
    .where((r) => r != 0xFE0F)
    .map((r) => r.toRadixString(16))
    .join('-');

/// Fluent Emoji 3D image (MIT, Microsoft), falling back to the system font.
class EmojiImage extends StatelessWidget {
  const EmojiImage(this.emoji, {super.key, this.size = 64});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/emoji/${emojiKey(emoji)}.webp',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(emoji, style: TextStyle(fontSize: size * 0.8)),
        ),
      ),
    );
  }
}
