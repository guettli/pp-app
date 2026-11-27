// What the two feelings games say, in every study language (keyed by the
// language code: "de", "en", "fr", "it", "es"). Naming a feeling is the
// first step to coping with it.
//
// "How do I feel?" (🍦😢): a small story; one of three faces fits. Faces
// that might fit too (angry when the ice cream falls) are never
// offered as wrong ones. After the right face the phone says what helps.
// "Faces" (😄😠): the phone names a feeling, the child taps its face.
//
// The feelings are nouns in fr, it and es ("la joie"): adjectives there
// depend on whether the child is a boy or a girl, and no story or help
// line depends on it either (a test checks for gendered words).

enum Feeling { happy, sad, angry, scared, surprised, disgusted }

/// The face of each feeling (Fluent Emoji in assets/emoji/).
const feelingEmoji = {
  Feeling.happy: '😄',
  Feeling.sad: '😢',
  Feeling.angry: '😠',
  Feeling.scared: '😨',
  Feeling.surprised: '😲',
  Feeling.disgusted: '🤢',
};

/// The name of each feeling, as said and shown under its face.
const feelingNames = <String, Map<Feeling, String>>{
  'de': {
    Feeling.happy: 'fröhlich',
    Feeling.sad: 'traurig',
    Feeling.angry: 'wütend',
    Feeling.scared: 'ängstlich',
    Feeling.surprised: 'überrascht',
    Feeling.disgusted: 'angeekelt',
  },
  'en': {
    Feeling.happy: 'happy',
    Feeling.sad: 'sad',
    Feeling.angry: 'angry',
    Feeling.scared: 'scared',
    Feeling.surprised: 'surprised',
    Feeling.disgusted: 'disgusted',
  },
  'fr': {
    Feeling.happy: 'la joie',
    Feeling.sad: 'la tristesse',
    Feeling.angry: 'la colère',
    Feeling.scared: 'la peur',
    Feeling.surprised: 'la surprise',
    Feeling.disgusted: 'le dégoût',
  },
  'it': {
    Feeling.happy: 'la gioia',
    Feeling.sad: 'la tristezza',
    Feeling.angry: 'la rabbia',
    Feeling.scared: 'la paura',
    Feeling.surprised: 'la sorpresa',
    Feeling.disgusted: 'il disgusto',
  },
  'es': {
    Feeling.happy: 'la alegría',
    Feeling.sad: 'la tristeza',
    Feeling.angry: 'el enfado',
    Feeling.scared: 'el miedo',
    Feeling.surprised: 'la sorpresa',
    Feeling.disgusted: 'el asco',
  },
};

/// Said after the story.
const feelingQuestion = {
  'de': 'Wie fühle ich mich?',
  'en': 'How do I feel?',
  'fr': 'Qu’est-ce que je ressens ?',
  'it': 'Cosa provo?',
  'es': '¿Qué siento?',
};

/// "Faces": {f} is the feeling's name.
const faceQuestion = {
  'de': 'Welches Gesicht ist {f}?',
  'en': 'Which face is {f}?',
  'fr': 'Quel visage montre {f} ?',
  'it': 'Quale faccia mostra {f}?',
  'es': '¿Qué cara muestra {f}?',
};

/// A small story, the feeling it brings and what helps.
class FeelingStory {
  const FeelingStory(this.yes, this.say, this.help, {this.maybe = const {}});

  /// The feeling most children would have.
  final Feeling yes;

  /// Feelings that fit too: never offered as wrong faces.
  final Set<Feeling> maybe;

  /// The story, said before [feelingQuestion].
  final Map<String, String> say;

  /// What helps with the feeling, said after the right face.
  final Map<String, String> help;
}

