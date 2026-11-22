// What the phone says in the voice games, in the language the child
// practises (like the praise in game/feedback.dart).

/// One sound to hold: [shown] on the balloon, [said] by the TTS, [sound]
/// what the recognizer must hear (see hold_vowel.dart).
typedef HoldSound = ({String shown, String said, String sound});

const _holdSounds = <String, List<HoldSound>>{
  'de': [
    (shown: 'A', said: 'A', sound: 'a'),
    (shown: 'O', said: 'O', sound: 'o'),
    (shown: 'U', said: 'U', sound: 'u'),
    (shown: 'I', said: 'I', sound: 'i'),
    (shown: 'E', said: 'E', sound: 'e'),
  ],
  'en': [
    (shown: 'AH', said: 'aah', sound: 'a'),
    (shown: 'OH', said: 'oh', sound: 'o'),
    (shown: 'OO', said: 'ooh', sound: 'u'),
    (shown: 'EE', said: 'eee', sound: 'i'),
    (shown: 'MM', said: 'mmm', sound: 'm'),
  ],
  'fr': [
    (shown: 'A', said: 'a', sound: 'a'),
    (shown: 'O', said: 'o', sound: 'o'),
    (shown: 'OU', said: 'ou', sound: 'u'),
    (shown: 'I', said: 'i', sound: 'i'),
    (shown: 'É', said: 'é', sound: 'e'),
  ],
  'it': [
    (shown: 'A', said: 'a', sound: 'a'),
    (shown: 'O', said: 'o', sound: 'o'),
    (shown: 'U', said: 'u', sound: 'u'),
    (shown: 'I', said: 'i', sound: 'i'),
    (shown: 'E', said: 'e', sound: 'e'),
  ],
  'es': [
    (shown: 'A', said: 'a', sound: 'a'),
    (shown: 'O', said: 'o', sound: 'o'),
    (shown: 'U', said: 'u', sound: 'u'),
    (shown: 'I', said: 'i', sound: 'i'),
    (shown: 'E', said: 'e', sound: 'e'),
  ],
};

class VoiceLines {
  const VoiceLines._(this._t, this.sounds);

  /// For a study language like "de-DE"; English if unknown.
  factory VoiceLines.of(String lang) {
    final code = lang.split('-').first;
    final t = _lines[code] ?? _lines['en']!;
    return VoiceLines._(t, _holdSounds[code] ?? _holdSounds['en']!);
  }

  final Map<String, String> _t;

  /// The sounds of one round of "hold it long".
  final List<HoldSound> sounds;

  /// "Say it long: A".
  String holdSay(HoldSound s) => _t['holdSay']!.replaceAll('{s}', s.said);

  /// "That sounded like A, not O.": [heard] is a sound of
  /// hold_vowel.dart ("a"), named like the language's own sound for it.
  String holdWrong(HoldSound want, String heard) {
    final named = sounds.where((s) => s.sound == heard).firstOrNull;
    return _t['holdWrong']!
        .replaceAll('{h}', named?.said ?? heard)
        .replaceAll('{s}', want.said);
  }

  String get record => _t['record']!;
  String get pitchNormal => _t['pitchNormal']!;
  String get pitchLow => _t['pitchLow']!;
  String get pitchHigh => _t['pitchHigh']!;

  static const _lines = {
    'de': {
      'holdSay': 'Halte das {s} ganz lange!',
      'holdWrong': 'Das klang wie {h}, nicht wie {s}.',
      'record': 'Neuer Rekord!',
      'pitchNormal': 'Sag mal A mit deiner normalen Stimme.',
      'pitchLow': 'Jetzt ganz tief, wie ein Bär!',
      'pitchHigh': 'Und jetzt ganz hoch, wie eine Maus!',
    },
    'en': {
      'holdSay': 'Hold it as long as you can: {s}!',
      'holdWrong': 'That sounded like {h}, not {s}.',
      'record': 'New record!',
      'pitchNormal': 'Say ah in your normal voice.',
      'pitchLow': 'Now a big deep voice, like a bear!',
      'pitchHigh': 'And now a tiny high voice, like a mouse!',
    },
    'fr': {
      'holdSay': 'Fais un {s} très long !',
      'holdWrong': 'On aurait dit un {h}, pas un {s}.',
      'record': 'Nouveau record !',
      'pitchNormal': 'Dis a avec ta voix normale.',
      'pitchLow': 'Maintenant une grosse voix, comme un ours !',
      'pitchHigh': 'Et maintenant une petite voix, comme une souris !',
    },
    'it': {
      'holdSay': 'Fai una {s} lunghissima!',
      'holdWrong': 'Sembrava una {h}, non una {s}.',
      'record': 'Nuovo record!',
      'pitchNormal': 'Di’ «a» con la tua voce normale.',
      'pitchLow': 'Ora un vocione, come un orso!',
      'pitchHigh': 'E ora una vocina, come un topolino!',
    },
    'es': {
      'holdSay': '¡Di una {s} muy larga!',
      'holdWrong': 'Sonaba como una {h}, no como una {s}.',
      'record': '¡Nuevo récord!',
      'pitchNormal': 'Di «a» con tu voz normal.',
      'pitchLow': '¡Ahora un vozarrón, como un oso!',
      'pitchHigh': '¡Y ahora una vocecita, como un ratón!',
    },
  };
}
