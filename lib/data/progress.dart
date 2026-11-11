import 'package:shared_preferences/shared_preferences.dart';

/// Best stars (0..3) per phrase, stored on the device only.
class Progress {
  Progress(this._prefs);

  final SharedPreferences _prefs;

  static Future<Progress> load() async =>
      Progress(await SharedPreferences.getInstance());

  String _key(String lang, String phrase) => 'stars|$lang|$phrase';

  int stars(String lang, String phrase) =>
      _prefs.getInt(_key(lang, phrase)) ?? 0;

  /// Returns true if this is a new best.
  Future<bool> record(String lang, String phrase, int stars) async {
    if (stars <= this.stars(lang, phrase)) return false;
    await _prefs.setInt(_key(lang, phrase), stars);
    return true;
  }

  String? get studyLang => _prefs.getString('studyLang');
  Future<void> setStudyLang(String lang) => _prefs.setString('studyLang', lang);
}
