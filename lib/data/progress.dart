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

  /// Stores [stars] if it beats the best so far and returns the previous best,
  /// so callers can count only the improvement.
  Future<int> record(String lang, String phrase, int stars) async {
    final prev = this.stars(lang, phrase);
    if (stars > prev) await _prefs.setInt(_key(lang, phrase), stars);
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

  /// Stores [semitones] (distance, positive) if it is a new best.
  Future<bool> recordPitch(double semitones, {required bool low}) async {
    if (semitones <= pitchBest(low: low)) return false;
    await _prefs.setDouble(low ? 'pitch|low' : 'pitch|high', semitones);
    return true;
  }

  String? get studyLang => _prefs.getString('studyLang');
  Future<void> setStudyLang(String lang) => _prefs.setString('studyLang', lang);
}
