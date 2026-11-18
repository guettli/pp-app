// What to do, said once at the start of a round, in the study language:
// a child who cannot read the screen must know whether to tap or to
// speak.

/// The ways a game is played, each with its own short intro.
enum GameIntro {
  /// Quiz and sound detective: the child says the word.
  sayWord,

  /// Listen closely: hear, then tap a picture.
  tapPicture,

  /// Word to picture: read, then tap a picture.
  readTapPicture,

  /// Letters: tap the letter tiles in order.
  tapLetters,

  /// Read aloud.
  readAloud,
}

/// The intro of [game] in [lang] (e.g. "de-DE"); English if unknown.
String introLine(GameIntro game, String lang) {
  final code = lang.split('-').first;
  return (_lines[code] ?? _lines['en']!)[game]!;
}

const _lines = <String, Map<GameIntro, String>>{
  'de': {
    GameIntro.sayWord: 'Hör gut zu und sag das richtige Wort!',
    GameIntro.tapPicture: 'Hör gut zu und tippe auf das richtige Bild!',
    GameIntro.readTapPicture: 'Lies das Wort und tippe auf das passende Bild!',
    GameIntro.tapLetters: 'Tippe die Buchstaben der Reihe nach an!',
    GameIntro.readAloud: 'Lies das Wort laut vor!',
  },
  'en': {
    GameIntro.sayWord: 'Listen, then say the right word!',
    GameIntro.tapPicture: 'Listen, then tap the right picture!',
    GameIntro.readTapPicture: 'Read the word, then tap its picture!',
    GameIntro.tapLetters: 'Tap the letters in the right order!',
    GameIntro.readAloud: 'Read the word out loud!',
  },
  'fr': {
    GameIntro.sayWord: 'Écoute bien, puis dis le bon mot !',
    GameIntro.tapPicture: 'Écoute bien, puis touche la bonne image !',
    GameIntro.readTapPicture: 'Lis le mot, puis touche son image !',
    GameIntro.tapLetters: 'Touche les lettres dans le bon ordre !',
    GameIntro.readAloud: 'Lis le mot à voix haute !',
  },
  'it': {
    GameIntro.sayWord: 'Ascolta bene, poi di’ la parola giusta!',
    GameIntro.tapPicture: 'Ascolta bene, poi tocca l’immagine giusta!',
    GameIntro.readTapPicture: 'Leggi la parola, poi tocca la sua immagine!',
    GameIntro.tapLetters: 'Tocca le lettere nell’ordine giusto!',
    GameIntro.readAloud: 'Leggi la parola ad alta voce!',
  },
  'es': {
    GameIntro.sayWord: '¡Escucha bien y di la palabra correcta!',
    GameIntro.tapPicture: '¡Escucha bien y toca la imagen correcta!',
    GameIntro.readTapPicture: '¡Lee la palabra y toca su imagen!',
    GameIntro.tapLetters: '¡Toca las letras en el orden correcto!',
    GameIntro.readAloud: '¡Lee la palabra en voz alta!',
  },
};