const feelingStories = <FeelingStory>[
  FeelingStory(
    Feeling.sad,
    maybe: {Feeling.angry, Feeling.surprised},
    {
      'de': 'Mein Eis ist auf den Boden gefallen.',
      'en': 'My ice cream fell on the floor.',
      'fr': 'Ma glace est tombée par terre.',
      'it': 'Il mio gelato è caduto per terra.',
      'es': 'Mi helado se ha caído al suelo.',
    },
    {
      'de': 'Wenn ich traurig bin, hilft mir eine Umarmung.',
      'en': 'When I am sad, a hug helps me.',
      'fr': 'Quand je suis triste, un câlin m’aide.',
      'it': 'Quando sono triste, un abbraccio mi aiuta.',
      'es': 'Cuando estoy triste, un abrazo me ayuda.',
    },
  ),
  FeelingStory(
    Feeling.happy,
    maybe: {Feeling.surprised},
    {
      'de': 'Oma kommt zu Besuch und bringt Kuchen mit.',
      'en': 'Grandma comes to visit and brings a cake.',
      'fr': 'Mamie vient nous voir et apporte un gâteau.',
      'it': 'La nonna viene a trovarci e porta una torta.',
      'es': 'La abuela viene de visita y trae un pastel.',
    },
    {
      'de': 'Freude kann ich teilen: Ich erzähle es allen!',
      'en': 'I can share my joy: I tell everybody!',
      'fr': 'Je peux partager ma joie : je le raconte à tout le monde !',
      'it': 'Posso condividere la mia gioia: lo racconto a tutti!',
      'es': 'Puedo compartir mi alegría: ¡se lo cuento a todos!',
    },
  ),
  FeelingStory(
    Feeling.scared,
    maybe: {Feeling.surprised},
    {
      'de': 'In der Nacht donnert es ganz laut.',
      'en': 'At night there is very loud thunder.',
      'fr': 'La nuit, le tonnerre gronde très fort.',
      'it': 'Di notte tuona fortissimo.',
      'es': 'Por la noche hay truenos muy fuertes.',
    },
    {
      'de': 'Wenn ich Angst habe, gehe ich zu jemandem, der mich lieb hat.',
      'en': 'When I am scared, I go to someone who loves me.',
      'fr': 'Quand j’ai peur, je vais voir quelqu’un qui m’aime.',
      'it': 'Quando ho paura, vado da qualcuno che mi vuole bene.',
      'es': 'Cuando tengo miedo, voy con alguien que me quiere.',
    },
  ),
  FeelingStory(
    Feeling.angry,
    maybe: {Feeling.sad, Feeling.surprised},
    {
      'de': 'Ein Kind nimmt mir einfach mein Spielzeug weg.',
      'en': 'A child just takes my toy away.',
      'fr': 'Un enfant me prend mon jouet.',
      'it': 'Un bambino mi porta via il giocattolo.',
      'es': 'Un niño me quita mi juguete.',
    },
    {
      'de':
          'Wenn ich wütend bin, sage ich laut: Stopp! Und ich hole einen '
          'Erwachsenen.',
      'en': 'When I am angry, I say loudly: Stop! And I get a grown-up.',
      'fr':
          'Quand je suis en colère, je dis fort : Stop ! Et je vais '
          'chercher un adulte.',
      'it': 'Quando mi arrabbio, dico forte: Basta! E chiamo un adulto.',
      'es': 'Cuando me enfado, digo fuerte: ¡Para! Y llamo a un adulto.',
    },
  ),
  FeelingStory(
    Feeling.disgusted,
    maybe: {Feeling.surprised},
    {
      'de': 'In meiner Tasche liegt eine alte, matschige Banane.',
      'en': 'There is an old, mushy banana in my bag.',
      'fr': 'Il y a une vieille banane toute molle dans mon sac.',
      'it': 'Nello zaino c’è una banana vecchia e molliccia.',
      'es': 'En mi mochila hay un plátano viejo y pocho.',
    },
    {
      'de': 'Bäh! Ich werfe sie weg und wasche mir die Hände.',
      'en': 'Yuck! I throw it away and wash my hands.',
      'fr': 'Beurk ! Je la jette et je me lave les mains.',
      'it': 'Che schifo! La butto via e mi lavo le mani.',
      'es': '¡Puaj! Lo tiro y me lavo las manos.',
    },
  ),
  FeelingStory(
    Feeling.sad,
    maybe: {Feeling.angry},
    {
      'de': 'Meine beste Freundin zieht weit weg.',
      'en': 'My best friend is moving far away.',
      'fr': 'Ma meilleure amie déménage très loin.',
      'it': 'La mia migliore amica si trasferisce lontano.',
      'es': 'Mi mejor amiga se muda muy lejos.',
    },
    {
      'de': 'Ich male ihr ein Bild. Dann denkt sie an mich.',
      'en': 'I paint her a picture. Then she thinks of me.',
      'fr': 'Je lui fais un dessin. Comme ça, elle pense à moi.',
      'it': 'Le faccio un disegno. Così pensa a me.',
      'es': 'Le hago un dibujo. Así piensa en mí.',
    },
  ),
  FeelingStory(
    Feeling.surprised,
    maybe: {Feeling.scared, Feeling.happy, Feeling.angry},
    {
      'de': 'Papa springt hinter der Tür hervor und ruft: Buh!',
      'en': 'Dad jumps out from behind the door and shouts: Boo!',
      'fr': 'Papa sort de derrière la porte et crie : Bouh !',
      'it': 'Papà salta fuori da dietro la porta e grida: Buh!',
      'es': 'Papá sale de detrás de la puerta y grita: ¡Bu!',
    },
    {
      'de':
          'Mein Herz klopft schnell. Ich atme tief, dann wird es wieder '
          'ruhig.',
      'en': 'My heart beats fast. I breathe deeply, and it calms down.',
      'fr': 'Mon cœur bat vite. Je respire profondément et il se calme.',
      'it': 'Il cuore mi batte forte. Faccio un respiro profondo e si calma.',
      'es': 'Mi corazón late rápido. Respiro hondo y se calma.',
    },
  ),
  FeelingStory(
    Feeling.happy,
    maybe: {Feeling.surprised},
    {
      'de': 'Ich bin zum ersten Mal ohne Hilfe Fahrrad gefahren.',
      'en': 'I rode my bike without help for the first time.',
      'fr': 'Pour la première fois, j’ai fait du vélo sans aide.',
      'it': 'Per la prima volta ho pedalato senza aiuto.',
      'es': 'Por primera vez he montado en bici sin ayuda.',
    },
    {
      'de': 'Ich bin stolz auf mich! Das fühlt sich warm und schön an.',
      'en': 'I am proud of myself! That feels warm and nice.',
      'fr': 'Quelle fierté ! C’est un sentiment chaud et doux.',
      'it': 'Che orgoglio! È una sensazione calda e bella.',
      'es': '¡Qué orgullo! Es un sentimiento cálido y bonito.',
    },
  ),
  FeelingStory(
    Feeling.scared,
    maybe: {Feeling.sad},
    {
      'de': 'Auf dem Spielplatz sehe ich Mama nicht mehr.',
      'en': 'At the playground I can’t see Mum anymore.',
      'fr': 'Au parc, je ne vois plus maman.',
      'it': 'Al parco giochi non vedo più la mamma.',
      'es': 'En el parque ya no veo a mamá.',
    },
    {
      'de': 'Ich bleibe, wo ich bin, und rufe laut nach Mama.',
      'en': 'I stay where I am and call loudly for Mum.',
      'fr': 'Je reste où je suis et j’appelle maman très fort.',
      'it': 'Resto dove sono e chiamo forte la mamma.',
      'es': 'No me muevo y llamo fuerte a mamá.',
    },
  ),
  FeelingStory(
    Feeling.disgusted,
    maybe: {Feeling.angry, Feeling.surprised},
    {
      'de': 'In meiner Suppe ist ein Haar.',
      'en': 'There is a hair in my soup.',
      'fr': 'Il y a un cheveu dans ma soupe.',
      'it': 'C’è un capello nella mia minestra.',
      'es': 'Hay un pelo en mi sopa.',
    },
    {
      'de': 'Ich sage Bescheid und bekomme einen neuen Teller.',
      'en': 'I tell someone and get a new bowl.',
      'fr': 'Je le dis et on me donne une autre assiette.',
      'it': 'Lo dico e mi danno un altro piatto.',
      'es': 'Lo digo y me dan otro plato.',
    },
  ),
  FeelingStory(
    Feeling.sad,
    maybe: {Feeling.angry},
    {
      'de': 'Die anderen Kinder lassen mich nicht mitspielen.',
      'en': 'The other children will not let me play.',
      'fr': 'Les autres enfants ne veulent pas jouer avec moi.',
      'it': 'Gli altri bambini non mi fanno giocare.',
      'es': 'Los otros niños no me dejan jugar.',
    },
    {
      'de': 'Ich erzähle es jemandem, der mich lieb hat.',
      'en': 'I tell someone who loves me.',
      'fr': 'Je le raconte à quelqu’un qui m’aime.',
      'it': 'Lo racconto a qualcuno che mi vuole bene.',
      'es': 'Se lo cuento a alguien que me quiere.',
    },
  ),
  FeelingStory(
    Feeling.surprised,
    maybe: {Feeling.happy},
    {
      'de': 'Der Postbote bringt ein Paket mit meinem Namen.',
      'en': 'The postman brings a parcel with my name on it.',
      'fr': 'Le facteur apporte un colis à mon nom.',
      'it': 'Il postino porta un pacco con il mio nome.',
      'es': 'El cartero trae un paquete con mi nombre.',
    },
    {
      'de': 'Was da wohl drin ist? Ich mache es gleich auf!',
      'en': 'What can be inside? I open it right away!',
      'fr': 'Qu’est-ce qu’il y a dedans ? Je l’ouvre tout de suite !',
      'it': 'Chissà cosa c’è dentro? Lo apro subito!',
      'es': '¿Qué habrá dentro? ¡Lo abro ahora mismo!',
    },
  ),
  FeelingStory(
    Feeling.angry,
    maybe: {Feeling.sad, Feeling.surprised},
    {
      'de': 'Mein Bruder wirft meinen hohen Turm um.',
      'en': 'My brother knocks over my tall tower.',
      'fr': 'Mon frère fait tomber ma grande tour.',
      'it': 'Mio fratello butta giù la mia torre alta.',
      'es': 'Mi hermano tira mi torre alta.',
    },
    {
      'de': 'Wenn ich wütend bin, stampfe ich fest auf und atme tief.',
      'en': 'When I am angry, I stamp my feet and breathe deeply.',
      'fr':
          'Quand je suis en colère, je tape des pieds et je respire '
          'profondément.',
      'it': 'Quando mi arrabbio, batto i piedi e respiro profondamente.',
      'es': 'Cuando me enfado, doy pisotones y respiro hondo.',
    },
  ),
  FeelingStory(
    Feeling.scared,
    maybe: {Feeling.surprised, Feeling.happy},
    {
      'de': 'Ein großer Hund bellt laut und rennt auf mich zu.',
      'en': 'A big dog barks loudly and runs towards me.',
      'fr': 'Un gros chien aboie fort et court vers moi.',
      'it': 'Un cane grande abbaia forte e corre verso di me.',
      'es': 'Un perro grande ladra fuerte y corre hacia mí.',
    },
    {
      'de': 'Ich bleibe ganz still stehen und rufe einen Erwachsenen.',
      'en': 'I stand very still and call a grown-up.',
      'fr': 'Je reste immobile et j’appelle un adulte.',
      'it': 'Non mi muovo e chiamo un adulto.',
      'es': 'No me muevo y llamo a un adulto.',
    },
  ),
  FeelingStory(
    Feeling.happy,
    maybe: {Feeling.surprised},
    {
      'de': 'Heute ist mein Geburtstag, und alle meine Freunde kommen.',
      'en': 'Today is my birthday, and all my friends are coming.',
      'fr': 'Aujourd’hui, c’est mon anniversaire et tous mes amis viennent.',
      'it': 'Oggi è il mio compleanno e vengono tutti i miei amici.',
      'es': 'Hoy es mi cumpleaños y vienen todos mis amigos.',
    },
    {
      'de': 'Ich lache und tanze vor Freude!',
      'en': 'I laugh and dance with joy!',
      'fr': 'Je ris et je danse de joie !',
      'it': 'Rido e ballo di gioia!',
      'es': '¡Me río y bailo de alegría!',
    },
  ),
  FeelingStory(
    Feeling.disgusted,
    maybe: {Feeling.angry, Feeling.surprised},
    {
      'de': 'Ich bin in Hundekacke getreten.',
      'en': 'I stepped in dog poo.',
      'fr': 'J’ai marché dans une crotte de chien.',
      'it': 'Ho pestato una cacca di cane.',
      'es': 'He pisado una caca de perro.',
    },
    {
      'de': 'Igitt! Ich mache meinen Schuh sauber.',
      'en': 'Yuck! I clean my shoe.',
      'fr': 'Beurk ! Je nettoie ma chaussure.',
      'it': 'Che schifo! Pulisco la scarpa.',
      'es': '¡Qué asco! Limpio el zapato.',
    },
  ),
];
