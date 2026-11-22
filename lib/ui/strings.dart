import 'package:flutter/widgets.dart';

/// Minimal UI texts. Kids mostly navigate by pictures; texts are for parents.
class S {
  const S(this._t);

  final Map<String, String> _t;

  static S of(BuildContext context) {
    final code = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    return S(_all[code] ?? _all['en']!);
  }

  String get title => 'Der Hase lacht';
  String get chooseLanguage => _t['chooseLanguage']!;
  String get world => _t['world']!;
  String get listen => _t['listen']!;
  String get speak => _t['speak']!;
  String get next => _t['next']!;
  String get needMic => _t['needMic']!;
  String get tryAgain => _t['tryAgain']!;
  String get yourTurn => _t['yourTurn']!;
  String get notHeard => _t['notHeard']!;
  String get worldDone => _t['worldDone']!;
  String get ok => _t['ok']!;
  String get funnyVoice => _t['funnyVoice']!;
  String get loading => _t['loading']!;
  String get holdTitle => _t['holdTitle']!;
  String get pitchTitle => _t['pitchTitle']!;
  String get best => _t['best']!;
  String get notHeardVoice => _t['notHeardVoice']!;
  String get newRecord => _t['newRecord']!;
  String get quizTitle => _t['quizTitle']!;
  String get listenTitle => _t['listenTitle']!;
  String get spellTitle => _t['spellTitle']!;
  String get readPickTitle => _t['readPickTitle']!;
  String get readAloudTitle => _t['readAloudTitle']!;
  String get soundsTitle => _t['soundsTitle']!;
  String get needsTitle => _t['needsTitle']!;
  String get riddleTitle => _t['riddleTitle']!;
  String get hint => _t['hint']!;
  String get oddTitle => _t['oddTitle']!;
  String get homeTitle => _t['homeTitle']!;
  String get hearGroup => _t['hearGroup']!;
  String get readGroup => _t['readGroup']!;
  String get speakGroup => _t['speakGroup']!;
  String get thinkGroup => _t['thinkGroup']!;
  String get memoryGroup => _t['memoryGroup']!;
  String get feelGroup => _t['feelGroup']!;
  String get feelingsTitle => _t['feelingsTitle']!;
  String get facesTitle => _t['facesTitle']!;
  String get lookTitle => _t['lookTitle']!;
  String get hearWordsTitle => _t['hearWordsTitle']!;
  String get missingTitle => _t['missingTitle']!;
  String get sayWhatTitle => _t['sayWhatTitle']!;
  String get phoneTalks => _t['phoneTalks']!;
  String get phoneSilent => _t['phoneSilent']!;
  String get phoneListens => _t['phoneListens']!;
  String get phoneDeaf => _t['phoneDeaf']!;
  String get wordsTitle => _t['wordsTitle']!;
  String get feedbackTitle => _t['feedbackTitle']!;
  String get kindBug => _t['kindBug']!;
  String get kindIdea => _t['kindIdea']!;
  String get kindWord => _t['kindWord']!;
  String get kindOther => _t['kindOther']!;
  String get feedbackHint => _t['feedbackHint']!;
  String get feedbackSends => _t['feedbackSends']!;
  String get feedbackPublic => _t['feedbackPublic']!;
  String get send => _t['send']!;
  String get feedbackSent => _t['feedbackSent']!;
  String get feedbackQueued => _t['feedbackQueued']!;
  String get quizReports => _t['quizReports']!;
  String get quizReportsInfo => _t['quizReportsInfo']!;
  String get quizReportSend => _t['quizReportSend']!;
  String get quizReportAsk => _t['quizReportAsk']!;
  String get listenRecording => _t['listenRecording']!;
  String get cancel => _t['cancel']!;
  String get quizReportSent => _t['quizReportSent']!;
  String get quizReportFailed => _t['quizReportFailed']!;
  String parentGate(int a, int b) =>
      _t['parentGate']!.replaceAll('{a}', '$a').replaceAll('{b}', '$b');
  String newStars(int n) => _t['newStars']!.replaceAll('{n}', '$n');

