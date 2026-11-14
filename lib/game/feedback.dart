// Varied feedback after each word: a short melody (synthesised here, no
// sound files) and a spoken word of praise in the language being learned.
// Both are picked at random so that the game does not sound the same every
// time; the same praise never comes twice in a row.
import 'dart:math' as math;
import 'dart:typed_data';

/// Spoken praise per language, by stars (index 0..3). 0 stars means the
/// child is asked to try again, kindly.
const praise = <String, List<List<String>>>{
  'de': [
    ['Noch mal!', 'Versuch es noch einmal!', 'Hör gut zu!', 'Gleich noch mal!'],
    ['Gut!', 'Fast geschafft!', 'Weiter so!', 'Nicht schlecht!'],
    ['Sehr gut!', 'Gut gemacht!', 'Schön!', 'Prima!', 'Klasse!'],
    [
      'Super!',
      'Toll!',
      'Wunderbar!',
      'Spitze!',
      'Fantastisch!',
      'Wow!',
      'Perfekt!',
    ],
  ],
  'en': [
    ['Once more!', 'Try again!', 'Listen carefully!', 'Have another go!'],
    ['Good!', 'Almost!', 'Keep going!', 'Not bad!'],
    ['Very good!', 'Well done!', 'Nice!', 'Great!', 'Lovely!'],
    [
      'Super!',
      'Brilliant!',
      'Wonderful!',
      'Fantastic!',
      'Wow!',
      'Perfect!',
      'Amazing!',
    ],
  ],
  'fr': [
    [
      'Encore une fois !',
      'Essaie encore !',
      'Écoute bien !',
      'On recommence !',
    ],
    ['Bien !', 'Presque !', 'Continue !', 'Pas mal !'],
    ['Très bien !', 'Bravo !', 'Bien dit !', 'Chouette !', 'Bien joué !'],
    [
      'Super !',
      'Génial !',
      'Magnifique !',
      'Formidable !',
      'Waouh !',
      'Parfait !',
    ],
  ],
  'it': [
    ['Ancora una volta!', 'Riprova!', 'Ascolta bene!', 'Ancora!'],
    ['Bene!', 'Quasi!', 'Continua così!', 'Non male!'],
    ['Molto bene!', 'Ottimo lavoro!', 'Che bello!', 'Ottimo!', 'Ben fatto!'],
    [
      'Super!',
      'Fantastico!',
      'Meraviglioso!',
      'Perfetto!',
      'Wow!',
      'Eccellente!',
    ],
  ],
  'es': [
    [
      '¡Vamos otra vez!',
      '¡Inténtalo de nuevo!',
      '¡Escucha bien!',
      '¡Una vez más!',
    ],
    ['¡Bien!', '¡Casi!', '¡Sigue así!', '¡No está mal!'],
    ['¡Muy bien!', '¡Bien hecho!', '¡Qué bien!', '¡Estupendo!', '¡Bravo!'],
    [
      '¡Súper!',
      '¡Genial!',
      '¡Maravilloso!',
      '¡Fantástico!',
      '¡Hala!',
      '¡Perfecto!',
    ],
  ],
};

/// Said after 0 stars when there is no further try: kind, and on we go.
const movingOn = <String, List<String>>{
  'de': ['Weiter geht\'s!', 'Komm, das nächste!', 'Auf zum nächsten!'],
  'en': ['Let\'s try the next one!', 'On we go!', 'Next one!'],
  'fr': ['On continue !', 'Allez, le suivant !', 'On passe au suivant !'],
  'it': ['Andiamo avanti!', 'Proviamo il prossimo!', 'Avanti!'],
  'es': ['¡Sigamos!', '¡Vamos con el siguiente!', '¡Adelante!'],
};

/// A random praise for [stars] in [lang] (e.g. "de-DE"), never [avoid].
/// With [onward] (0 stars and no try left) a "let's go on" instead of
/// "try again".
String pickPraise(
  String lang,
  int stars,
  math.Random rng, {
  String? avoid,
  bool onward = false,
}) {
  final base = lang.split('-').first;
  final code = praise.containsKey(base) ? base : 'en';
  final list = stars <= 0 && onward
      ? movingOn[code]!
      : praise[code]![stars.clamp(0, 3)];
  final choices = list.where((p) => p != avoid).toList();
  return choices[rng.nextInt(choices.length)];
}

