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

  /// What do I need: hear a problem, tap what helps.
  needs,

  /// Who am I: hear clues, tap the picture.
  riddle,
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
    GameIntro.needs: 'Hör gut zu und hilf mir! Tippe auf das, was ich brauche!',
    GameIntro.riddle:
        'Rate, wer ich bin! Hör auf die Tipps und tippe auf das richtige Bild. Die Lampe gibt dir noch einen Tipp.',
  },
  'en': {
    GameIntro.sayWord: 'Listen, then say the right word!',
    GameIntro.tapPicture: 'Listen, then tap the right picture!',
    GameIntro.readTapPicture: 'Read the word, then tap its picture!',
    GameIntro.tapLetters: 'Tap the letters in the right order!',
    GameIntro.readAloud: 'Read the word out loud!',
    GameIntro.needs: 'Listen and help me! Tap what I need!',
    GameIntro.riddle:
        'Guess who I am! Listen to the clues and tap the right picture. The lamp gives you another clue.',
  },
  'fr': {
    GameIntro.sayWord: 'Écoute bien, puis dis le bon mot !',
    GameIntro.tapPicture: 'Écoute bien, puis touche la bonne image !',
    GameIntro.readTapPicture: 'Lis le mot, puis touche son image !',
    GameIntro.tapLetters: 'Touche les lettres dans le bon ordre !',
    GameIntro.readAloud: 'Lis le mot à voix haute !',
    GameIntro.needs: 'Écoute bien et aide-moi ! Touche ce dont j’ai besoin !',
    GameIntro.riddle:
        'Devine qui je suis ! Écoute les indices et touche la bonne image. La lampe te donne un autre indice.',
  },
  'it': {
    GameIntro.sayWord: 'Ascolta bene, poi di’ la parola giusta!',
    GameIntro.tapPicture: 'Ascolta bene, poi tocca l’immagine giusta!',
    GameIntro.readTapPicture: 'Leggi la parola, poi tocca la sua immagine!',
    GameIntro.tapLetters: 'Tocca le lettere nell’ordine giusto!',
    GameIntro.readAloud: 'Leggi la parola ad alta voce!',
    GameIntro.needs: 'Ascolta bene e aiutami! Tocca quello che mi serve!',
    GameIntro.riddle:
        'Indovina chi sono! Ascolta gli indizi e tocca l’immagine giusta. La lampadina ti dà un altro indizio.',
  },
  'es': {
    GameIntro.sayWord: '¡Escucha bien y di la palabra correcta!',
    GameIntro.tapPicture: '¡Escucha bien y toca la imagen correcta!',
    GameIntro.readTapPicture: '¡Lee la palabra y toca su imagen!',
    GameIntro.tapLetters: '¡Toca las letras en el orden correcto!',
    GameIntro.readAloud: '¡Lee la palabra en voz alta!',
    GameIntro.needs: '¡Escucha bien y ayúdame! ¡Toca lo que necesito!',
    GameIntro.riddle:
        '¡Adivina quién soy! Escucha las pistas y toca la imagen correcta. La bombilla te da otra pista.',
  },
};
