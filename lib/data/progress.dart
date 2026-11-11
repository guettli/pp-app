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

  String? get studyLang => _prefs.getString('studyLang');
  Future<void> setStudyLang(String lang) => _prefs.setString('studyLang', lang);
}
