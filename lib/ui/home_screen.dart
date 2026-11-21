import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/phrases.dart';
import '../game/play_screen.dart';
import '../game/world_scene.dart';
import '../listen/listen_screen.dart';
import '../quiz/quiz_screen.dart';
import '../read/read_aloud_screen.dart';
import '../spell/spell_screen.dart';
import '../think/think_screen.dart';
import '../voice/voice_screen.dart';
import 'audio_badge.dart';
import 'emoji_image.dart';
import 'feedback_screen.dart';
import 'game_tile.dart';
import 'strings.dart';
import 'word_list_screen.dart';

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

  Future<void> _push(Widget Function() screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen()));
    setState(() {});
  }

  /// The games besides the worlds, by what the child practises (not by
  /// how it answers: the quiz is thinking, answered by speaking), in the
  /// order shown.
  List<GameGroup> _groups(S s) {
    final quiz = (
      screen: () => QuizScreen(app: app),
      emojis: const ['🦉'],
      name: s.quizTitle,
      audio: Audio.both,
    );
    final listen = (
      screen: () => ListenScreen(app: app),
      emojis: const ['👂'],
      name: s.listenTitle,
      audio: Audio.output,
    );
    final spell = (
      screen: () => SpellScreen(app: app),
      emojis: const ['✏️'],
      name: s.spellTitle,
      audio: Audio.output,
    );
    final readPick = (
      screen: () => ListenScreen(app: app, reading: true),
      emojis: const ['📖', '🐮'],
      name: s.readPickTitle,
      audio: Audio.output,
    );
    final readAloud = (
      screen: () => ReadAloudScreen(app: app),
      emojis: const ['📖', '🎤'],
      name: s.readAloudTitle,
      audio: Audio.both,
    );
    final sounds = (
      screen: () => QuizScreen(app: app, sounds: true),
      emojis: const ['🔔'],
      name: s.soundsTitle,
      audio: Audio.both,
    );
    final needs = (
      screen: () => ThinkScreen(app: app, game: ThinkGame.needs),
      emojis: const ['🧤', '☂️'],
      name: s.needsTitle,
      audio: Audio.output,
    );
    final riddle = (
      screen: () => ThinkScreen(app: app, game: ThinkGame.riddle),
      emojis: const ['🐮', '🔊'],
      name: s.riddleTitle,
      audio: Audio.output,
    );
    final hold = (
      screen: () => VoiceGameScreen(app: app, game: VoiceGame.hold),
      emojis: const ['🎈'],
      name: s.holdTitle,
      audio: Audio.both,
    );
    final pitch = (
      screen: () => VoiceGameScreen(app: app, game: VoiceGame.pitch),
      emojis: const ['🐻', '🐭'],
      name: s.pitchTitle,
      audio: Audio.both,
    );
    return [
      (key: 'hear', emoji: '👂', name: s.hearGroup, games: [listen, sounds]),
      (
        key: 'read',
        emoji: '📖',
        name: s.readGroup,
        games: [readPick, spell, readAloud],
      ),
      (key: 'speak', emoji: '🎤', name: s.speakGroup, games: [hold, pitch]),
      (
        key: 'think',
        emoji: '🤔',
        name: s.thinkGroup,
        games: [needs, riddle, quiz],
      ),
    ];
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
          if (app.feedback != null)
            IconButton(
              tooltip: s.feedbackTitle,
              onPressed: () => _push(() => FeedbackScreen(app: app)),
              icon: const Icon(Icons.mail_outline, size: 30),
            ),
          IconButton(
            tooltip: s.wordsTitle,
            onPressed: () => _push(() => WordListScreen(app: app)),
            icon: const EmojiImage('📖', size: 32),
          ),
          IconButton(
            tooltip: s.chooseLanguage,
            onPressed: _chooseLanguage,
            icon: EmojiImage(languageFlags[book.lang]!, size: 32),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // the games besides the worlds, by kind, two in a row
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: tileRows([
                  for (final g in _groups(s))
                    GameTile(
                      key: ValueKey('group-${g.key}'),
                      emojis: [g.emoji],
                      name: g.name,
                      emojiSize: 56,
                      onTap: () => _push(() => GroupScreen(group: g)),
                    ),
                ], 2),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid.builder(
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
                  color: open
                      ? const Color(0xFF2B2B6B)
                      : const Color(0xFF1D1D45),
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
                                emojis: [
                                  for (final p in book.world(w)) p.emoji,
                                ],
                                collected: [
                                  for (final p in book.world(w))
                                    open &&
                                        app.progress.stars(book.lang, p.text) >=
                                            1,
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // large text: the stars shrink, never overflow
                          if (open)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
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
                              ),
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
          ),
        ],
      ),
    );
  }
}
