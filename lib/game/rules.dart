/// Longest recording for [text]. Kids speak slowly, and a cut-off tail would
/// count as missing sounds, so long phrases get more time.
Duration recordingLimit(String text) {
  final ms = 2500 + 120 * text.runes.length;
  return Duration(milliseconds: ms.clamp(4000, 10000));
}

/// Stars to add to the session total: only the improvement over the best
/// result so far ([previousBest]), never negative.
int starsGained(int stars, int previousBest) =>
    stars > previousBest ? stars - previousBest : 0;
