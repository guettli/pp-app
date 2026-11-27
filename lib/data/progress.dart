import 'package:shared_preferences/shared_preferences.dart';

import 'phrases.dart';

/// Best stars (0..3) per phrase, stored on the device only.
class Progress {
  Progress(this._prefs);

  final SharedPreferences _prefs;

  static Future<Progress> load() async =>
      Progress(await SharedPreferences.getInstance());

  String _key(String lang, String phrase) => 'stars|$lang|$phrase';

  int stars(String lang, String phrase) =>
      _prefs.getInt(_key(lang, phrase)) ?? 0;

  /// The child has said [phrase] in a world (also with 0 stars; tries
  /// before this was stored count only with a star).
  bool played(String lang, String phrase) =>
      _prefs.containsKey(_key(lang, phrase));

  /// Stores [stars] if it beats the best so far (or is the first try) and
  /// returns the previous best, so callers can count only the improvement.
  Future<int> record(String lang, String phrase, int stars) async {
    final key = _key(lang, phrase);
    final prev = this.stars(lang, phrase);
    if (stars > prev || !_prefs.containsKey(key)) {
      await _prefs.setInt(key, stars);
    }
    return prev;
  }

  int worldStars(PhraseBook book, int world) =>
      book.world(world).fold(0, (sum, p) => sum + stars(book.lang, p.text));

  /// World n is open when world n-1 has at least one star per phrase on
  /// average.
  bool worldOpen(PhraseBook book, int world) =>
      world == 0 || worldStars(book, world - 1) >= book.world(world - 1).length;

  /// Longest time [sound] was held in the voice game (per study language).
  Duration holdBest(String lang, String sound) =>
      Duration(milliseconds: _prefs.getInt('hold|$lang|$sound') ?? 0);

  /// Stores [held] if it is a new best; returns whether it was.
  Future<bool> recordHold(String lang, String sound, Duration held) async {
    if (held <= holdBest(lang, sound)) return false;
    await _prefs.setInt('hold|$lang|$sound', held.inMilliseconds);
    return true;
  }

  /// Furthest the child went from its own voice, in semitones: [low] the
  /// most below (a positive number), otherwise the most above. Only the
  /// numbers are kept, never a recording.
  double pitchBest({required bool low}) =>
      _prefs.getDouble(low ? 'pitch|low' : 'pitch|high') ?? 0;

  /// Stores [semitones] (distance, positive) if it is a new best. More
  /// than [maxPitchRecord] is a tracking error, not a voice.
  Future<bool> recordPitch(double semitones, {required bool low}) async {
    if (semitones > maxPitchRecord) return false;
    if (semitones <= pitchBest(low: low)) return false;
    await _prefs.setDouble(low ? 'pitch|low' : 'pitch|high', semitones);
    return true;
  }

  static const maxPitchRecord = 15.0;

  /// The child's own voice (Hz) as last measured, for when it cannot be
  /// measured today.
  double? get pitchBase => _prefs.getDouble('pitch|base');
  Future<void> setPitchBase(double hz) => _prefs.setDouble('pitch|base', hz);

  /// Most stars (0..3) for one quiz round (per study language).
  int quizBest(String lang) => _prefs.getInt('quiz|$lang') ?? 0;

  /// Stores [stars] if it is a new best; returns whether it was.
  Future<bool> recordQuiz(String lang, int stars) async {
    if (stars <= quizBest(lang)) return false;
    await _prefs.setInt('quiz|$lang', stars);
    return true;
  }

  /// Most stars (0..3) for one round of "listen closely".
  int listenBest(String lang) => _prefs.getInt('listen|$lang') ?? 0;

  /// Stores [stars] if it is a new best; returns whether it was.
  Future<bool> recordListen(String lang, int stars) async {
    if (stars <= listenBest(lang)) return false;
    await _prefs.setInt('listen|$lang', stars);
    return true;
  }

  /// Most stars (0..3) for one round of the letter puzzle.
  int spellBest(String lang) => _prefs.getInt('spell|$lang') ?? 0;

  /// Stores [stars] if it is a new best; returns whether it was.
  Future<bool> recordSpell(String lang, int stars) async {
    if (stars <= spellBest(lang)) return false;
    await _prefs.setInt('spell|$lang', stars);
    return true;
  }

  /// Most stars (0..3) for one round of "word to picture".
  int readPickBest(String lang) => _prefs.getInt('readpick|$lang') ?? 0;

  /// Stores [stars] if it is a new best; returns whether it was.
  Future<bool> recordReadPick(String lang, int stars) async {
    if (stars <= readPickBest(lang)) return false;
    await _prefs.setInt('readpick|$lang', stars);
    return true;
  }

  /// Most stars (0..3) for one round of "read aloud".
  int readAloudBest(String lang) => _prefs.getInt('readaloud|$lang') ?? 0;

  /// Stores [stars] if it is a new best; returns whether it was.
  Future<bool> recordReadAloud(String lang, int stars) async {
    if (stars <= readAloudBest(lang)) return false;
    await _prefs.setInt('readaloud|$lang', stars);
    return true;
  }

  /// Most stars (0..3) for one round of the sound detective.
  int soundsBest(String lang) => _prefs.getInt('sounds|$lang') ?? 0;

  /// Stores [stars] if it is a new best; returns whether it was.
  Future<bool> recordSounds(String lang, int stars) async {
    if (stars <= soundsBest(lang)) return false;
    await _prefs.setInt('sounds|$lang', stars);
    return true;
  }

  /// Most stars (0..3) for one round of a thinking, feelings or memory
  /// game ([game]: needs, riddle, odd, home, faces, feelings, or
  /// MemoryScreen.progressKey).
  int thinkBest(String game, String lang) => _prefs.getInt('$game|$lang') ?? 0;

  /// Stores [stars] if it is a new best; returns whether it was.
  Future<bool> recordThink(String game, String lang, int stars) async {
    if (stars <= thinkBest(game, lang)) return false;
    await _prefs.setInt('$game|$lang', stars);
    return true;
  }

  /// A grown-up switched on quiz reports (feedback screen, behind the
  /// parent gate): the quiz then shows a button that sends the question
  /// with the child's recording to the developer, the thinking games one
  /// that sends the question (no recording). Stays on until switched off.
  bool get quizReports => _prefs.getBool('settings|quizReports') ?? false;
  Future<void> setQuizReports(bool on) =>
      _prefs.setBool('settings|quizReports', on);

  /// A grown-up switched on the sound symbols (feedback screen, behind
  /// the parent gate): the worlds then show the IPA symbol of every sound
  /// in its chip (ʃ, ŋ, aɪ̯), not just a coloured dot. Off for children:
  /// the symbols are not the letters they learn.
  bool get ipaChips => _prefs.getBool('settings|ipaChips') ?? false;
  Future<void> setIpaChips(bool on) => _prefs.setBool('settings|ipaChips', on);

  /// Rommé: what the first melds must be worth (0: anything).
  int get rummyOpenPoints => _prefs.getInt('rummy|open') ?? 30;
  Future<void> setRummyOpenPoints(int points) =>
      _prefs.setInt('rummy|open', points);

  String? get studyLang => _prefs.getString('studyLang');
  Future<void> setStudyLang(String lang) => _prefs.setString('studyLang', lang);
}
