// What the two thinking games say, in every study language (keyed by the
// language code: "de", "en", "fr", "it", "es"). The pictures are the
// words of the phrase books, found by their emoji.
//
// "What do I need?" (🎒): a small everyday problem; one picture helps.
// "Who am I?" (🕵️): clues one after the other, the last one fits only
// the answer.

/// A problem and what solves it.
class Need {
  const Need(this.yes, this.say, {this.maybe = const {}});

  /// What solves it; one of them is the right picture.
  final Set<String> yes;

  /// What might help too, if a child thinks around a corner (a hammer for
  /// a locked door): never offered as a wrong picture.
  final Set<String> maybe;

  /// The problem, said before [needQuestion].
  final Map<String, String> say;
}

/// Said after the problem.
const needQuestion = {
  'de': 'Was brauche ich?',
  'en': 'What do I need?',
  'fr': 'De quoi ai-je besoin ?',
  'it': 'Di cosa ho bisogno?',
  'es': '¿Qué necesito?',
};

/// Wrong pictures besides the answers of the other problems.
const needExtras = {'⚽', '🎲', '🪁', '🧲'};

const needs = <Need>[
  Need(
    {'☂️'},
    {
      'de': 'Es regnet, und ich will nach draußen.',
      'en': 'It is raining, and I want to go outside.',
      'fr': 'Il pleut et je veux sortir.',
      'it': 'Piove e voglio uscire.',
      'es': 'Está lloviendo y quiero salir.',
    },
  ),
  Need(
    {'🔦'},
    // no candles for small children
    maybe: {'🕯️'},
    {
      'de': 'Es ist ganz dunkel, und ich will etwas sehen.',
      'en': 'It is very dark, and I want to see.',
      'fr': 'Il fait tout noir et je veux voir.',
      'it': 'È tutto buio e voglio vedere.',
      'es': 'Está muy oscuro y quiero ver.',
    },
  ),
  Need({'🥄'}, maybe: {'🥛'}, {
    'de': 'Ich will Suppe essen.',
    'en': 'I want to eat soup.',
    'fr': 'Je veux manger de la soupe.',
    'it': 'Voglio mangiare la minestra.',
    'es': 'Quiero comer sopa.',
  }),
  Need({'🔑'}, maybe: {'🔨', '🪜'}, {
    'de': 'Die Tür ist abgeschlossen, und ich will hinein.',
    'en': 'The door is locked, and I want to get in.',
    'fr': 'La porte est fermée à clé et je veux entrer.',
    'it': 'La porta è chiusa a chiave e voglio entrare.',
    'es': 'La puerta está cerrada con llave y quiero entrar.',
  }),
  Need({'🧤'}, maybe: {'🛁', '🕯️', '🧦', '🧣', '🛏️'}, {
    'de': 'Meine Hände sind ganz kalt.',
    'en': 'My hands are very cold.',
    'fr': 'J’ai très froid aux mains.',
    'it': 'Ho le mani freddissime.',
    'es': 'Tengo las manos muy frías.',
  }),
  Need({'🧣'}, maybe: {'🛁', '🕯️', '🛏️'}, {
    'de': 'Mein Hals ist kalt.',
    'en': 'My neck is cold.',
    'fr': 'J’ai froid au cou.',
    'it': 'Ho freddo al collo.',
    'es': 'Tengo frío en el cuello.',
  }),
  Need({'🧦'}, maybe: {'🛁', '🛏️', '🕯️'}, {
    'de': 'Meine Füße sind kalt.',
    'en': 'My feet are cold.',
    'fr': 'J’ai froid aux pieds.',
    'it': 'Ho freddo ai piedi.',
    'es': 'Tengo los pies fríos.',
  }),
  Need(
    {'✂️'},
    {
      'de': 'Ich will ein Stück Papier ausschneiden.',
      'en': 'I want to cut out a piece of paper.',
      'fr': 'Je veux découper un morceau de papier.',
      'it': 'Voglio ritagliare un pezzo di carta.',
      'es': 'Quiero recortar un trozo de papel.',
    },
  ),
  Need(
    {'✏️'},
    {
      'de': 'Ich will ein Bild malen.',
      'en': 'I want to draw a picture.',
      'fr': 'Je veux faire un dessin.',
      'it': 'Voglio fare un disegno.',
      'es': 'Quiero hacer un dibujo.',
    },
  ),
  Need({'🪥'}, maybe: {'🪣', '🥛'}, {
    'de': 'Ich will mir die Zähne putzen.',
    'en': 'I want to brush my teeth.',
    'fr': 'Je veux me brosser les dents.',
    'it': 'Voglio lavarmi i denti.',
    'es': 'Quiero lavarme los dientes.',
  }),
  Need({'🛏️'}, maybe: {'📖'}, {
    'de': 'Ich bin müde und will schlafen.',
    'en': 'I am tired and want to sleep.',
    'fr': 'Je suis fatigué et je veux dormir.',
    'it': 'Sono stanco e voglio dormire.',
    'es': 'Estoy cansado y quiero dormir.',
  }),
  Need(
    {'🔨'},
    {
      'de': 'Ich will einen Nagel in das Brett schlagen.',
      'en': 'I want to hammer a nail into a piece of wood.',
      'fr': 'Je veux planter un clou dans la planche.',
      'it': 'Voglio piantare un chiodo nell’asse.',
      'es': 'Quiero clavar un clavo en la tabla.',
    },
  ),
  Need({'🧹'}, maybe: {'🪣'}, {
    'de': 'Auf dem Boden liegen lauter Krümel.',
    'en': 'There are crumbs all over the floor.',
    'fr': 'Il y a plein de miettes par terre.',
    'it': 'Ci sono tante briciole sul pavimento.',
    'es': 'Hay muchas migas en el suelo.',
  }),
  Need(
    {'🪜'},
    // poke it down with the broom; the ball itself is no help
    maybe: {'🧹', '⚽'},
    {
      'de': 'Mein Ball liegt oben auf dem Dach.',
      'en': 'My ball is up on the roof.',
      'fr': 'Mon ballon est sur le toit.',
      'it': 'La mia palla è sul tetto.',
      'es': 'Mi pelota está en el tejado.',
    },
  ),
  Need({'🥛'}, maybe: {'🪣'}, {
    'de': 'Ich habe Durst.',
    'en': 'I am thirsty.',
    'fr': 'J’ai soif.',
    'it': 'Ho sete.',
    'es': 'Tengo sed.',
  }),
  Need({'🪣'}, maybe: {'🥄'}, {
    'de': 'Ich will am Strand eine Sandburg bauen.',
    'en': 'I want to build a sandcastle on the beach.',
    'fr': 'Je veux faire un château de sable à la plage.',
    'it': 'Voglio fare un castello di sabbia in spiaggia.',
    'es': 'Quiero hacer un castillo de arena en la playa.',
  }),
  Need(
    {'📖'},
    {
      'de': 'Ich will eine Geschichte lesen.',
      'en': 'I want to read a story.',
      'fr': 'Je veux lire une histoire.',
      'it': 'Voglio leggere una storia.',
      'es': 'Quiero leer un cuento.',
    },
  ),
  Need({'🚑'}, maybe: {'✈️'}, {
    'de': 'Jemand hat sich wehgetan und muss schnell ins Krankenhaus.',
    'en': 'Someone is hurt and needs to get to hospital quickly.',
    'fr': 'Quelqu’un s’est fait mal et doit vite aller à l’hôpital.',
    'it': 'Qualcuno si è fatto male e deve andare subito in ospedale.',
    'es': 'Alguien se ha hecho daño y tiene que ir rápido al hospital.',
  }),
  Need({'🚢'}, maybe: {'✈️'}, {
    'de': 'Ich will über das Meer fahren.',
    'en': 'I want to cross the sea.',
    'fr': 'Je veux traverser la mer.',
    'it': 'Voglio attraversare il mare.',
    'es': 'Quiero cruzar el mar.',
  }),
  Need({'✈️'}, maybe: {'🪁'}, {
    'de': 'Ich will hoch über den Wolken fliegen.',
    'en': 'I want to fly high above the clouds.',
    'fr': 'Je veux voler au-dessus des nuages.',
    'it': 'Voglio volare sopra le nuvole.',
    'es': 'Quiero volar por encima de las nubes.',
  }),
  Need({'🦴'}, maybe: {'🥛'}, {
    'de': 'Mein Hund hat Hunger.',
    'en': 'My dog is hungry.',
    'fr': 'Mon chien a faim.',
    'it': 'Il mio cane ha fame.',
    'es': 'Mi perro tiene hambre.',
  }),
  Need({'🛁'}, maybe: {'🪣'}, {
    'de': 'Ich bin von oben bis unten schmutzig.',
    'en': 'I am dirty from head to toe.',
    'fr': 'Je suis sale de la tête aux pieds.',
    'it': 'Sono sporco dalla testa ai piedi.',
    'es': 'Estoy sucio de pies a cabeza.',
  }),
  Need(
    {'🥁', '🎸', '🎻', '🎺'},
    // a pot and a spoon, a bucket for a drum
    maybe: {'🥄', '🪣', '🔨'},
    {
      'de': 'Ich will Musik machen.',
      'en': 'I want to make music.',
      'fr': 'Je veux faire de la musique.',
      'it': 'Voglio fare musica.',
      'es': 'Quiero hacer música.',
    },
  ),
];

