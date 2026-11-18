// What the phone says in the quiz, and the property names in the word
// list, in the language the child practises (like voice/voice_lines.dart).
import 'facts.dart';

class QuizLines {
  const QuizLines._(this._t, this.code);

  /// For a study language like "de-DE"; English if unknown.
  factory QuizLines.of(String lang) {
    final code = lang.split('-').first;
    return _lines.containsKey(code)
        ? QuizLines._(_lines[code]!, code)
        : QuizLines._(_lines['en']!, 'en');
  }

  final Map<String, String> _t;
  final String code;

  /// "What can fly?", "What starts like Maus?"
  String question(Ask ask) {
    final like = ask.like;
    if (like != null) return _t['startsLike']!.replaceAll('{w}', like.text);
    return _t[ask.toString()]!;
  }

  /// "What can fly? Tree, bird or house?"
  String ask(QuizQuestion q) {
    final w = [for (final o in q.options) o.text];
    final last = w.last;
    final or =
        code == 'es' && RegExp(r'^h?[oó]', caseSensitive: false).hasMatch(last)
        ? 'u' // "o oso" -> "u oso"
        : _t['or']!;
    final list = '${w.sublist(0, w.length - 1).join(', ')} $or $last';
    return code == 'es'
        ? '${question(q.ask)} ¿$list?'
        : '${question(q.ask)} $list?';
  }

  String answerIs(String word) => _t['answerIs']!.replaceAll('{w}', word);
  String get notUnderstood => _t['notUnderstood']!;

  /// Short name of [p] for the word list ("flies").
  String label(Prop p) => _t['label.${p.name}']!;

