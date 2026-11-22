// The rounds of the memory games, made from the pictures the child knows.
import 'dart:math' as math;

import '../data/phrases.dart';
import '../think/think_rules.dart' show bareEmoji;

/// The name is the key of the best round in [Progress.thinkBest] (with
/// the prefix "memory-").
enum MemoryGame {
  /// Pictures are shown, hidden, then found among more.
  look,

  /// Words are said (no pictures), then their pictures found among more.
  hear,

  /// Pictures are shown, hidden, shown again without one: which is gone?
  missing,

  /// Pictures are shown, hidden, then the child names them (microphone).
  say,
}

/// One question of a memory game.
class MemoryQuestion {
  const MemoryQuestion(this.shown, this.options, {this.missing});

  /// What is shown (or said), in this order.
  final List<Phrase> shown;

  /// The pictures to tap afterwards, in the order shown.
  final List<Phrase> options;

  /// "What's missing?": the one of [shown] hidden the second time.
  final Phrase? missing;

  /// The pictures the child must tap.
  List<Phrase> get answers => missing == null ? shown : [missing!];

  @override
  String toString() =>
      '${shown.map((p) => p.emoji).join(' ')} -> '
      '${options.map((p) => p.emoji).join(' ')}'
      '${missing == null ? '' : ' (${missing!.emoji})'}';
}

/// How many pictures each question shows: a little more as the round goes.
const memorySizes = <MemoryGame, List<int>>{
  MemoryGame.look: [2, 3, 3, 3, 4],
  MemoryGame.hear: [2, 3, 3, 3, 4],
  MemoryGame.missing: [3, 3, 4, 4, 4],
  MemoryGame.say: [2, 2, 3, 3, 3],
};

/// The same for a child who already had three stars: a picture more.
const memorySizesHarder = <MemoryGame, List<int>>{
  MemoryGame.look: [3, 3, 4, 4, 4],
  MemoryGame.hear: [3, 3, 4, 4, 4],
  MemoryGame.missing: [4, 4, 5, 5, 5],
  MemoryGame.say: [2, 3, 3, 4, 4],
};

/// The picture counts of a round of [game].
List<int> memoryRoundSizes(MemoryGame game, {bool harder = false}) =>
    (harder ? memorySizesHarder : memorySizes)[game]!;

/// Pictures to choose from: six to find the remembered ones among, three
/// for the missing one. "What did you see?": the words the recogniser
/// tells apart (not shown: a word that was not there is one of these).
int memoryOptions(MemoryGame game) => game == MemoryGame.missing ? 3 : 6;

/// Pictures that are easy to mix up after a few seconds: at most one of
/// each family in a question. The number pictures (1️⃣ .. 🔟) are all the
/// same blue square.
const lookAlike = [
  ['👵', '👴', '🧓'],
  ['🚗', '🚕', '🚙', '🚓'],
  ['🐦', '🐤', '🐥', '🐔', '🐣'],
  ['🌹', '🌷', '🌸', '🌺'],
  ['🍎', '🍅', '🍒', '🍓'],
  ['🐶', '🐕'],
  ['🐱', '🐈'],
];

/// The family of [emoji] for [lookAlike], or null.
String? lookAlikeFamily(String emoji) {
  final bare = bareEmoji(emoji);
  if (bare.contains('⃣') || bare == '🔟') return 'number';
  for (final (i, f) in lookAlike.indexed) {
    if (f.map(bareEmoji).contains(bare)) return 'family$i';
  }
  return null;
}