/// A thing that tells the child about itself.
class Riddle {
  const Riddle(this.emoji, this.clues, {this.alike = const {}});

  final String emoji;

  /// Per language three clues, from vague to clear. Each one alone fits
  /// only [emoji] among the pictures shown: none fits another riddle's
  /// thing but [alike].
  final Map<String, List<String>> clues;

  /// Things any one clue might fit too (a banana can be eaten and grows
  /// on a tree like an apple; a duck says "quak" like a frog in German):
  /// never offered with this riddle.
  final Set<String> alike;
}

const riddles = <Riddle>[
  Riddle(
    '🐮',
    alike: {'🐰', '🐔', '🐶', '🐱', '🦓', '🐘'},
    {
      'de': [
        'Ich lebe auf dem Bauernhof.',
        'Ich fresse Gras.',
        'Ich sage Muh!',
      ],
      'en': ['I live on a farm.', 'I eat grass.', 'I say moo!'],
      'fr': ['J’habite à la ferme.', 'Je mange de l’herbe.', 'Je fais meuh !'],
      'it': ['Vivo in fattoria.', 'Mangio l’erba.', 'Faccio muu!'],
      'es': ['Vivo en la granja.', 'Como hierba.', '¡Hago muu!'],
    },
  ),
  Riddle(
    '🐶',
    alike: {'🐮', '🐱', '🐘', '🦒', '🐰', '🦁', '🦓', '🐸', '🐔', '🐟'},

    {
      'de': [
        'Ich habe vier Beine.',
        'Ich wohne gern bei den Menschen.',
        'Ich sage Wau wau!',
      ],
      'en': [
        'I have four legs.',
        'I like to live with people.',
        'I say woof woof!',
      ],
      'fr': [
        'J’ai quatre pattes.',
        'J’aime vivre avec les gens.',
        'Je fais ouaf ouaf !',
      ],
      'it': [
        'Ho quattro zampe.',
        'Mi piace vivere con le persone.',
        'Faccio bau bau!',
      ],
      'es': [
        'Tengo cuatro patas.',
        'Me gusta vivir con la gente.',
        '¡Hago guau guau!',
      ],
    },
  ),
  Riddle(
    '🐱',
    alike: {'🐶', '🐰', '🦁', '🐮', '🦒', '🦓', '🦉', '🐍'},

    {
      'de': [
        'Ich habe weiches Fell.',
        'Ich fange gern Mäuse.',
        'Ich sage Miau!',
      ],
      'en': ['I have soft fur.', 'I like to catch mice.', 'I say meow!'],
      'fr': [
        'J’ai une fourrure toute douce.',
        'J’aime attraper les souris.',
        'Je fais miaou !',
      ],
      'it': [
        'Ho il pelo morbido.',
        'Mi piace acchiappare i topi.',
        'Faccio miao!',
      ],
      'es': ['Tengo el pelo suave.', 'Me gusta cazar ratones.', '¡Hago miau!'],
    },
  ),
  Riddle(
    '🐸',
    alike: {'🦆', '🐟', '🐌', '🐍', '🍎'},
    {
      'de': [
        'Ich lebe am Teich.',
        'Ich bin grün.',
        'Ich kann weit springen und sage Quak!',
      ],
      'en': [
        'I live by a pond.',
        'I am green.',
        'I can jump far and I say ribbit!',
      ],
      'fr': [
        'J’habite près d’une mare.',
        'Je suis verte.',
        'Je saute très loin et je fais coâ coâ !',
      ],
      'it': [
        'Vivo nello stagno.',
        'Sono verde.',
        'Salto lontano e faccio cra cra!',
      ],
      'es': [
        'Vivo en la charca.',
        'Soy verde.',
        '¡Salto muy lejos y hago croac!',
      ],
    },
  ),
  Riddle(
    '🐝',
    alike: {'🐞'},

    {
      'de': [
        'Ich bin klein und kann fliegen.',
        'Ich summe: Summ, summ!',
        'Ich mache Honig.',
      ],
      'en': ['I am small and I can fly.', 'I buzz: bzz, bzz!', 'I make honey.'],
      'fr': [
        'Je suis petite et je vole.',
        'Je fais bzz, bzz !',
        'Je fabrique du miel.',
      ],
      'it': [
        'Sono piccola e so volare.',
        'Faccio bzz, bzz!',
        'Faccio il miele.',
      ],
      'es': ['Soy pequeña y sé volar.', '¡Hago bzz, bzz!', 'Hago miel.'],
    },
  ),
  Riddle(
    '🐟',
    alike: {'🦈', '🐬', '🐳', '🐙', '🐸', '🐧', '🐍', '🐌'},
    {
      'de': [
        'Ich lebe im Wasser.',
        'Ich habe keine Beine.',
        'Ich habe Flossen und glänzende Schuppen.',
      ],
      'en': [
        'I live in the water.',
        'I have no legs.',
        'I have fins and shiny scales.',
      ],
      'fr': [
        'Je vis dans l’eau.',
        'Je n’ai pas de pattes.',
        'J’ai des nageoires et des écailles brillantes.',
      ],
      'it': [
        'Vivo nell’acqua.',
        'Non ho le zampe.',
        'Ho le pinne e le squame lucenti.',
      ],
      'es': [
        'Vivo en el agua.',
        'No tengo patas.',
        'Tengo aletas y escamas brillantes.',
      ],
    },
  ),
  Riddle(
    '🐘',
    alike: {'🐰'},
    {
      'de': [
        'Ich bin sehr groß und grau.',
        'Ich habe große Ohren.',
        'Ich habe einen langen Rüssel.',
      ],
      'en': [
        'I am very big and grey.',
        'I have big ears.',
        'I have a long trunk.',
      ],
      'fr': [
        'Je suis très grand et gris.',
        'J’ai de grandes oreilles.',
        'J’ai une longue trompe.',
      ],
      'it': [
        'Sono molto grande e grigio.',
        'Ho le orecchie grandi.',
        'Ho una lunga proboscide.',
      ],
      'es': [
        'Soy muy grande y gris.',
        'Tengo las orejas grandes.',
        'Tengo una trompa larga.',
      ],
    },
  ),
  Riddle(
    '🦒',
    alike: {'🦩', '🦁', '🐘', '🦓', '🐌'},
    {
      'de': [
        'Ich lebe in Afrika.',
        'Ich fresse Blätter von hohen Bäumen.',
        'Ich habe einen ganz langen Hals.',
      ],
      'en': [
        'I live in Africa.',
        'I eat leaves from tall trees.',
        'I have a very long neck.',
      ],
      'fr': [
        'Je vis en Afrique.',
        'Je mange les feuilles des grands arbres.',
        'J’ai un très long cou.',
      ],
      'it': [
        'Vivo in Africa.',
        'Mangio le foglie degli alberi alti.',
        'Ho il collo lunghissimo.',
      ],
      'es': [
        'Vivo en África.',
        'Como hojas de árboles altos.',
        'Tengo el cuello muy largo.',
      ],
    },
  ),
  Riddle(
    '🐰',
    alike: {'🦘', '🐴'},

    {
      'de': [
        'Ich esse gern Karotten.',
        'Ich habe einen kleinen, runden Schwanz.',
        'Ich habe lange Ohren und hoppele.',
      ],
      'en': [
        'I like to eat carrots.',
        'I have a small, round tail.',
        'I have long ears and I hop.',
      ],
      'fr': [
        'J’aime manger des carottes.',
        'J’ai une petite queue toute ronde.',
        'J’ai de longues oreilles et je saute.',
      ],
      'it': [
        'Mi piace mangiare le carote.',
        'Ho una codina piccola e rotonda.',
        'Ho le orecchie lunghe e saltello.',
      ],
      'es': [
        'Me gusta comer zanahorias.',
        'Tengo una colita pequeña y redonda.',
        'Tengo las orejas largas y doy saltitos.',
      ],
    },
  ),
  Riddle('🐌', {
    'de': [
      'Ich bin sehr langsam.',
      'Ich hinterlasse eine glitzernde Spur.',
      'Ich trage mein Haus auf dem Rücken.',
    ],
    'en': [
      'I am very slow.',
      'I leave a shiny trail.',
      'I carry my house on my back.',
    ],
    'fr': [
      'Je suis très lent.',
      'Je laisse une trace brillante.',
      'Je porte ma maison sur mon dos.',
    ],
    'it': [
      'Sono lentissima.',
      'Lascio una scia luccicante.',
      'Porto la mia casa sulla schiena.',
    ],
    'es': [
      'Soy muy lento.',
      'Dejo un rastro brillante.',
      'Llevo mi casa a la espalda.',
    ],
  }),
  Riddle(
    '🐍',
    alike: {'🐟', '🐌'},

    {
      'de': [
        'Ich habe keine Beine.',
        'Ich bin lang und dünn.',
        'Ich krieche über den Boden und zische: Sss!',
      ],
      'en': [
        'I have no legs.',
        'I am long and thin.',
        'I slither along the ground and hiss: sss!',
      ],
      'fr': [
        'Je n’ai pas de pattes.',
        'Je suis long et fin.',
        'Je rampe par terre et je siffle : sss !',
      ],
      'it': [
        'Non ho le zampe.',
        'Sono lungo e sottile.',
        'Striscio per terra e faccio sss!',
      ],
      'es': [
        'No tengo patas.',
        'Soy larga y delgada.',
        '¡Me arrastro por el suelo y hago sss!',
      ],
    },
  ),
  Riddle(
    '🦉',
    alike: {'🐔', '🌙'},

    {
      'de': [
        'Ich habe Federn und kann fliegen.',
        'Ich bin in der Nacht wach.',
        'Ich habe große, runde Augen und rufe: Schuhu!',
      ],
      'en': [
        'I have feathers and I can fly.',
        'I am awake at night.',
        'I have big round eyes and I call: twit-twoo!',
      ],
      'fr': [
        'J’ai des plumes et je vole.',
        'Je suis réveillé la nuit.',
        'J’ai de grands yeux ronds et je fais hou hou !',
      ],
      'it': [
        'Ho le piume e so volare.',
        'Sto sveglio di notte.',
        'Ho grandi occhi tondi e faccio uh uh!',
      ],
      'es': [
        'Tengo plumas y sé volar.',
        'Estoy despierto por la noche.',
        '¡Tengo grandes ojos redondos y hago uh uh!',
      ],
    },
  ),
  Riddle(
    '☀️',
    alike: {'🌙', '🌈'},

    {
      'de': [
        'Ich bin oben am Himmel.',
        'Ich bin sehr heiß.',
        'Ich scheine am Tag ganz hell.',
      ],
      'en': [
        'I am up in the sky.',
        'I am very hot.',
        'I shine brightly in the daytime.',
      ],
      'fr': [
        'Je suis dans le ciel.',
        'Je suis très chaud.',
        'Je brille très fort pendant la journée.',
      ],
      'it': [
        'Sto lassù nel cielo.',
        'Sono caldissimo.',
        'Splendo forte di giorno.',
      ],
      'es': [
        'Estoy arriba en el cielo.',
        'Doy mucho calor.',
        'Brillo mucho durante el día.',
      ],
    },
  ),
  Riddle(
    '🌙',
    alike: {'🍌', '☀️', '🌈', '🦉', '🍎'},
    {
      'de': [
        'Ich bin oben am Himmel.',
        'Man sieht mich in der Nacht.',
        'Manchmal bin ich rund und manchmal krumm wie eine Banane.',
      ],
      'en': [
        'I am up in the sky.',
        'You see me at night.',
        'Sometimes I am round, and sometimes I am curved like a banana.',
      ],
      'fr': [
        'Je suis dans le ciel.',
        'On me voit la nuit.',
        'Parfois je suis ronde, parfois courbée comme une banane.',
      ],
      'it': [
        'Sto lassù nel cielo.',
        'Mi vedi di notte.',
        'A volte sono tonda, a volte curva come una banana.',
      ],
      'es': [
        'Estoy arriba en el cielo.',
        'Me ves por la noche.',
        'A veces soy redonda y a veces curva como un plátano.',
      ],
    },
  ),
  Riddle(
    '🍌',
    alike: {'🌙', '🍎', '🐟', '🐔', '🐮'},
    {
      'de': [
        'Man kann mich essen.',
        'Ich wachse dort, wo es warm ist.',
        'Ich bin gelb und krumm.',
      ],
      'en': [
        'You can eat me.',
        'I grow where it is warm.',
        'I am yellow and curved.',
      ],
      'fr': [
        'On peut me manger.',
        'Je pousse dans les pays chauds.',
        'Je suis jaune et courbée.',
      ],
      'it': [
        'Mi puoi mangiare.',
        'Cresco nei paesi caldi.',
        'Sono gialla e curva.',
      ],
      'es': [
        'Me puedes comer.',
        'Crezco donde hace calor.',
        'Soy amarillo y curvo.',
      ],
    },
  ),
  Riddle(
    '🍎',
    alike: {'🍅', '🍒', '🍌', '🐟', '🐔', '🐮'},
    {
      'de': [
        'Man kann mich essen.',
        'Ich wachse an einem Baum.',
        'Ich bin rund, rot oder grün und knackig.',
      ],
      'en': [
        'You can eat me.',
        'I grow on a tree.',
        'I am round, red or green, and crunchy.',
      ],
      'fr': [
        'On peut me manger.',
        'Je pousse sur un arbre.',
        'Je suis ronde, rouge ou verte, et croquante.',
      ],
      'it': [
        'Mi puoi mangiare.',
        'Cresco su un albero.',
        'Sono tonda, rossa o verde, e croccante.',
      ],
      'es': [
        'Me puedes comer.',
        'Crezco en un árbol.',
        'Soy redonda, roja o verde, y crujiente.',
      ],
    },
  ),
  Riddle(
    '✂️',
    alike: {'🔑', '🚑'},

    {
      'de': [
        'Ich bin aus Metall.',
        'Ich habe zwei Löcher für deine Finger.',
        'Mit mir kannst du Papier schneiden.',
      ],
      'en': [
        'I am made of metal.',
        'I have two holes for your fingers.',
        'You can cut paper with me.',
      ],
      'fr': [
        'Je suis en métal.',
        'J’ai deux trous pour tes doigts.',
        'Avec moi, tu peux couper du papier.',
      ],
      'it': [
        'Sono di metallo.',
        'Ho due buchi per le dita.',
        'Con me puoi tagliare la carta.',
      ],
      'es': [
        'Soy de metal.',
        'Tengo dos agujeros para tus dedos.',
        'Conmigo puedes cortar papel.',
      ],
    },
  ),
  Riddle(
    '🔑',
    alike: {'✂️'},

    {
      'de': [
        'Ich bin klein und aus Metall.',
        'Ich passe in deine Hosentasche.',
        'Mit mir schließt du die Tür auf.',
      ],
      'en': [
        'I am small and made of metal.',
        'I fit in your pocket.',
        'You unlock the door with me.',
      ],
      'fr': [
        'Je suis petite et en métal.',
        'Je tiens dans ta poche.',
        'Avec moi, tu ouvres la porte fermée à clé.',
      ],
      'it': [
        'Sono piccola e di metallo.',
        'Entro nella tua tasca.',
        'Con me apri la porta chiusa.',
      ],
      'es': [
        'Soy pequeña y de metal.',
        'Quepo en tu bolsillo.',
        'Conmigo abres la puerta cerrada.',
      ],
    },
  ),
  Riddle('🚑', {
    'de': [
      'Ich habe Räder.',
      'Ich bin laut: Tatü tata!',
      'Ich bringe kranke Menschen ins Krankenhaus.',
    ],
    'en': [
      'I have wheels.',
      'I am loud: nee-naw, nee-naw!',
      'I take ill people to hospital.',
    ],
    'fr': [
      'J’ai des roues.',
      'Je fais pin-pon, pin-pon !',
      'J’emmène les malades à l’hôpital.',
    ],
    'it': [
      'Ho le ruote.',
      'Ho una sirena fortissima.',
      'Porto i malati all’ospedale.',
    ],
    'es': [
      'Tengo ruedas.',
      'Tengo una sirena muy fuerte.',
      'Llevo a los enfermos al hospital.',
    ],
  }),
  Riddle('⛄', {
    'de': [
      'Ich bin kalt.',
      'Wenn die Sonne scheint, schmelze ich.',
      'Meine Nase ist eine Karotte.',
    ],
    'en': [
      'I am cold.',
      'When the sun shines, I melt.',
      'My nose is a carrot.',
    ],
    'fr': [
      'Je suis tout froid.',
      'Quand le soleil brille, je fonds.',
      'Mon nez est une carotte.',
    ],
    'it': [
      'Sono freddo.',
      'Quando c’è il sole, mi sciolgo.',
      'Il mio naso è una carota.',
    ],
    'es': [
      'Estoy muy frío.',
      'Cuando sale el sol, me derrito.',
      'Mi nariz es una zanahoria.',
    ],
  }),
  Riddle(
    '🦁',
    alike: {'🐴', '🐱'},
    {
      'de': [
        'Ich bin eine große Katze.',
        'Ich kann laut brüllen.',
        'Um meinen Kopf habe ich eine große Mähne.',
      ],
      'en': [
        'I am a big cat.',
        'I can roar loudly.',
        'I have a big mane around my head.',
      ],
      'fr': [
        'Je suis un très grand chat.',
        'Je rugis très fort.',
        'J’ai une grande crinière autour de la tête.',
      ],
      'it': [
        'Sono un gatto grandissimo.',
        'Ruggisco fortissimo.',
        'Ho una grande criniera intorno alla testa.',
      ],
      'es': [
        'Soy un gato muy grande.',
        'Rujo muy fuerte.',
        'Tengo una gran melena alrededor de la cabeza.',
      ],
    },
  ),
  Riddle(
    '🌈',
    alike: {'☀️', '🌙'},
    {
      'de': [
        'Ich bin oben am Himmel.',
        'Man sieht mich, wenn nach dem Regen die Sonne scheint.',
        'Ich bin ein Bogen aus vielen Farben.',
      ],
      'en': [
        'I am up in the sky.',
        'You see me when the sun comes out after the rain.',
        'I am an arch of many colours.',
      ],
      'fr': [
        'Je suis dans le ciel.',
        'On me voit quand le soleil revient après la pluie.',
        'Je suis un arc de toutes les couleurs.',
      ],
      'it': [
        'Sto lassù nel cielo.',
        'Mi vedi quando torna il sole dopo la pioggia.',
        'Sono un arco di tanti colori.',
      ],
      'es': [
        'Estoy arriba en el cielo.',
        'Me ves cuando sale el sol después de la lluvia.',
        'Soy un arco de muchos colores.',
      ],
    },
  ),
  Riddle(
    '🐞',
    alike: {'🐝', '🐌', '🔑'},
    {
      'de': [
        'Ich bin ganz klein.',
        'Ich habe sechs Beine und kann fliegen.',
        'Ich bin rot und habe schwarze Punkte.',
      ],
      'en': [
        'I am very small.',
        'I have six legs and I can fly.',
        'I am red with black spots.',
      ],
      'fr': [
        'Je suis toute petite.',
        'J’ai six pattes et je vole.',
        'Je suis rouge avec des points noirs.',
      ],
      'it': [
        'Sono piccolissima.',
        'Ho sei zampe e so volare.',
        'Sono rossa con i puntini neri.',
      ],
      'es': [
        'Soy muy pequeña.',
        'Tengo seis patas y sé volar.',
        'Soy roja con puntos negros.',
      ],
    },
  ),
  Riddle(
    '🦓',
    alike: {'🦁', '🐘', '🦒'},
    {
      'de': [
        'Ich sehe fast aus wie ein Pferd.',
        'Ich lebe in Afrika.',
        'Ich habe schwarze und weiße Streifen.',
      ],
      'en': [
        'I look almost like a horse.',
        'I live in Africa.',
        'I have black and white stripes.',
      ],
      'fr': [
        'Je ressemble presque à un cheval.',
        'Je vis en Afrique.',
        'J’ai des rayures noires et blanches.',
      ],
      'it': [
        'Sembro quasi un cavallo.',
        'Vivo in Africa.',
        'Ho le strisce bianche e nere.',
      ],
      'es': [
        'Parezco casi un caballo.',
        'Vivo en África.',
        'Tengo rayas blancas y negras.',
      ],
    },
  ),
  Riddle(
    '🐧',
    alike: {'🦉', '🐔', '🐟', '🐸'},

    {
      'de': [
        'Ich bin ein Vogel.',
        'Ich kann nicht fliegen, aber gut schwimmen.',
        'Ich lebe auf dem Eis und watschle hin und her.',
      ],
      'en': [
        'I am a bird.',
        'I cannot fly, but I swim well.',
        'I live on the ice and waddle around.',
      ],
      'fr': [
        'Je suis un oiseau.',
        'Je ne vole pas, mais je nage bien.',
        'Je vis sur la glace et je me dandine.',
      ],
      'it': [
        'Sono un uccello.',
        'Non so volare, ma nuoto bene.',
        'Vivo sul ghiaccio e cammino dondolando.',
      ],
      'es': [
        'Soy un pájaro.',
        'No sé volar, pero nado muy bien.',
        'Vivo en el hielo y camino balanceándome.',
      ],
    },
  ),
  Riddle(
    '🐔',
    alike: {'🐮', '🐶', '🐱', '🐰', '🦉', '🐧'},

    {
      'de': [
        'Ich lebe auf dem Bauernhof.',
        'Ich habe Federn.',
        'Ich lege Eier und sage Gack, gack!',
      ],
      'en': [
        'I live on a farm.',
        'I have feathers.',
        'I lay eggs and say cluck, cluck!',
      ],
      'fr': [
        'J’habite à la ferme.',
        'J’ai des plumes.',
        'Je ponds des œufs et je fais cot, cot !',
      ],
      'it': [
        'Vivo in fattoria.',
        'Ho le piume.',
        'Faccio le uova e dico coccodè!',
      ],
      'es': [
        'Vivo en la granja.',
        'Tengo plumas.',
        '¡Pongo huevos y hago clo, clo!',
      ],
    },
  ),
];

