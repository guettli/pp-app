import 'package:flutter/widgets.dart';

/// Minimal UI texts. Kids mostly navigate by pictures; texts are for parents.
class S {
  const S(this._t);

  final Map<String, String> _t;

  static S of(BuildContext context) {
    final code = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    return S(_all[code] ?? _all['en']!);
  }

  String get title => 'Phoneme Party';
  String get chooseLanguage => _t['chooseLanguage']!;
  String get world => _t['world']!;
  String get listen => _t['listen']!;
  String get speak => _t['speak']!;
  String get next => _t['next']!;
  String get needMic => _t['needMic']!;
  String get tryAgain => _t['tryAgain']!;
  String get worldDone => _t['worldDone']!;
  String get ok => _t['ok']!;
  String get loading => _t['loading']!;
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
      'worldDone': 'Geschafft!',
      'newStars': '{n} neue Sterne gesammelt.',
      'ok': 'Super',
      'loading': 'Lade Spracherkennung …',
    },
    'en': {
      'chooseLanguage': 'Which language do you practise?',
      'world': 'World',
      'listen': 'Listen',
      'speak': 'Speak',
      'next': 'Next',
      'needMic': 'Please allow the microphone.',
      'tryAgain': 'That did not work. Please try again.',
      'worldDone': 'Well done!',
      'newStars': '{n} new stars collected.',
      'ok': 'Great',
      'loading': 'Loading speech recognition …',
    },
    'fr': {
      'chooseLanguage': 'Quelle langue pratiques-tu ?',
      'world': 'Monde',
      'listen': 'Écouter',
      'speak': 'Parler',
      'next': 'Suivant',
      'needMic': 'Autorise le microphone, s’il te plaît.',
      'tryAgain': 'Ça n’a pas marché. Essaie encore.',
      'worldDone': 'Bravo !',
      'newStars': '{n} nouvelles étoiles.',
      'ok': 'Super',
      'loading': 'Chargement de la reconnaissance vocale …',
    },
    'it': {
      'chooseLanguage': 'Quale lingua pratichi?',
      'world': 'Mondo',
      'listen': 'Ascolta',
      'speak': 'Parla',
      'next': 'Avanti',
      'needMic': 'Per favore consenti il microfono.',
      'tryAgain': 'Non ha funzionato. Riprova.',
      'worldDone': 'Bravo!',
      'newStars': '{n} nuove stelle raccolte.',
      'ok': 'Evviva',
      'loading': 'Caricamento del riconoscimento vocale …',
    },
    'es': {
      'chooseLanguage': '¿Qué idioma practicas?',
      'world': 'Mundo',
      'listen': 'Escuchar',
      'speak': 'Hablar',
      'next': 'Siguiente',
      'needMic': 'Por favor, permite el micrófono.',
      'tryAgain': 'No ha funcionado. Inténtalo otra vez.',
      'worldDone': '¡Muy bien!',
      'newStars': '{n} estrellas nuevas.',
      'ok': 'Genial',
      'loading': 'Cargando el reconocimiento de voz …',
    },
  };
}