  static const _all = {
    'de': {
      'chooseLanguage': 'Welche Sprache übst du?',
      'world': 'Welt',
      'listen': 'Anhören',
      'speak': 'Sprechen',
      'next': 'Weiter',
      'needMic': 'Bitte erlaube das Mikrofon.',
      'tryAgain': 'Das hat nicht geklappt. Versuch es noch einmal.',
      'yourTurn': 'Jetzt du!',
      'notHeard': 'Ich habe nichts gehört. Tippe auf 🎤 und sprich nach.',
      'worldDone': 'Geschafft!',
      'newStars': '{n} neue Sterne gesammelt.',
      'ok': 'Super',
      'funnyVoice': 'Lustige Stimme',
      'loading': 'Lade Spracherkennung …',
      'holdTitle': 'Lange Laute',
      'pitchTitle': 'Tief und hoch',
      'best': 'Rekord',
      'newRecord': 'Neuer Rekord!',
      'quizTitle': 'Rätsel',
      'listenTitle': 'Hör genau',
      'spellTitle': 'Buchstaben',
      'readPickTitle': 'Wort zum Bild',
      'readAloudTitle': 'Lies vor',
      'soundsTitle': 'Anlaut-Detektiv',
      'needsTitle': 'Was brauche ich?',
      'riddleTitle': 'Wer bin ich?',
      'hint': 'Noch ein Tipp',
      'oddTitle': 'Was passt nicht?',
      'homeTitle': 'Wer wohnt hier?',
      'hearGroup': 'Hören',
      'readGroup': 'Lesen',
      'speakGroup': 'Sprechen',
      'thinkGroup': 'Denken',
      'memoryGroup': 'Merken',
      'feelGroup': 'Gefühle',
      'feelingsTitle': 'Wie fühle ich mich?',
      'facesTitle': 'Gefühlsgesichter',
      'lookTitle': 'Bilder merken',
      'hearWordsTitle': 'Wörter merken',
      'missingTitle': 'Was fehlt?',
      'sayWhatTitle': 'Was hast du gesehen?',
      'phoneTalks': 'Das Handy spricht',
      'phoneSilent': 'Das Handy spricht nicht',
      'phoneListens': 'Das Handy hört zu',
      'phoneDeaf': 'Das Mikrofon bleibt aus',
      'wordsTitle': 'Wörter',
      'feedbackTitle': 'Feedback für Der Hase lacht',
      'parentGate': 'Für Erwachsene: Wie viel ist {a} × {b}?',
      'kindBug': 'Fehler',
      'kindIdea': 'Idee',
      'kindWord': 'Wort oder Bild',
      'kindOther': 'Sonstiges',
      'feedbackHint': 'Was ist passiert? Was wünschen Sie sich?',
      'feedbackSends': 'Wird mitgeschickt (keine Aufnahmen, keine Namen):',
      'feedbackPublic':
          'Geht nur an das Phoneme-Party-Team und wird nicht veröffentlicht.',
      'send': 'Senden',
      'feedbackSent': 'Danke! Gesendet.',
      'feedbackQueued': 'Danke! Wird gesendet, sobald Internet da ist.',
      'quizReports': 'Rätsel-Aufnahmen senden können',
      'quizReportsInfo':
          'Im Rätsel erscheint ein 🐞-Knopf. Ein Tipp darauf fragt nach (die Aufnahme lässt sich vorher anhören) und sendet dann die letzte Frage mit der Aufnahme des Kindes an den Entwickler, damit er die Spracherkennung verbessern kann. Gespeichert 90 Tage, nicht veröffentlicht.',
      'quizReportSend': 'Diese Frage an den Entwickler senden',
      'quizReportAsk': 'Diese Frage mit der Aufnahme an den Entwickler senden?',
      'listenRecording': 'Aufnahme anhören',
      'cancel': 'Abbrechen',
      'quizReportSent': 'Gesendet. Danke!',
      'quizReportFailed': 'Nicht gesendet. Ist Internet da?',
      'notHeardVoice':
          'Ich habe nichts gehört. Tippe auf 🎤 und versuch es noch einmal.',
    },
    'en': {
      'chooseLanguage': 'Which language do you practise?',
      'world': 'World',
      'listen': 'Listen',
      'speak': 'Speak',
      'next': 'Next',
      'needMic': 'Please allow the microphone.',
      'tryAgain': 'That did not work. Please try again.',
      'yourTurn': 'Your turn!',
      'notHeard': 'I did not hear anything. Tap 🎤 and say it after me.',
      'worldDone': 'Well done!',
      'newStars': '{n} new stars collected.',
      'ok': 'Great',
      'funnyVoice': 'Funny voice',
      'loading': 'Loading speech recognition …',
      'holdTitle': 'Long sounds',
      'pitchTitle': 'Low and high',
      'best': 'Best',
      'newRecord': 'New record!',
      'quizTitle': 'Quiz',
      'listenTitle': 'Listen',
      'spellTitle': 'Letters',
      'readPickTitle': 'Word to picture',
      'readAloudTitle': 'Read aloud',
      'soundsTitle': 'Sound detective',
      'needsTitle': 'What do I need?',
      'riddleTitle': 'Who am I?',
      'hint': 'Another clue',
      'oddTitle': 'Odd one out',
      'homeTitle': 'Who lives here?',
      'hearGroup': 'Listening',
      'readGroup': 'Reading',
      'speakGroup': 'Speaking',
      'thinkGroup': 'Thinking',
      'memoryGroup': 'Memory',
      'feelGroup': 'Feelings',
      'feelingsTitle': 'How do I feel?',
      'facesTitle': 'Feeling faces',
      'lookTitle': 'Remember the pictures',
      'hearWordsTitle': 'Remember the words',
      'missingTitle': 'What’s missing?',
      'sayWhatTitle': 'What did you see?',
      'phoneTalks': 'The phone talks',
      'phoneSilent': 'The phone stays quiet',
      'phoneListens': 'The phone listens',
      'phoneDeaf': 'The microphone stays off',
      'wordsTitle': 'Words',
      'feedbackTitle': 'Feedback for Der Hase lacht',
      'parentGate': 'For grown-ups: what is {a} × {b}?',
      'kindBug': 'Bug',
      'kindIdea': 'Idea',
      'kindWord': 'Word or picture',
      'kindOther': 'Other',
      'feedbackHint': 'What happened? What would you like?',
      'feedbackSends': 'Also sent (no recordings, no names):',
      'feedbackPublic':
          'Goes to the Der Hase lacht team only and is not published.',
      'send': 'Send',
      'feedbackSent': 'Thank you! Sent.',
      'feedbackQueued': 'Thank you! It will be sent when there is internet.',
      'quizReports': 'Allow sending quiz recordings',
      'quizReportsInfo':
          'A 🐞 button appears in the quiz. Tapping it asks first (the recording can be heard before) and then sends the last question with the child’s recording to the developer, to improve the speech recognition. Kept 90 days, not published.',
      'quizReportSend': 'Send this question to the developer',
      'quizReportAsk':
          'Send this question with the recording to the developer?',
      'listenRecording': 'Listen to the recording',
      'cancel': 'Cancel',
      'quizReportSent': 'Sent. Thank you!',
      'quizReportFailed': 'Not sent. Is there internet?',
      'notHeardVoice': 'I did not hear anything. Tap 🎤 and try again.',
    },
    'fr': {
      'chooseLanguage': 'Quelle langue pratiques-tu ?',
      'world': 'Monde',
      'listen': 'Écouter',
      'speak': 'Parler',
      'next': 'Suivant',
      'needMic': 'Autorise le microphone, s’il te plaît.',
      'tryAgain': 'Ça n’a pas marché. Essaie encore.',
      'yourTurn': 'À toi !',
      'notHeard': 'Je n’ai rien entendu. Touche 🎤 et répète.',
      'worldDone': 'Bravo !',
      'newStars': '{n} nouvelles étoiles.',
      'ok': 'Super',
      'funnyVoice': 'Voix rigolote',
      'loading': 'Chargement de la reconnaissance vocale …',
      'holdTitle': 'Sons longs',
      'pitchTitle': 'Grave et aigu',
      'best': 'Record',
      'newRecord': 'Nouveau record !',
      'quizTitle': 'Devinettes',
      'listenTitle': 'Écoute bien',
      'spellTitle': 'Lettres',
      'readPickTitle': 'Mot et image',
      'readAloudTitle': 'Lis à voix haute',
      'soundsTitle': 'Détective des sons',
      'needsTitle': 'De quoi ai-je besoin ?',
      'riddleTitle': 'Qui suis-je ?',
      'hint': 'Un autre indice',
      'oddTitle': 'L’intrus',
      'homeTitle': 'Qui vit ici ?',
      'hearGroup': 'Écouter',
      'readGroup': 'Lire',
      'speakGroup': 'Parler',
      'thinkGroup': 'Réfléchir',
      'memoryGroup': 'Mémoire',
      'feelGroup': 'Émotions',
      'feelingsTitle': 'Qu’est-ce que je ressens ?',
      'facesTitle': 'Les visages des émotions',
      'lookTitle': 'Retiens les images',
      'hearWordsTitle': 'Retiens les mots',
      'missingTitle': 'Qu’est-ce qui manque ?',
      'sayWhatTitle': 'Qu’as-tu vu ?',
      'phoneTalks': 'Le téléphone parle',
      'phoneSilent': 'Le téléphone ne parle pas',
      'phoneListens': 'Le téléphone écoute',
      'phoneDeaf': 'Le micro reste éteint',
      'wordsTitle': 'Mots',
      'feedbackTitle': 'Avis sur Der Hase lacht',
      'parentGate': 'Pour les adultes : combien font {a} × {b} ?',
      'kindBug': 'Bug',
      'kindIdea': 'Idée',
      'kindWord': 'Mot ou image',
      'kindOther': 'Autre',
      'feedbackHint': 'Que s’est-il passé ? Que souhaitez-vous ?',
      'feedbackSends': 'Envoyé aussi (aucun enregistrement, aucun nom) :',
      'feedbackPublic':
          'Envoyé uniquement à l’équipe Der Hase lacht, jamais publié.',
      'send': 'Envoyer',
      'feedbackSent': 'Merci ! Envoyé.',
      'feedbackQueued': 'Merci ! Ce sera envoyé dès qu’il y aura internet.',
      'quizReports': 'Permettre d’envoyer les enregistrements des devinettes',
      'quizReportsInfo':
          'Un bouton 🐞 apparaît dans les devinettes. Après confirmation (l’enregistrement peut être écouté avant), il envoie la dernière question avec l’enregistrement de l’enfant au développeur, pour améliorer la reconnaissance vocale. Gardé 90 jours, jamais publié.',
      'quizReportSend': 'Envoyer cette question au développeur',
      'quizReportAsk':
          'Envoyer cette question avec l’enregistrement au développeur\u00A0?',
      'listenRecording': 'Écouter l’enregistrement',
      'cancel': 'Annuler',
      'quizReportSent': 'Envoyé. Merci !',
      'quizReportFailed': 'Pas envoyé. Y a-t-il internet ?',
      'notHeardVoice': 'Je n’ai rien entendu. Touche 🎤 et réessaie.',
    },
    'it': {
      'chooseLanguage': 'Quale lingua pratichi?',
      'world': 'Mondo',
      'listen': 'Ascolta',
      'speak': 'Parla',
      'next': 'Avanti',
      'needMic': 'Per favore consenti il microfono.',
      'tryAgain': 'Non ha funzionato. Riprova.',
      'yourTurn': 'Tocca a te!',
      'notHeard': 'Non ho sentito niente. Tocca 🎤 e ripeti.',
      'worldDone': 'Bravo!',
      'newStars': '{n} nuove stelle raccolte.',
      'ok': 'Evviva',
      'funnyVoice': 'Voce buffa',
      'loading': 'Caricamento del riconoscimento vocale …',
      'holdTitle': 'Suoni lunghi',
      'pitchTitle': 'Basso e alto',
      'best': 'Record',
      'newRecord': 'Nuovo record!',
      'quizTitle': 'Indovinelli',
      'listenTitle': 'Ascolta bene',
      'spellTitle': 'Lettere',
      'readPickTitle': 'Parola e immagine',
      'readAloudTitle': 'Leggi ad alta voce',
      'soundsTitle': 'Detective dei suoni',
      'needsTitle': 'Cosa mi serve?',
      'riddleTitle': 'Chi sono?',
      'hint': 'Un altro indizio',
      'oddTitle': 'L’intruso',
      'homeTitle': 'Chi vive qui?',
      'hearGroup': 'Ascoltare',
      'readGroup': 'Leggere',
      'speakGroup': 'Parlare',
      'thinkGroup': 'Pensare',
      'memoryGroup': 'Memoria',
      'feelGroup': 'Emozioni',
      'feelingsTitle': 'Cosa provo?',
      'facesTitle': 'Le facce delle emozioni',
      'lookTitle': 'Ricorda le immagini',
      'hearWordsTitle': 'Ricorda le parole',
      'missingTitle': 'Cosa manca?',
      'sayWhatTitle': 'Cosa hai visto?',
      'phoneTalks': 'Il telefono parla',
      'phoneSilent': 'Il telefono non parla',
      'phoneListens': 'Il telefono ascolta',
      'phoneDeaf': 'Il microfono resta spento',
      'wordsTitle': 'Parole',
      'feedbackTitle': 'Commenti su Der Hase lacht',
      'parentGate': 'Per gli adulti: quanto fa {a} × {b}?',
      'kindBug': 'Errore',
      'kindIdea': 'Idea',
      'kindWord': 'Parola o immagine',
      'kindOther': 'Altro',
      'feedbackHint': 'Cosa è successo? Cosa desidera?',
      'feedbackSends': 'Inviato anche (nessuna registrazione, nessun nome):',
      'feedbackPublic':
          'Va solo al team di Der Hase lacht e non viene pubblicato.',
      'send': 'Invia',
      'feedbackSent': 'Grazie! Inviato.',
      'feedbackQueued': 'Grazie! Verrà inviato appena c’è internet.',
      'quizReports': 'Consenti l’invio delle registrazioni degli indovinelli',
      'quizReportsInfo':
          'Negli indovinelli compare un pulsante 🐞. Dopo una conferma (la registrazione si può ascoltare prima) invia l’ultima domanda con la registrazione del bambino allo sviluppatore, per migliorare il riconoscimento vocale. Conservata 90 giorni, mai pubblicata.',
      'quizReportSend': 'Invia questa domanda allo sviluppatore',
      'quizReportAsk':
          'Inviare questa domanda con la registrazione allo sviluppatore?',
      'listenRecording': 'Ascolta la registrazione',
      'cancel': 'Annulla',
      'quizReportSent': 'Inviato. Grazie!',
      'quizReportFailed': 'Non inviato. C’è internet?',
      'notHeardVoice': 'Non ho sentito niente. Tocca 🎤 e riprova.',
    },
    'es': {
      'chooseLanguage': '¿Qué idioma practicas?',
      'world': 'Mundo',
      'listen': 'Escuchar',
      'speak': 'Hablar',
      'next': 'Siguiente',
      'needMic': 'Por favor, permite el micrófono.',
      'tryAgain': 'No ha funcionado. Inténtalo otra vez.',
      'yourTurn': '¡Te toca!',
      'notHeard': 'No he oído nada. Toca 🎤 y repite.',
      'worldDone': '¡Muy bien!',
      'newStars': '{n} estrellas nuevas.',
      'ok': 'Genial',
      'funnyVoice': 'Voz graciosa',
      'loading': 'Cargando el reconocimiento de voz …',
      'holdTitle': 'Sonidos largos',
      'pitchTitle': 'Grave y agudo',
      'best': 'Récord',
      'newRecord': '¡Nuevo récord!',
      'quizTitle': 'Adivinanzas',
      'listenTitle': 'Escucha bien',
      'spellTitle': 'Letras',
      'readPickTitle': 'Palabra e imagen',
      'readAloudTitle': 'Lee en voz alta',
      'soundsTitle': 'Detective de sonidos',
      'needsTitle': '¿Qué necesito?',
      'riddleTitle': '¿Quién soy?',
      'hint': 'Otra pista',
      'oddTitle': '¿Cuál sobra?',
      'homeTitle': '¿Quién vive aquí?',
      'hearGroup': 'Escuchar',
      'readGroup': 'Leer',
      'speakGroup': 'Hablar',
      'thinkGroup': 'Pensar',
      'memoryGroup': 'Memoria',
      'feelGroup': 'Emociones',
      'feelingsTitle': '¿Qué siento?',
      'facesTitle': 'Caras de emociones',
      'lookTitle': 'Recuerda las imágenes',
      'hearWordsTitle': 'Recuerda las palabras',
      'missingTitle': '¿Qué falta?',
      'sayWhatTitle': '¿Qué has visto?',
      'phoneTalks': 'El teléfono habla',
      'phoneSilent': 'El teléfono no habla',
      'phoneListens': 'El teléfono escucha',
      'phoneDeaf': 'El micrófono permanece apagado',
      'wordsTitle': 'Palabras',
      'feedbackTitle': 'Comentarios sobre Der Hase lacht',
      'parentGate': 'Para adultos: ¿cuánto es {a} × {b}?',
      'kindBug': 'Error',
      'kindIdea': 'Idea',
      'kindWord': 'Palabra o imagen',
      'kindOther': 'Otro',
      'feedbackHint': '¿Qué ha pasado? ¿Qué le gustaría?',
      'feedbackSends': 'También se envía (sin grabaciones ni nombres):',
      'feedbackPublic':
          'Solo lo recibe el equipo de Der Hase lacht; no se publica.',
      'send': 'Enviar',
      'feedbackSent': '¡Gracias! Enviado.',
      'feedbackQueued': '¡Gracias! Se enviará cuando haya internet.',
      'quizReports': 'Permitir enviar grabaciones de las adivinanzas',
      'quizReportsInfo':
          'En las adivinanzas aparece un botón 🐞. Tras confirmar (la grabación se puede escuchar antes) envía la última pregunta con la grabación del niño al desarrollador, para mejorar el reconocimiento de voz. Se guarda 90 días, no se publica.',
      'quizReportSend': 'Enviar esta pregunta al desarrollador',
      'quizReportAsk':
          '¿Enviar esta pregunta con la grabación al desarrollador?',
      'listenRecording': 'Escuchar la grabación',
      'cancel': 'Cancelar',
      'quizReportSent': 'Enviado. ¡Gracias!',
      'quizReportFailed': 'No enviado. ¿Hay internet?',
      'notHeardVoice': 'No he oído nada. Toca 🎤 e inténtalo otra vez.',
    },
  };
}