// "Odd one out" (🧺): three pictures of one kind and one of another kind
// (assets/facts/facts.tsv). After the right tap the phone says why.

/// Said when the four pictures are shown.
const oddQuestion = {
  'de': 'Was passt nicht dazu?',
  'en': 'Which one doesn’t belong?',
  'fr': 'Laquelle n’est pas comme les autres ?',
  'it': 'Quale non c’entra?',
  'es': '¿Cuál no va con los demás?',
};

/// The kinds a group of three can be, by the name of their facts.tsv
/// property, and why the odd one does not belong.
const oddKinds = <String, Map<String, String>>{
  'animal': {
    'de': 'Die anderen sind alle Tiere.',
    'en': 'The others are all animals.',
    'fr': 'Les autres sont tous des animaux.',
    'it': 'Gli altri sono tutti animali.',
    'es': 'Los demás son todos animales.',
  },
  'eat': {
    'de': 'Die anderen kann man essen.',
    'en': 'You can eat the others.',
    'fr': 'Les autres, on peut les manger.',
    'it': 'Gli altri si possono mangiare.',
    'es': 'Los demás se pueden comer.',
  },
  'wear': {
    'de': 'Die anderen kann man anziehen.',
    'en': 'You can wear the others.',
    'fr': 'Les autres, on peut les porter.',
    'it': 'Gli altri si possono indossare.',
    'es': 'Los demás te los puedes poner.',
  },
  'plant': {
    'de': 'Die anderen sind alle Pflanzen.',
    'en': 'The others are all plants.',
    'fr': 'Les autres sont des plantes.',
    'it': 'Gli altri sono tutti piante.',
    'es': 'Los demás son plantas.',
  },
  'wheels': {
    'de': 'Die anderen haben alle Räder.',
    'en': 'The others all have wheels.',
    'fr': 'Les autres ont tous des roues.',
    'it': 'Gli altri hanno tutti le ruote.',
    'es': 'Los demás tienen ruedas.',
  },
  'music': {
    'de': 'Mit den anderen macht man Musik.',
    'en': 'You make music with the others.',
    'fr': 'Avec les autres, on fait de la musique.',
    'it': 'Con gli altri si fa musica.',
    'es': 'Con los demás se hace música.',
  },
  'body': {
    'de': 'Die anderen sind Teile von deinem Körper.',
    'en': 'The others are parts of your body.',
    'fr': 'Les autres sont des parties de ton corps.',
    'it': 'Gli altri sono parti del tuo corpo.',
    'es': 'Los demás son partes de tu cuerpo.',
  },
  'shines': {
    'de': 'Die anderen leuchten alle.',
    'en': 'The others all give light.',
    'fr': 'Les autres font tous de la lumière.',
    'it': 'Gli altri fanno tutti luce.',
    'es': 'Los demás dan luz.',
  },
};

