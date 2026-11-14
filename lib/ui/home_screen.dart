import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/phrases.dart';
import '../game/play_screen.dart';
import '../game/world_scene.dart';
import 'emoji_image.dart';
import 'strings.dart';

/// Language switch + world map. Each world shows its collection (pictures
/// with at least one star) and the stars collected so far.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.app});

  final AppState app;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppState get app => widget.app;

  Future<void> _chooseLanguage() async {
    final s = S.of(context);
    final lang = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                s.chooseLanguage,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            for (final l in studyLanguages)
              ListTile(
                leading: EmojiImage(languageFlags[l]!, size: 36),
                title: Text(
                  languageNames[l]!,
                  style: const TextStyle(fontSize: 20),
                ),
                selected: l == app.book.lang,
                onTap: () => Navigator.pop(ctx, l),
              ),
          ],
        ),
      ),
    );
    if (lang != null && lang != app.book.lang) {
      await app.switchLanguage(lang);
      setState(() {});
    }
  }

  Future<void> _open(int world) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayScreen(app: app, world: world),
      ),
    );
    setState(() {}); // refresh stars
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final book = app.book;
    return Scaffold(
      backgroundColor: const Color(0xFF14143A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(s.title),
        actions: [
          IconButton(
            tooltip: s.chooseLanguage,
            onPressed: _chooseLanguage,
            icon: EmojiImage(languageFlags[book.lang]!, size: 32),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: book.worldCount,
        itemBuilder: (context, w) {
          final open = app.worldOpen(w);
          final stars = app.worldStars(w);
          final max = book.world(w).length * 3;
          return Material(
            color: open ? const Color(0xFF2B2B6B) : const Color(0xFF1D1D45),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: open ? () => _open(w) : null,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // the world's collection: found pictures, shadows for the rest
                    Expanded(
                      child: Opacity(
                        opacity: open ? 1 : 0.4,
                        child: CollectionGrid(
                          emojis: [for (final p in book.world(w)) p.emoji],
                          collected: [
                            for (final p in book.world(w))
                              open &&
                                  app.progress.stars(book.lang, p.text) >= 1,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (open)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const EmojiImage('⭐', size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '$stars/$max',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )
                    else
                      const EmojiImage('🔒', size: 22),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
