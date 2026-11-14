import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phoneme_party/game/world_scene.dart';
import 'package:phoneme_party/ui/emoji_image.dart';

void main() {
  const emojis = ['🐶', '🐱', '🍎', '⚽', '🚗', '🌙', '🐟', '🏠'];
  final collected = [true, false, true, false, false, false, false, true];

  Widget app(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, child: child)),
    ),
  );

  testWidgets('found pictures are shown, the rest as shadows', (t) async {
    final keys = List.generate(8, (_) => GlobalKey());
    await t.pumpWidget(
      app(
        WorldScene(
          emojis: emojis,
          collected: collected,
          current: 1,
          slotKeys: keys,
          bounce: 0,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(EmojiShadow), findsNWidgets(5));
    expect(find.byType(EmojiImage), findsNWidgets(8)); // shadows wrap one too
    // every slot can be located for the flight, and they fit the width
    for (final k in keys) {
      final box = k.currentContext!.findRenderObject() as RenderBox;
      expect(box.size.width, greaterThan(30));
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('slots shrink on a narrow screen instead of overflowing', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: WorldScene(emojis: emojis, collected: collected),
            ),
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('the finished world dances without errors', (t) async {
    await t.pumpWidget(app(DancingScene(emojis: emojis, collected: collected)));
    await t.pump(const Duration(milliseconds: 700));
    expect(find.byType(EmojiShadow), findsNWidgets(5));
    expect(t.takeException(), isNull);
  });
}
