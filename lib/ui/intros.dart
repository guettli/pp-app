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

  /// The worlds: hear a word, say it after the phone.
  repeat,

  /// Odd one out: tap the picture that does not belong.
  odd,

  /// Who lives here: a place, tap the animal that lives there.
  home,

  /// Remember the pictures: look, they hide, tap them again.
  memoryLook,

  /// Remember the words: listen, then tap their pictures.
  memoryHear,

  /// What's missing: look, one hides, tap the one that is gone.
  memoryMissing,

  /// Feeling faces: hear a feeling, tap its face.
  faces,

  /// How do I feel: hear a story, tap the face.
  feelings,
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
    GameIntro.odd:
        'Drei Bilder gehören zusammen. Tippe auf das Bild, das nicht dazu passt!',
    GameIntro.home: 'Schau, wo wir sind! Tippe auf das Tier, das hier wohnt!',
    GameIntro.repeat: 'Hör gut zu und sprich mir nach!',
    GameIntro.memoryLook:
        'Schau dir die Bilder gut an und merk sie dir! Dann verstecke ich sie, und du findest sie wieder.',
    GameIntro.memoryHear:
        'Hör gut zu und merk dir die Wörter! Dann tippst du auf die passenden Bilder.',
    GameIntro.memoryMissing:
        'Schau dir die Bilder gut an! Dann verstecke ich alle und nehme eins weg. Tippe auf das Bild, das fehlt!',
    GameIntro.faces:
        'Hör gut zu! Ich sage ein Gefühl. Tippe auf das passende Gesicht!',
    GameIntro.feelings:
        'Hör gut zu! Wie fühle ich mich? Tippe auf das richtige Gesicht!',
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
    GameIntro.odd:
        'Three pictures belong together. Tap the one that doesn’t belong!',
    GameIntro.home: 'Look where we are! Tap the animal that lives here!',
    GameIntro.repeat: 'Listen and say it after me!',
    GameIntro.memoryLook:
        'Look closely and remember the pictures! Then I’ll hide them, and you find them again.',
    GameIntro.memoryHear:
        'Listen closely and remember the words! Then tap the matching pictures.',
    GameIntro.memoryMissing:
        'Look closely at the pictures! Then I’ll hide them all and take one away. Tap the picture that is missing!',
    GameIntro.faces: 'Listen! I say a feeling. Tap the face that shows it!',
    GameIntro.feelings: 'Listen! How do I feel? Tap the right face!',
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
    GameIntro.odd:
        'Trois images vont ensemble. Touche celle qui n’est pas comme les autres !',
    GameIntro.home: 'Regarde où nous sommes ! Touche l’animal qui vit ici !',
    GameIntro.repeat: 'Écoute bien et répète après moi !',
    GameIntro.memoryLook:
        'Regarde bien les images et retiens-les ! Ensuite je les cache, et tu les retrouves.',
    GameIntro.memoryHear:
        'Écoute bien et retiens les mots ! Ensuite, touche les bonnes images.',
    GameIntro.memoryMissing:
        'Regarde bien les images ! Ensuite je les cache toutes et j’en enlève une. Touche l’image qui manque !',
    GameIntro.faces:
        'Écoute bien ! Je dis une émotion. Touche le visage qui la montre !',
    GameIntro.feelings:
        'Écoute bien ! Qu’est-ce que je ressens ? Touche le bon visage !',
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
    GameIntro.odd: 'Tre immagini vanno insieme. Tocca quella che non c’entra!',
    GameIntro.home: 'Guarda dove siamo! Tocca l’animale che vive qui!',
    GameIntro.repeat: 'Ascolta bene e ripeti dopo di me!',
    GameIntro.memoryLook:
        'Guarda bene le immagini e ricordale! Poi le nascondo e tu le ritrovi.',
    GameIntro.memoryHear:
        'Ascolta bene e ricorda le parole! Poi tocca le immagini giuste.',
    GameIntro.memoryMissing:
        'Guarda bene le immagini! Poi le nascondo tutte e ne tolgo una. Tocca l’immagine che manca!',
    GameIntro.faces:
        'Ascolta bene! Dico un’emozione. Tocca la faccia che la mostra!',
    GameIntro.feelings: 'Ascolta bene! Cosa provo? Tocca la faccia giusta!',
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
    GameIntro.odd:
        'Tres imágenes van juntas. ¡Toca la que no va con las demás!',
    GameIntro.home: '¡Mira dónde estamos! ¡Toca el animal que vive aquí!',
    GameIntro.repeat: '¡Escucha bien y repite después de mí!',
    GameIntro.memoryLook:
        '¡Mira bien las imágenes y recuérdalas! Luego las escondo y tú las encuentras.',
    GameIntro.memoryHear:
        '¡Escucha bien y recuerda las palabras! Luego toca las imágenes correctas.',
    GameIntro.memoryMissing:
        '¡Mira bien las imágenes! Luego las escondo todas y quito una. ¡Toca la imagen que falta!',
    GameIntro.faces:
        '¡Escucha bien! Digo una emoción. ¡Toca la cara que la muestra!',
    GameIntro.feelings: '¡Escucha bien! ¿Qué siento? ¡Toca la cara correcta!',
  },
};