/// The second clue, said after a wrong tap: a nudge to think about what
/// the three have in common (🔊 then says the question and the nudge).
const oddHints = <String, Map<String, String>>{
  'animal': {
    'de': 'Drei davon sind Tiere.',
    'en': 'Three of them are animals.',
    'fr': 'Il y a trois animaux.',
    'it': 'Tre di questi sono animali.',
    'es': 'Tres de ellos son animales.',
  },
  'eat': {
    'de': 'Drei davon kann man essen.',
    'en': 'You can eat three of them.',
    'fr': 'On peut en manger trois.',
    'it': 'Tre di questi si possono mangiare.',
    'es': 'Tres de ellos se pueden comer.',
  },
  'wear': {
    'de': 'Drei davon kann man anziehen.',
    'en': 'You can wear three of them.',
    'fr': 'On peut en porter trois.',
    'it': 'Tre di questi si possono indossare.',
    'es': 'Te puedes poner tres de ellos.',
  },
  'plant': {
    'de': 'Drei davon sind Pflanzen.',
    'en': 'Three of them are plants.',
    'fr': 'Il y a trois plantes.',
    'it': 'Tre di questi sono piante.',
    'es': 'Tres de ellos son plantas.',
  },
  'wheels': {
    'de': 'Drei davon haben Räder.',
    'en': 'Three of them have wheels.',
    'fr': 'Trois d’entre eux ont des roues.',
    'it': 'Tre di questi hanno le ruote.',
    'es': 'Tres de ellos tienen ruedas.',
  },
  'music': {
    'de': 'Mit drei davon macht man Musik.',
    'en': 'You make music with three of them.',
    'fr': 'Avec trois d’entre eux, on fait de la musique.',
    'it': 'Con tre di questi si fa musica.',
    'es': 'Con tres de ellos se hace música.',
  },
  'body': {
    'de': 'Drei davon sind Teile von deinem Körper.',
    'en': 'Three of them are parts of your body.',
    'fr': 'Il y a trois parties de ton corps.',
    'it': 'Tre di questi sono parti del tuo corpo.',
    'es': 'Tres de ellos son partes de tu cuerpo.',
  },
  'shines': {
    'de': 'Drei davon leuchten.',
    'en': 'Three of them give light.',
    'fr': 'Trois d’entre eux font de la lumière.',
    'it': 'Tre di questi fanno luce.',
    'es': 'Tres de ellos dan luz.',
  },
};

