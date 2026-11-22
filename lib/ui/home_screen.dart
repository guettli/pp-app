import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/phrases.dart';
import '../game/play_screen.dart';
import '../game/world_scene.dart';
import '../listen/listen_screen.dart';
import '../memory/memory_rules.dart';
import '../memory/memory_screen.dart';
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
      // five languages and a title: more than half of a small phone
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
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
      ),
    );
    if (lang != null && lang != app.book.lang) {
      await app.switchLanguage(lang);
      // new in the other language, not in this one
      setState(_fresh.clear);
    }
  }

  /// Worlds opened by the last world played: they sparkle until tapped.
  final _fresh = <int>{};

  Future<void> _open(int world) async {
    setState(() => _fresh.remove(world));
    final before = [
      for (var w = 0; w < app.book.worldCount; w++) app.worldOpen(w),
    ];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayScreen(app: app, world: world),
      ),
    );
    if (!mounted) return;
    setState(() {
      // refresh stars; a world that just opened: shown as new
      for (var w = 0; w < before.length; w++) {
        if (!before[w] && app.worldOpen(w)) _fresh.add(w);
      }
    });
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
    final p = app.progress;
    final lang = app.book.lang;
    final quiz = (
      screen: () => QuizScreen(app: app),
      emojis: const ['🦉'],
      name: s.quizTitle,
      audio: Audio.both,
      best: () => p.quizBest(lang),
    );
    final listen = (
      screen: () => ListenScreen(app: app),
      emojis: const ['👂'],
      name: s.listenTitle,
      audio: Audio.output,
      best: () => p.listenBest(lang),
    );
    final spell = (
      screen: () => SpellScreen(app: app),
      emojis: const ['✏️'],
      name: s.spellTitle,
      audio: Audio.output,
      best: () => p.spellBest(lang),
    );
    final readPick = (
      screen: () => ListenScreen(app: app, reading: true),
      emojis: const ['📖', '🐮'],
      name: s.readPickTitle,
      audio: Audio.output,
      best: () => p.readPickBest(lang),
    );
    final readAloud = (
      screen: () => ReadAloudScreen(app: app),
      emojis: const ['📖', '🎤'],
      name: s.readAloudTitle,
      audio: Audio.both,
      best: () => p.readAloudBest(lang),
    );
    final sounds = (
      screen: () => QuizScreen(app: app, sounds: true),
      emojis: const ['🔔'],
      name: s.soundsTitle,
      audio: Audio.both,
      best: () => p.soundsBest(lang),
    );
    final needs = (
      screen: () => ThinkScreen(app: app, game: ThinkGame.needs),
      emojis: const ['🧤', '☂️'],
      name: s.needsTitle,
      audio: Audio.output,
      best: () => p.thinkBest('needs', lang),
    );
    final riddle = (
      screen: () => ThinkScreen(app: app, game: ThinkGame.riddle),
      emojis: const ['🐮', '🔊'],
      name: s.riddleTitle,
      audio: Audio.output,
      best: () => p.thinkBest('riddle', lang),
    );
    final hold = (
      screen: () => VoiceGameScreen(app: app, game: VoiceGame.hold),
      emojis: const ['🎈'],
      name: s.holdTitle,
      audio: Audio.both,
      best: null,
    );
    final pitch = (
      screen: () => VoiceGameScreen(app: app, game: VoiceGame.pitch),
      emojis: const ['🐻', '🐭'],
      name: s.pitchTitle,
      audio: Audio.both,
      best: null,
    );
    final odd = (
      screen: () => ThinkScreen(app: app, game: ThinkGame.odd),
      emojis: const ['🐶', '🐱', '🚗'],
      name: s.oddTitle,
      audio: Audio.output,
      best: () => p.thinkBest('odd', lang),
    );
    final home = (
      screen: () => ThinkScreen(app: app, game: ThinkGame.home),
      emojis: const ['🌊', '🐟'],
      name: s.homeTitle,
      audio: Audio.output,
      best: () => p.thinkBest('home', lang),
    );
    final faces = (
      screen: () => ThinkScreen(app: app, game: ThinkGame.faces),
      emojis: const ['😄', '😠'],
      name: s.facesTitle,
      audio: Audio.output,
      best: () => p.thinkBest('faces', lang),
    );
    final feelings = (
      screen: () => ThinkScreen(app: app, game: ThinkGame.feelings),
      emojis: const ['🍦', '😢'],
      name: s.feelingsTitle,
      audio: Audio.output,
      best: () => p.thinkBest('feelings', lang),
    );
    Game memory(MemoryGame g, List<String> emojis, String name) => (
      screen: () => MemoryScreen(app: app, game: g),
      emojis: emojis,
      name: name,
      audio: g == MemoryGame.say ? Audio.both : Audio.output,
      best: () => p.thinkBest(MemoryScreen.progressKey(g), lang),
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
        games: [needs, riddle, odd, home, quiz],
      ),
      (
        key: 'memory',
        emoji: '🧠',
        name: s.memoryGroup,
        games: [
          memory(MemoryGame.look, const ['👀'], s.lookTitle),
          memory(MemoryGame.hear, const ['👂', '💬'], s.hearWordsTitle),
          memory(MemoryGame.missing, const ['❓'], s.missingTitle),
          memory(MemoryGame.say, const ['👀', '🎤'], s.sayWhatTitle),
        ],
      ),
      (key: 'feel', emoji: '😄', name: s.feelGroup, games: [faces, feelings]),
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
                      total: groupStars(g.games),
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
                final fresh = open && _fresh.contains(w);
                final tile = Material(
                  color: open
                      ? const Color(0xFF2B2B6B)
                      : const Color(0xFF1D1D45),
                  // a world that just opened: a golden frame
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: fresh
                        ? const BorderSide(color: Color(0xFFFFD54F), width: 4)
                        : BorderSide.none,
                  ),
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
                // always in a Stack: the tap's ripple stays when ✨ goes
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: tile),
                    if (fresh)
                      Positioned(
                        top: -6,
                        right: -6,
                        child: IgnorePointer(
                          child: EmojiImage(
                            '✨',
                            key: ValueKey('world-new-$w'),
                            size: 32,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
