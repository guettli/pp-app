// What the phone says in the voice games, in the language the child
// practises (like the praise in game/feedback.dart).

/// One sound to hold: [shown] on the balloon, [said] by the TTS.
typedef HoldSound = ({String shown, String said});

const _holdSounds = <String, List<HoldSound>>{
  'de': [
    (shown: 'A', said: 'A'),
    (shown: 'O', said: 'O'),
    (shown: 'U', said: 'U'),
    (shown: 'I', said: 'I'),
    (shown: 'E', said: 'E'),
  ],
  'en': [
    (shown: 'AH', said: 'ah'),
    (shown: 'OH', said: 'oh'),
    (shown: 'OO', said: 'oo'),
    (shown: 'EE', said: 'ee'),
    (shown: 'MM', said: 'mmm'),
  ],
  'fr': [
    (shown: 'A', said: 'a'),
    (shown: 'O', said: 'o'),
    (shown: 'OU', said: 'ou'),
    (shown: 'I', said: 'i'),
    (shown: 'É', said: 'é'),
  ],
  'it': [
    (shown: 'A', said: 'a'),
    (shown: 'O', said: 'o'),
    (shown: 'U', said: 'u'),
    (shown: 'I', said: 'i'),
    (shown: 'E', said: 'e'),
  ],
  'es': [
    (shown: 'A', said: 'a'),
    (shown: 'O', said: 'o'),
    (shown: 'U', said: 'u'),
    (shown: 'I', said: 'i'),
    (shown: 'E', said: 'e'),
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
  String get record => _t['record']!;
  String get pitchNormal => _t['pitchNormal']!;
  String get pitchLow => _t['pitchLow']!;
  String get pitchHigh => _t['pitchHigh']!;

  static const _lines = {
    'de': {
      'holdSay': 'Sag ganz lange: {s}',
      'record': 'Neuer Rekord!',
      'pitchNormal': 'Sag A, mit deiner Stimme.',
      'pitchLow': 'Jetzt ganz tief, wie ein Bär!',
      'pitchHigh': 'Und jetzt ganz hoch, wie eine Maus!',
    },
    'en': {
      'holdSay': 'Say it for a long time: {s}',
      'record': 'New record!',
      'pitchNormal': 'Say ah, in your own voice.',
      'pitchLow': 'Now very low, like a bear!',
      'pitchHigh': 'And now very high, like a mouse!',
    },
    'fr': {
      'holdSay': 'Dis-le très longtemps : {s}',
      'record': 'Nouveau record !',
      'pitchNormal': 'Dis a, avec ta voix.',
      'pitchLow': 'Maintenant très grave, comme un ours !',
      'pitchHigh': 'Et maintenant très aigu, comme une souris !',
    },
    'it': {
      'holdSay': 'Dillo molto a lungo: {s}',
      'record': 'Nuovo record!',
      'pitchNormal': 'Di’ a, con la tua voce.',
      'pitchLow': 'Ora molto basso, come un orso!',
      'pitchHigh': 'E ora molto alto, come un topolino!',
    },
    'es': {
      'holdSay': 'Dilo muy largo: {s}',
      'record': '¡Nuevo récord!',
      'pitchNormal': 'Di a, con tu voz.',
      'pitchLow': '¡Ahora muy grave, como un oso!',
      'pitchHigh': '¡Y ahora muy agudo, como un ratón!',
    },
  };
}