  static const _lines = <String, Map<String, String>>{
    'de': {
      'animal': 'Was ist ein Tier?',
      'flies': 'Was kann fliegen?',
      'swims': 'Wer kann schwimmen?',
      'walks': 'Wer kann laufen?',
      'talks': 'Was kann sprechen?',
      'eat': 'Was kann man essen?',
      'drink': 'Was kann man trinken?',
      'wear': 'Was kann man anziehen oder aufsetzen?',
      'plant': 'Was ist eine Pflanze?',
      'wheels': 'Was hat Räder?',
      'music': 'Womit kann man Musik machen?',
      'shines': 'Was leuchtet?',
      'cold': 'Was ist kalt?',
      'body': 'Was gehört zu deinem Körper?',
      'number': 'Was ist eine Zahl?',
      'biggest': 'Was ist am größten?',
      'smallest': 'Was ist am kleinsten?',
      'heaviest': 'Was ist am schwersten?',
      'lightest': 'Was ist am leichtesten?',
      'or': 'oder',
      'answerIs': 'Die Antwort ist: {w}.',
      'startsLike': 'Was fängt an wie {w}?',
      'notUnderstood': 'Das habe ich nicht verstanden. Noch einmal!',
      'label.animal': 'Tier',
      'label.flies': 'fliegt',
      'label.swims': 'schwimmt',
      'label.walks': 'läuft',
      'label.talks': 'spricht',
      'label.eat': 'zum Essen',
      'label.drink': 'zum Trinken',
      'label.wear': 'zum Anziehen',
      'label.plant': 'Pflanze',
      'label.wheels': 'hat Räder',
      'label.music': 'macht Musik',
      'label.shines': 'leuchtet',
      'label.cold': 'kalt',
      'label.body': 'Körper',
      'label.number': 'Zahl',
    },
    'en': {
      'animal': 'Which one is an animal?',
      'flies': 'Which one can fly?',
      'swims': 'Which one can swim?',
      'walks': 'Which one can walk?',
      'talks': 'Which one can talk?',
      'eat': 'Which one can you eat?',
      'drink': 'Which one can you drink?',
      'wear': 'Which one can you wear?',
      'plant': 'Which one is a plant?',
      'wheels': 'Which one has wheels?',
      'music': 'Which one can you make music with?',
      'shines': 'Which one gives light?',
      'cold': 'Which one is cold?',
      'body': 'Which one is part of your body?',
      'number': 'Which one is a number?',
      'biggest': 'Which one is the biggest?',
      'smallest': 'Which one is the smallest?',
      'heaviest': 'Which one is the heaviest?',
      'lightest': 'Which one is the lightest?',
      'or': 'or',
      'answerIs': 'The answer is: {w}.',
      'startsLike': 'Which one starts like {w}?',
      'notUnderstood': 'I did not catch that. Once more!',
      'label.animal': 'animal',
      'label.flies': 'flies',
      'label.swims': 'swims',
      'label.walks': 'walks',
      'label.talks': 'talks',
      'label.eat': 'to eat',
      'label.drink': 'to drink',
      'label.wear': 'to wear',
      'label.plant': 'plant',
      'label.wheels': 'wheels',
      'label.music': 'music',
      'label.shines': 'gives light',
      'label.cold': 'cold',
      'label.body': 'body',
      'label.number': 'number',
    },
    'fr': {
      'animal': 'Lequel est un animal\u00A0?',
      'flies': 'Qu’est-ce qui peut voler\u00A0?',
      'swims': 'Qu’est-ce qui peut nager\u00A0?',
      'walks': 'Qui peut marcher\u00A0?',
      'talks': 'Qui peut parler\u00A0?',
      'eat': 'Qu’est-ce qu’on peut manger\u00A0?',
      'drink': 'Qu’est-ce qu’on peut boire\u00A0?',
      'wear': 'Qu’est-ce qu’on peut mettre sur soi\u00A0?',
      'plant': 'Lequel est une plante\u00A0?',
      'wheels': 'Qu’est-ce qui a des roues\u00A0?',
      'music': 'Avec quoi peut-on faire de la musique\u00A0?',
      'shines': 'Qu’est-ce qui fait de la lumière\u00A0?',
      'cold': 'Qu’est-ce qui est froid\u00A0?',
      'body': 'Qu’est-ce qui fait partie de ton corps\u00A0?',
      'number': 'Lequel est un nombre\u00A0?',
      'biggest': 'Lequel est le plus grand\u00A0?',
      'smallest': 'Lequel est le plus petit\u00A0?',
      'heaviest': 'Lequel est le plus lourd\u00A0?',
      'lightest': 'Lequel est le plus léger\u00A0?',
      'or': 'ou',
      'answerIs': 'La réponse est\u00A0: {w}.',
      'startsLike': 'Qu’est-ce qui commence comme {w}\u00A0?',
      'notUnderstood': 'Je n’ai pas compris. Encore une fois\u00A0!',
      'label.animal': 'animal',
      'label.flies': 'vole',
      'label.swims': 'nage',
      'label.walks': 'marche',
      'label.talks': 'parle',
      'label.eat': 'se mange',
      'label.drink': 'se boit',
      'label.wear': 'se met',
      'label.plant': 'plante',
      'label.wheels': 'des roues',
      'label.music': 'musique',
      'label.shines': 'éclaire',
      'label.cold': 'froid',
      'label.body': 'corps',
      'label.number': 'nombre',
    },
    'it': {
      'animal': 'Quale di questi è un animale?',
      'flies': 'Cosa può volare?',
      'swims': 'Cosa può nuotare?',
      'walks': 'Cosa può camminare?',
      'talks': 'Chi sa parlare?',
      'eat': 'Cosa si può mangiare?',
      'drink': 'Cosa si può bere?',
      'wear': 'Cosa si può indossare?',
      'plant': 'Quale di questi è una pianta?',
      'wheels': 'Cosa ha le ruote?',
      'music': 'Con cosa si può fare musica?',
      'shines': 'Cosa fa luce?',
      'cold': 'Cos’è freddo?',
      'body': 'Cosa fa parte del tuo corpo?',
      'number': 'Quale di questi è un numero?',
      'biggest': 'Qual è il più grande?',
      'smallest': 'Qual è il più piccolo?',
      'heaviest': 'Qual è il più pesante?',
      'lightest': 'Qual è il più leggero?',
      'or': 'o',
      'answerIs': 'La risposta è: {w}.',
      'startsLike': 'Cosa comincia come {w}?',
      'notUnderstood': 'Non ho capito. Ancora una volta!',
      'label.animal': 'animale',
      'label.flies': 'vola',
      'label.swims': 'nuota',
      'label.walks': 'cammina',
      'label.talks': 'parla',
      'label.eat': 'si mangia',
      'label.drink': 'si beve',
      'label.wear': 'si indossa',
      'label.plant': 'pianta',
      'label.wheels': 'ruote',
      'label.music': 'musica',
      'label.shines': 'fa luce',
      'label.cold': 'freddo',
      'label.body': 'corpo',
      'label.number': 'numero',
    },
    'es': {
      'animal': '¿Cuál es un animal?',
      'flies': '¿Qué puede volar?',
      'swims': '¿Qué puede nadar?',
      'walks': '¿Quién puede caminar?',
      'talks': '¿Quién puede hablar?',
      'eat': '¿Qué se puede comer?',
      'drink': '¿Qué se puede beber?',
      'wear': '¿Qué te puedes poner?',
      'plant': '¿Cuál es una planta?',
      'wheels': '¿Qué tiene ruedas?',
      'music': '¿Con qué se puede hacer música?',
      'shines': '¿Qué da luz?',
      'cold': '¿Qué está frío?',
      'body': '¿Qué es parte de tu cuerpo?',
      'number': '¿Cuál es un número?',
      'biggest': '¿Cuál es el más grande?',
      'smallest': '¿Cuál es el más pequeño?',
      'heaviest': '¿Cuál es el más pesado?',
      'lightest': '¿Cuál es el más ligero?',
      'or': 'o',
      'answerIs': 'La respuesta es: {w}.',
      'startsLike': '¿Qué empieza como {w}?',
      'notUnderstood': 'No te he entendido. ¡Otra vez!',
      'label.animal': 'animal',
      'label.flies': 'vuela',
      'label.swims': 'sabe nadar',
      'label.walks': 'camina',
      'label.talks': 'habla',
      'label.eat': 'se come',
      'label.drink': 'se bebe',
      'label.wear': 'se pone',
      'label.plant': 'planta',
      'label.wheels': 'ruedas',
      'label.music': 'música',
      'label.shines': 'da luz',
      'label.cold': 'frío',
      'label.body': 'cuerpo',
      'label.number': 'número',
    },
  };
}