/// Kinds never mixed in one question: a carrot is food, but a plant too.
const oddNotTogether = [
  {'plant', 'eat'},
];

// "Who lives here?" (🏞️): a place, and the animal that lives there among
// animals that clearly do not.

/// A place and its animals.
class Habitat {
  const Habitat(this.scene, this.say, this.yes, {this.maybe = const {}});

  /// The picture of the place.
  final String scene;

  /// The question ("Who lives in the sea?").
  final Map<String, String> say;

  /// Who lives there; one of them is the right picture.
  final Set<String> yes;

  /// Who might live there too (a penguin in the sea, a mouse in a house):
  /// never offered as a wrong picture.
  final Set<String> maybe;
}

/// The animals offered as wrong pictures (each place leaves out its own
/// [Habitat.yes] and [Habitat.maybe]).
const habitatAnimals = {
  '🐮', '🐻', '🐟', '🦈', '🐔', '🐑', '🐳', '🐭', '🐸', '🦊', '🐶', //
  '🐺', '🐷', '🐴', '🐵', '🐝', '🐰', '🦔', '🦁', '🐯', '🦉', '🐫', //
  '🐤', '🐦', '🦆', '🐱', '🐙', '🐼', '🐍', '🐌', '🕷️', '🐐', '🐬', //
  '🐧', '🦓', '🦒', '🦜', '🐘', '🦘', '🐊', '🦩', '🦋', '🐿️', '🐞', //
};