/// A round of [game] from [pool]: no picture twice in a question, none
/// of the previous question (it would be remembered from there), no two
/// look-alikes, and no two that [similar] says sound alike (for "Remember
/// the words"), as far as the pool allows.
List<MemoryQuestion> makeMemoryRound(
  MemoryGame game,
  List<Phrase> pool,
  math.Random rng, {
  bool Function(Phrase a, Phrase b)? similar,
  bool Function(List<Phrase> shown, List<Phrase> options)? fair,
  bool harder = false,
}) {
  // one phrase per picture: two with the same picture cannot be told apart
  final seen = <String>{};
  final pics = [
    for (final p in pool)
      if (p.emoji.isNotEmpty && seen.add(bareEmoji(p.emoji))) p,
  ];

  /// [need] pictures from [from] (shuffled) that go together, or null.
  List<Phrase>? pick(List<Phrase> from, int need, {required bool strict}) {
    final out = <Phrase>[];
    final families = <String>{};
    for (final p in from) {
      final family = lookAlikeFamily(p.emoji);
      if (strict && family != null && families.contains(family)) continue;
      if (strict && similar != null && out.any((o) => similar(o, p))) {
        continue;
      }
      out.add(p);
      if (family != null) families.add(family);
      if (out.length == need) return out;
    }
    return null;
  }

  final out = <MemoryQuestion>[];
  var last = <Phrase>{};
  for (final n in memoryRoundSizes(game, harder: harder)) {
    final extra = memoryOptions(game) - (game == MemoryGame.missing ? 1 : n);
    final need = n + extra;
    if (pics.length < need) break;
    final fresh = [...pics.where((p) => !last.contains(p))]..shuffle(rng);
    final all = [...pics]..shuffle(rng);
    // [fair]: a few more tries (the words must be told apart), then any
    List<Phrase>? fairPick(List<Phrase> from) {
      for (var tries = 0; tries < 20; tries++) {
        final c = pick(from, need, strict: true);
        if (c == null) return null;
        if (fair == null || fair(c.sublist(0, n), c)) return c;
        from.shuffle(rng);
      }
      return null;
    }

    final chosen =
        fairPick(fresh) ??
        fairPick(all) ??
        pick(fresh, need, strict: false) ??
        pick(all, need, strict: false)!;
    final shown = chosen.sublist(0, n);
    final others = chosen.sublist(n, need);
    final MemoryQuestion q;
    if (game == MemoryGame.missing) {
      final missing = shown[rng.nextInt(n)];
      q = MemoryQuestion(
        shown,
        [missing, ...others]..shuffle(rng),
        missing: missing,
      );
    } else {
      q = MemoryQuestion(shown, [...shown, ...others]..shuffle(rng));
    }
    out.add(q);
    last = {...q.shown, ...q.options};
  }
  return out;
}

/// What the phone says in a memory game, in the study language.
class MemoryLines {
  const MemoryLines._(this._t);

  factory MemoryLines.of(String lang) =>
      MemoryLines._(_lines[lang.split('-').first] ?? _lines['en']!);

  final List<String> _t;

  /// Before the pictures (not before the first: the intro said it).
  String get look => _t[0];

  /// Before the words.
  String get listen => _t[1];

  /// The pictures are back: which were they?
  String get whichSeen => _t[2];

  /// The pictures are there: which words were said?
  String get whichHeard => _t[3];

  /// Which one is gone?
  String get whichMissing => _t[4];

  /// What did you see? Say it!
  String get whichSay => _t[5];

  /// One named, more to name.
  String get more => _t[6];

  /// A word of a picture that was not there.
  String get notThere => _t[7];

  /// Before a harder round (three stars before): more pictures now.
  String get harder => _t[8];
}

const _lines = <String, List<String>>{
  'de': [
    'Schau genau!',
    'Hör genau zu!',
    'Welche Bilder waren es?',
    'Welche Wörter hast du gehört?',
    'Welches Bild fehlt?',
    'Was hast du gesehen? Sag mir ein Bild!',
    'Und was noch?',
    'Das war nicht dabei.',
    'Das machst du schon richtig gut! Jetzt kommen noch mehr dazu.',
  ],
  'en': [
    'Look closely!',
    'Listen closely!',
    'Which pictures were there?',
    'Which words did you hear?',
    'Which picture is missing?',
    'What did you see? Tell me one picture!',
    'And what else?',
    'That wasn’t there.',
    'You’re really good at this! Now there are more.',
  ],
  'fr': [
    'Regarde bien !',
    'Écoute bien !',
    'Quelles images étaient là ?',
    'Quels mots as-tu entendus ?',
    'Quelle image manque ?',
    'Qu’est-ce que tu as vu ? Dis-moi une image !',
    'Et quoi d’autre ?',
    'Ça, ce n’était pas là !',
    'Tu y arrives très bien ! Maintenant, il y a encore plus d’images.',
  ],
  'it': [
    'Guarda bene!',
    'Ascolta bene!',
    'Quali immagini c’erano?',
    'Quali parole hai sentito?',
    'Quale immagine manca?',
    'Cosa hai visto? Dimmi un’immagine!',
    'E cos’altro?',
    'Non c’era.',
    'Ci riesci benissimo! Adesso sono di più.',
  ],
  'es': [
    '¡Mira bien!',
    '¡Escucha bien!',
    '¿Qué imágenes había?',
    '¿Qué palabras has oído?',
    '¿Qué imagen falta?',
    '¿Qué has visto? ¡Dime una imagen!',
    '¿Y qué más?',
    'Eso no estaba ahí.',
    '¡Lo haces muy bien! Ahora hay más.',
  ],
};
