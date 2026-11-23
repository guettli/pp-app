import 'package:flutter/widgets.dart';

import '../rummy/rummy_rules.dart' show RummyNo;

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
  String get togetherGroup => _t['togetherGroup']!;
  String get togetherTitle => _t['togetherTitle']!;
  String get openMatch => _t['openMatch']!;
  String get joinMatch => _t['joinMatch']!;
  String get showCode => _t['showCode']!;
  String get wantsToPlay => _t['wantsToPlay']!;
  String get yes => _t['yes']!;
  String get no => _t['no']!;
  String get typeCode => _t['typeCode']!;
  String get codeWrong => _t['codeWrong']!;
  String get undo => _t['undo']!;
  String get youAre => _t['youAre']!;
  String get waitForYes => _t['waitForYes']!;
  String get connecting => _t['connecting']!;
  String get codeTaken => _t['codeTaken']!;
  String get friendGone => _t['friendGone']!;
  String get offline => _t['offline']!;
  String get linkFailed => _t['linkFailed']!;
  String get wave => _t['wave']!;
  String get rummy => _t['rummy']!;
  String get playHase => _t['playHase']!;
  String get openAt => _t['openAt']!;
  String get openNone => _t['openNone']!;
  String get rummyDraw => _t['rummyDraw']!;
  String get rummyPlay => _t['rummyPlay']!;
  String get waitPlease => _t['waitPlease']!;
  String get meldBtn => _t['meldBtn']!;
  String get openBtn => _t['openBtn']!;
  String get discardBtn => _t['discardBtn']!;
  String get putBack => _t['putBack']!;
  String get sortCards => _t['sortCards']!;
  String get youWon => _t['youWon']!;
  String get friendWon => _t['friendWon']!;
  String get noWinner => _t['noWinner']!;
  String get penaltyPoints => _t['penaltyPoints']!;
  String get nextRound => _t['nextRound']!;
  String get pickOne => _t['pickOne']!;
  String cardsLeft(int n) => _t['cardsLeft']!.replaceAll('{n}', '$n');
  String stagedPoints(int a, int b) =>
      _t['stagedPoints']!.replaceAll('{a}', '$a').replaceAll('{b}', '$b');
  String rummyPlayOpen(int n) => n == 0
      ? _t['rummyPlayFree']!
      : _t['rummyPlayOpen']!.replaceAll('{n}', '$n');

  /// Why the game refused a move ([open]: the points for laying out).
  String rummyNo(RummyNo no, int open) =>
      _t['no_${no == RummyNo.notOver ? RummyNo.notYourTurn.name : no.name}']!
          .replaceAll('{n}', '$open');
  String get codeExpired => _t['codeExpired']!;
  String get notAccepted => _t['notAccepted']!;
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
  String get thinkReportAsk => _t['thinkReportAsk']!;
  String get thinkReportNote => _t['thinkReportNote']!;
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
      'notAccepted': 'Diesmal hat es nicht geklappt. Versuch es nochmal!',
      'codeExpired': 'Die Bilder gelten nicht mehr. Mach ein neues Spiel auf!',
      'togetherGroup': 'Zusammen',
      'togetherTitle': 'Zusammen spielen',
      'openMatch': 'Spiel aufmachen',
      'joinMatch': 'Mitspielen',
      'showCode': 'Zeig diese Bilder dem anderen Kind!',
      'wantsToPlay': 'möchte mitspielen',
      'yes': 'Ja',
      'no': 'Nein',
      'typeCode': 'Tipp die Bilder vom anderen Handy!',
      'codeWrong': 'Die Bilder passen nicht. Versuch es nochmal!',
      'undo': 'Zurück',
      'youAre': 'Du bist',
      'waitForYes': 'Warte, bis das andere Kind Ja sagt.',
      'connecting': 'Ich verbinde euch …',
      'codeTaken': 'Da spielt schon jemand mit.',
      'friendGone': 'Das andere Kind ist nicht mehr da.',
      'offline': 'Keine Verbindung zum Internet.',
      'linkFailed': 'Die Handys finden sich nicht.',
      'wave': 'Winken',
      'rummy': 'Rommé',
      'playHase': 'Mit dem Hasen',
      'openAt': 'Rauslegen ab',
      'openNone': 'ohne',
      'rummyDraw': 'Zieh eine Karte: vom Stapel oder vom Ablagestapel.',
      'rummyPlay': 'Leg aus, leg an oder wirf eine Karte ab.',
      'rummyPlayFree': 'Leg Karten raus oder wirf eine ab.',
      'rummyPlayOpen': 'Leg Karten für {n} Punkte raus oder wirf eine ab.',
      'waitPlease': 'Warte …',
      'meldBtn': 'Auslegen',
      'openBtn': 'Rauslegen',
      'discardBtn': 'Abwerfen',
      'putBack': 'Zurücklegen',
      'sortCards': 'Sortieren',
      'youWon': 'Gewonnen!',
      'friendWon': 'hat gewonnen.',
      'noWinner': 'Die Karten sind alle.',
      'penaltyPoints': 'Minuspunkte',
      'nextRound': 'Noch eine Runde',
      'pickOne': 'Wähle eine Karte.',
      'cardsLeft': '{n} Karten',
      'stagedPoints': 'Zum Rauslegen: {a} von {b} Punkten',
      'no_notYourTurn': 'Du bist nicht dran.',
      'no_drawFirst': 'Zieh zuerst eine Karte.',
      'no_drewAlready': 'Du hast schon gezogen.',
      'no_notInHand': 'Diese Karte hast du nicht.',
      'no_notAMeld': 'Das ist kein Satz und keine Reihe.',
      'no_tooFewPoints': 'Zum Rauslegen brauchst du {n} Punkte.',
      'no_mustUsePile':
          'Die Karte vom Ablagestapel muss mit raus – oder leg sie zurück.',
      'no_openFirst': 'Leg zuerst raus.',
      'no_doesNotFit': 'Das passt hier nicht.',
      'no_keepThatCard': 'Diese Karte darfst du jetzt nicht abwerfen.',
      'no_pileEmpty': 'Vom Ablagestapel geht es gerade nicht.',
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
      'quizReports': 'Aufnahmen und Denkspiel-Fragen senden können',
      'quizReportsInfo':
          'In den Spielen, die zuhören (Welten, Rätsel, Anlaut-Detektiv, Lies vor, Lange Laute), erscheint ein 🐞-Knopf. Ein Tipp darauf fragt nach (die Aufnahme lässt sich vorher anhören) und sendet dann den letzten Versuch mit der Aufnahme des Kindes an den Entwickler, damit er die Spracherkennung verbessern kann. Gespeichert 90 Tage, nicht veröffentlicht. In den Denkspielen sendet 🐞 die Frage ohne Aufnahme als Rückmeldung (gelöscht nach 12 Monaten).',
      'quizReportSend': 'An den Entwickler senden',
      'quizReportAsk': 'Diese Aufnahme an den Entwickler senden?',
      'listenRecording': 'Aufnahme anhören',
      'thinkReportAsk': 'Diese Frage an den Entwickler senden?',
      'thinkReportNote': 'Was stimmt nicht? (freiwillig)',
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
      'notAccepted': 'It didn\'t work this time. Try again!',
      'codeExpired': 'These pictures are too old. Start a new game!',
      'togetherGroup': 'Together',
      'togetherTitle': 'Play together',
      'openMatch': 'Start a game',
      'joinMatch': 'Join',
      'showCode': 'Show these pictures to the other child!',
      'wantsToPlay': 'wants to play',
      'yes': 'Yes',
      'no': 'No',
      'typeCode': 'Tap the pictures from the other phone!',
      'codeWrong': 'Those pictures don\'t match. Try again!',
      'undo': 'Back',
      'youAre': 'You are',
      'waitForYes': 'Wait until the other child says yes.',
      'connecting': 'Connecting you…',
      'codeTaken': 'Someone is already playing.',
      'friendGone': 'The other child is not there any more.',
      'offline': 'No internet connection.',
      'linkFailed': 'The phones can\'t find each other.',
      'wave': 'Wave',
      'rummy': 'Rummy',
      'playHase': 'With the hare',
      'openAt': 'First meld from',
      'openNone': 'any',
      'rummyDraw': 'Draw a card: from the stock or the discard pile.',
      'rummyPlay': 'Meld, lay off or discard a card.',
      'rummyPlayFree': 'Lay out cards or discard one.',
      'rummyPlayOpen': 'Lay out cards worth {n} points or discard one.',
      'waitPlease': 'Wait …',
      'meldBtn': 'Meld',
      'openBtn': 'Lay out',
      'discardBtn': 'Discard',
      'putBack': 'Put back',
      'sortCards': 'Sort',
      'youWon': 'You won!',
      'friendWon': 'won.',
      'noWinner': 'The cards ran out.',
      'penaltyPoints': 'Penalty points',
      'nextRound': 'Another round',
      'pickOne': 'Pick one card.',
      'cardsLeft': '{n} cards',
      'stagedPoints': 'To lay out: {a} of {b} points',
      'no_notYourTurn': 'It is not your turn.',
      'no_drawFirst': 'Draw a card first.',
      'no_drewAlready': 'You drew already.',
      'no_notInHand': 'You do not have that card.',
      'no_notAMeld': 'That is not a set or a run.',
      'no_tooFewPoints': 'You need {n} points to lay out.',
      'no_mustUsePile':
          'The card from the discard pile must be laid out – or put it back.',
      'no_openFirst': 'Lay out first.',
      'no_doesNotFit': 'That does not fit here.',
      'no_keepThatCard': 'You may not discard that card now.',
      'no_pileEmpty': 'Not from the discard pile now.',
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
      'quizReports': 'Allow sending recordings and thinking-game questions',
      'quizReportsInfo':
          'A 🐞 button appears in the games that listen (worlds, quiz, sound detective, read aloud, long sounds). Tapping it asks first (the recording can be heard before) and then sends the last try with the child’s recording to the developer, to improve the speech recognition. Kept 90 days, not published. In the thinking games, 🐞 sends the question without a recording, as feedback (deleted after 12 months).',
      'quizReportSend': 'Send to the developer',
      'quizReportAsk': 'Send this recording to the developer?',
      'listenRecording': 'Listen to the recording',
      'thinkReportAsk': 'Send this question to the developer?',
      'thinkReportNote': 'What is wrong? (optional)',
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
      'notAccepted': 'Ça n’a pas marché cette fois. Essaie encore !',
      'codeExpired': 'Ces images ne valent plus. Ouvre une nouvelle partie !',
      'togetherGroup': 'Ensemble',
      'togetherTitle': 'Jouer ensemble',
      'openMatch': 'Ouvrir une partie',
      'joinMatch': 'Rejoindre',
      'showCode': 'Montre ces images à l’autre enfant !',
      'wantsToPlay': 'veut jouer',
      'yes': 'Oui',
      'no': 'Non',
      'typeCode': 'Touche les images de l’autre téléphone !',
      'codeWrong': 'Ces images ne vont pas. Essaie encore !',
      'undo': 'Retour',
      'youAre': 'Tu es',
      'waitForYes': 'Attends que l’autre enfant dise oui.',
      'connecting': 'Je vous connecte…',
      'codeTaken': 'Quelqu’un joue déjà.',
      'friendGone': 'L’autre enfant n’est plus là.',
      'offline': 'Pas de connexion Internet.',
      'linkFailed': 'Les téléphones ne se trouvent pas.',
      'wave': 'Saluer',
      'rummy': 'Rami',
      'playHase': 'Avec le lièvre',
      'openAt': 'Première pose dès',
      'openNone': 'libre',
      'rummyDraw': 'Pioche une carte : dans la pioche ou la défausse.',
      'rummyPlay': 'Pose, complète ou défausse une carte.',
      'rummyPlayFree': 'Pose des cartes ou défausse-en une.',
      'rummyPlayOpen': 'Pose des cartes pour {n} points ou défausse-en une.',
      'waitPlease': 'Attends …',
      'meldBtn': 'Poser',
      'openBtn': 'Ouvrir',
      'discardBtn': 'Défausser',
      'putBack': 'Reposer',
      'sortCards': 'Trier',
      'youWon': 'Gagné !',
      'friendWon': 'a gagné.',
      'noWinner': 'Plus de cartes.',
      'penaltyPoints': 'Points de pénalité',
      'nextRound': 'Encore une manche',
      'pickOne': 'Choisis une carte.',
      'cardsLeft': '{n} cartes',
      'stagedPoints': 'À poser : {a} sur {b} points',
      'no_notYourTurn': 'Ce n’est pas ton tour.',
      'no_drawFirst': 'Pioche d’abord une carte.',
      'no_drewAlready': 'Tu as déjà pioché.',
      'no_notInHand': 'Tu n’as pas cette carte.',
      'no_notAMeld': 'Ce n’est ni une série ni une suite.',
      'no_tooFewPoints': 'Il faut {n} points pour ouvrir.',
      'no_mustUsePile':
          'La carte de la défausse doit être posée – ou repose-la.',
      'no_openFirst': 'Ouvre d’abord.',
      'no_doesNotFit': 'Ça ne va pas ici.',
      'no_keepThatCard': 'Tu ne peux pas défausser cette carte maintenant.',
      'no_pileEmpty': 'Pas depuis la défausse maintenant.',
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
      'quizReports':
          'Permettre d’envoyer les enregistrements et les questions des jeux de réflexion',
      'quizReportsInfo':
          'Un bouton 🐞 apparaît dans les jeux qui écoutent (mondes, devinettes, détective des sons, lecture à voix haute, sons longs). Après confirmation (l’enregistrement peut être écouté avant), il envoie le dernier essai avec l’enregistrement de l’enfant au développeur, pour améliorer la reconnaissance vocale. Gardé 90 jours, jamais publié. Dans les jeux de réflexion, 🐞 envoie la question sans enregistrement, comme un retour (effacé après 12\u00A0mois).',
      'quizReportSend': 'Envoyer au développeur',
      'quizReportAsk': 'Envoyer cet enregistrement au développeur\u00A0?',
      'listenRecording': 'Écouter l’enregistrement',
      'thinkReportAsk': 'Envoyer cette question au développeur\u00A0?',
      'thinkReportNote': 'Qu’est-ce qui ne va pas\u00A0? (facultatif)',
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
      'notAccepted': 'Questa volta non ha funzionato. Riprova!',
      'codeExpired': 'Queste immagini non valgono più. Apri una nuova partita!',
      'togetherGroup': 'Insieme',
      'togetherTitle': 'Giocare insieme',
      'openMatch': 'Apri una partita',
      'joinMatch': 'Partecipa',
      'showCode': 'Mostra queste immagini a chi gioca con te!',
      'wantsToPlay': 'vuole giocare',
      'yes': 'Sì',
      'no': 'No',
      'typeCode': 'Tocca le immagini dell’altro telefono!',
      'codeWrong': 'Queste immagini non vanno. Riprova!',
      'undo': 'Indietro',
      'youAre': 'Tu sei',
      'waitForYes': 'Aspetta che dall’altra parte dicano sì.',
      'connecting': 'Vi collego…',
      'codeTaken': 'Qualcuno sta già giocando.',
      'friendGone': 'Chi giocava con te non c’è più.',
      'offline': 'Nessuna connessione a Internet.',
      'linkFailed': 'I telefoni non si trovano.',
      'wave': 'Saluta',
      'rummy': 'Ramino',
      'playHase': 'Con la lepre',
      'openAt': 'Prima calata da',
      'openNone': 'libera',
      'rummyDraw': 'Pesca una carta: dal mazzo o dagli scarti.',
      'rummyPlay': 'Cala, attacca o scarta una carta.',
      'rummyPlayFree': 'Cala delle carte o scartane una.',
      'rummyPlayOpen': 'Cala carte per {n} punti o scartane una.',
      'waitPlease': 'Aspetta …',
      'meldBtn': 'Cala',
      'openBtn': 'Apri',
      'discardBtn': 'Scarta',
      'putBack': 'Rimetti',
      'sortCards': 'Ordina',
      'youWon': 'Hai vinto!',
      'friendWon': 'ha vinto.',
      'noWinner': 'Le carte sono finite.',
      'penaltyPoints': 'Punti di penalità',
      'nextRound': 'Un’altra mano',
      'pickOne': 'Scegli una carta.',
      'cardsLeft': '{n} carte',
      'stagedPoints': 'Da calare: {a} di {b} punti',
      'no_notYourTurn': 'Non è il tuo turno.',
      'no_drawFirst': 'Prima pesca una carta.',
      'no_drewAlready': 'Hai già pescato.',
      'no_notInHand': 'Non hai questa carta.',
      'no_notAMeld': 'Non è né un tris né una scala.',
      'no_tooFewPoints': 'Servono {n} punti per aprire.',
      'no_mustUsePile': 'La carta degli scarti va calata – o rimettila.',
      'no_openFirst': 'Prima apri.',
      'no_doesNotFit': 'Qui non va.',
      'no_keepThatCard': 'Ora non puoi scartare questa carta.',
      'no_pileEmpty': 'Ora non dagli scarti.',
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
      'quizReports':
          'Consenti l’invio delle registrazioni e delle domande dei giochi di logica',
      'quizReportsInfo':
          'Nei giochi che ascoltano (mondi, indovinelli, detective dei suoni, lettura ad alta voce, suoni lunghi) compare un pulsante 🐞. Dopo una conferma (la registrazione si può ascoltare prima) invia l’ultimo tentativo con la registrazione del bambino allo sviluppatore, per migliorare il riconoscimento vocale. Conservata 90 giorni, mai pubblicata. Nei giochi di logica, 🐞 invia la domanda senza registrazione, come un commento (cancellato dopo 12 mesi).',
      'quizReportSend': 'Invia allo sviluppatore',
      'quizReportAsk': 'Inviare questa registrazione allo sviluppatore?',
      'listenRecording': 'Ascolta la registrazione',
      'thinkReportAsk': 'Inviare questa domanda allo sviluppatore?',
      'thinkReportNote': 'Che cosa non va? (facoltativo)',
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
      'notAccepted': 'Esta vez no ha funcionado. ¡Inténtalo otra vez!',
      'codeExpired': 'Estas imágenes ya no valen. ¡Abre una partida nueva!',
      'togetherGroup': 'Juntos',
      'togetherTitle': 'Jugar juntos',
      'openMatch': 'Abrir una partida',
      'joinMatch': 'Unirse',
      'showCode': '¡Enseña estas imágenes a quien juega contigo!',
      'wantsToPlay': 'quiere jugar',
      'yes': 'Sí',
      'no': 'No',
      'typeCode': '¡Toca las imágenes del otro teléfono!',
      'codeWrong': 'Esas imágenes no coinciden. ¡Inténtalo otra vez!',
      'undo': 'Atrás',
      'youAre': 'Eres',
      'waitForYes': 'Espera a que digan que sí al otro lado.',
      'connecting': 'Os estoy conectando…',
      'codeTaken': 'Ya hay alguien jugando.',
      'friendGone': 'Quien jugaba contigo ya no está.',
      'offline': 'No hay conexión a Internet.',
      'linkFailed': 'Los teléfonos no se encuentran.',
      'wave': 'Saludar',
      'rummy': 'Rummy',
      'playHase': 'Con la liebre',
      'openAt': 'Primera bajada desde',
      'openNone': 'libre',
      'rummyDraw': 'Roba una carta: del mazo o del descarte.',
      'rummyPlay': 'Baja, añade o descarta una carta.',
      'rummyPlayFree': 'Baja cartas o descarta una.',
      'rummyPlayOpen': 'Baja cartas por {n} puntos o descarta una.',
      'waitPlease': 'Espera …',
      'meldBtn': 'Bajar',
      'openBtn': 'Abrir',
      'discardBtn': 'Descartar',
      'putBack': 'Devolver',
      'sortCards': 'Ordenar',
      'youWon': '¡Has ganado!',
      'friendWon': 'ha ganado.',
      'noWinner': 'Se acabaron las cartas.',
      'penaltyPoints': 'Puntos de penalización',
      'nextRound': 'Otra ronda',
      'pickOne': 'Elige una carta.',
      'cardsLeft': '{n} cartas',
      'stagedPoints': 'Para abrir: {a} de {b} puntos',
      'no_notYourTurn': 'No es tu turno.',
      'no_drawFirst': 'Primero roba una carta.',
      'no_drewAlready': 'Ya has robado.',
      'no_notInHand': 'No tienes esa carta.',
      'no_notAMeld': 'No es ni un trío ni una escalera.',
      'no_tooFewPoints': 'Necesitas {n} puntos para abrir.',
      'no_mustUsePile': 'La carta del descarte debe bajarse, o devuélvela.',
      'no_openFirst': 'Primero abre.',
      'no_doesNotFit': 'Aquí no encaja.',
      'no_keepThatCard': 'Ahora no puedes descartar esta carta.',
      'no_pileEmpty': 'Ahora no del descarte.',
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
      'quizReports':
          'Permitir enviar grabaciones y preguntas de los juegos de pensar',
      'quizReportsInfo':
          'En los juegos que escuchan (mundos, adivinanzas, detective de sonidos, lectura en voz alta, sonidos largos) aparece un botón 🐞. Tras confirmar (la grabación se puede escuchar antes) envía el último intento con la grabación del niño al desarrollador, para mejorar el reconocimiento de voz. Se guarda 90 días, no se publica. En los juegos de pensar, 🐞 envía la pregunta sin grabación, como comentario (se borra a los 12 meses).',
      'quizReportSend': 'Enviar al desarrollador',
      'quizReportAsk': '¿Enviar esta grabación al desarrollador?',
      'listenRecording': 'Escuchar la grabación',
      'thinkReportAsk': '¿Enviar esta pregunta al desarrollador?',
      'thinkReportNote': '¿Qué está mal? (opcional)',
      'cancel': 'Cancelar',
      'quizReportSent': 'Enviado. ¡Gracias!',
      'quizReportFailed': 'No enviado. ¿Hay internet?',
      'notHeardVoice': 'No he oído nada. Toca 🎤 e inténtalo otra vez.',
    },
  };
}