const habitats = <Habitat>[
  Habitat(
    '🌊',
    {
      'de': 'Wer wohnt im Meer?',
      'en': 'Who lives in the sea?',
      'fr': 'Qui vit dans la mer ?',
      'it': 'Chi vive nel mare?',
      'es': '¿Quién vive en el mar?',
    },
    {'🐟', '🦈', '🐳', '🐙', '🐬'},
    maybe: {'🐧', '🦆', '🐊', '🦩', '🐸', '🐦', '🐍'},
  ),
  Habitat(
    '🚜',
    {
      'de': 'Wer wohnt auf dem Bauernhof?',
      'en': 'Who lives on the farm?',
      'fr': 'Qui vit à la ferme ?',
      'it': 'Chi vive in fattoria?',
      'es': '¿Quién vive en la granja?',
    },
    {'🐮', '🐔', '🐑', '🐷', '🐴', '🐐', '🐤'},
    maybe: {
      '🐶', '🐱', '🐭', '🦆', '🐰', '🐦', '🐝', '🕷️', '🐌', '🐞', '🦋', //
      '🐸', '🦉', '🦊', '🐍', '🦔', '🐟',
    },
  ),
  Habitat(
    '🌳',
    {
      'de': 'Wer wohnt im Wald?',
      'en': 'Who lives in the forest?',
      'fr': 'Qui vit dans la forêt ?',
      'it': 'Chi vive nel bosco?',
      'es': '¿Quién vive en el bosque?',
    },
    {'🦊', '🐺', '🦔', '🐿️', '🦉', '🐻'},
    maybe: {
      '🐦', '🐌', '🕷️', '🦋', '🐞', '🐝', '🐰', '🐭', '🐍', '🐸', '🐼', //
      '🐵', '🐯', '🦜', '🐘', '🦆',
    },
  ),
  Habitat(
    '🌴',
    {
      'de': 'Wer wohnt im Dschungel?',
      'en': 'Who lives in the jungle?',
      'fr': 'Qui vit dans la jungle ?',
      'it': 'Chi vive nella giungla?',
      'es': '¿Quién vive en la selva?',
    },
    {'🐵', '🦜', '🐯'},
    maybe: {
      '🐍', '🐊', '🐘', '🦋', '🐸', '🕷️', '🐦', '🐝', '🐞', '🐌', '🦁', //
      '🦒', '🦓', '🐼', '🐻', '🦉', '🐭', '🦩', '🐔', '🐟', '🦆',
    },
  ),
  Habitat(
    '❄️',
    {
      'de': 'Wer wohnt auf dem Eis, wo es ganz kalt ist?',
      'en': 'Who lives on the ice, where it is very cold?',
      'fr': 'Qui vit sur la glace, là où il fait très froid ?',
      'it': 'Chi vive sul ghiaccio, dove fa tanto freddo?',
      'es': '¿Quién vive en el hielo, donde hace mucho frío?',
    },
    {'🐧'},
    maybe: {
      '🐳', '🐟', '🦈', '🐙', '🐬', '🦊', '🐻', '🐺', '🦉', '🐰', '🐭', //
      '🦆', '🐦',
    },
  ),
  Habitat(
    '🏜️',
    {
      'de': 'Wer wohnt in der Wüste?',
      'en': 'Who lives in the desert?',
      'fr': 'Qui vit dans le désert ?',
      'it': 'Chi vive nel deserto?',
      'es': '¿Quién vive en el desierto?',
    },
    {'🐫'},
    maybe: {
      '🐍', '🕷️', '🐭', '🦊', '🐝', '🐞', '🦋', '🐦', '🦁', '🦒', '🦓', //
      '🐘', '🐴', '🐐', '🦘', '🐌', '🦉', '🐰', '🐊', '🦩',
    },
  ),
  Habitat(
    '🏠',
    {
      'de': 'Wer wohnt bei uns im Haus?',
      'en': 'Who lives with us at home?',
      'fr': 'Qui vit avec nous à la maison ?',
      'it': 'Chi vive con noi a casa?',
      'es': '¿Quién vive con nosotros en casa?',
    },
    {'🐶', '🐱'},
    maybe: {
      '🐭', '🕷️', '🐰', '🦜', '🐦', '🐟', '🐍', '🐸', '🐝', '🐞', '🦋', //
      '🐌', '🐤', '🐔', '🦔', '🐷', '🐐',
    },
  ),
];