/// What happens after a scored word.
enum AfterResult { next, retry }

/// After 0 stars the child gets one more try at the same word; otherwise
/// (or after [attempts] tries) the game moves on by itself, so nobody gets
/// stuck on a word the recognition does not like.
AfterResult afterResult(int stars, int attempts) =>
    stars == 0 && attempts < 2 ? AfterResult.retry : AfterResult.next;

const _rate = 16000;

/// Major pentatonic steps (semitones) – every combination sounds friendly.
const _pentatonic = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24];

/// Melodies as indices into [_pentatonic], by stars. One is picked at random
/// and transposed, so the same result rarely sounds the same.
const _melodies = <List<List<int>>>[
  [
    [4, 2],
    [3, 1],
    [2, 0, 1],
  ], // 0 stars: soft, going down ("oh-oh"), not a buzzer
  [
    [2, 4],
    [0, 3],
    [1, 2],
  ],
  [
    [0, 2, 4],
    [0, 3, 5],
    [2, 1, 4],
    [0, 4, 3],
  ],
  [
    [0, 2, 4, 5, 7],
    [0, 3, 5, 7],
    [5, 4, 5, 7, 9],
    [0, 2, 3, 5, 6, 7],
  ],
];

/// A short melody for [stars] (mono, 16 kHz, peak 0.5).
Float32List jingle(int stars, math.Random rng) {
  final options = _melodies[stars.clamp(0, 3)];
  final melody = options[rng.nextInt(options.length)];
  final root = 60 + [0, 2, 5, 7][rng.nextInt(4)]; // C, D, F or G
  final noteMs = stars == 0 ? 220 : 120;
  return _render([
    for (var i = 0; i < melody.length; i++)
      (
        midi: root + _pentatonic[melody[i]],
        startMs: i * noteMs,
        // the last note rings longer
        lengthMs: i == melody.length - 1 ? 450 : noteMs + 80,
      ),
  ], bright: stars > 0);
}

/// One high "pling" for a picture landing in its slot.
Float32List pling(math.Random rng) => _render([
  (midi: 72 + _pentatonic[5 + rng.nextInt(5)], startMs: 0, lengthMs: 300),
], bright: true);

/// A longer fanfare for a finished world.
Float32List fanfare(math.Random rng) {
  final root = 60 + [0, 2, 5, 7][rng.nextInt(4)];
  const steps = [0, 2, 4, 5, 7, 5, 7, 10];
  return _render([
    for (var i = 0; i < steps.length; i++)
      (
        midi: root + _pentatonic[steps[i]],
        startMs: i * 110,
        lengthMs: i == steps.length - 1 ? 800 : 200,
      ),
  ], bright: true);
}

Float32List _render(
  List<({int midi, int startMs, int lengthMs})> notes, {
  required bool bright,
}) {
  final end = notes.map((n) => n.startMs + n.lengthMs).reduce(math.max);
  final out = Float32List(end * _rate ~/ 1000);
  for (final n in notes) {
    final hz = 440 * math.pow(2, (n.midi - 69) / 12);
    final start = n.startMs * _rate ~/ 1000;
    final len = n.lengthMs * _rate ~/ 1000;
    for (var i = 0; i < len && start + i < out.length; i++) {
      final t = i / _rate;
      // quick attack, bell-like decay
      // fade out over the last 8 ms, so a cut note does not click
      final fade = math.min(1.0, (len - i) / (_rate * 0.008));
      final env = math.min(1.0, i / (_rate * 0.005)) * math.exp(-5 * t) * fade;
      final w = 2 * math.pi * hz * t;
      var v = math.sin(w);
      if (bright) v += 0.3 * math.sin(2 * w) + 0.1 * math.sin(3 * w);
      out[start + i] += v * env;
    }
  }
  var peak = 0.0;
  for (final v in out) {
    peak = math.max(peak, v.abs());
  }
  if (peak > 0) {
    for (var i = 0; i < out.length; i++) {
      out[i] *= 0.5 / peak;
    }
  }
  return out;
}
