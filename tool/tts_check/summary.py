"""Summarizes one or more tts-check reports.

Usage: python3 tool/tts_check/summary.py report.json [more.json ...]
Prints average stars per voice and the words that got at most one star
from every voice (candidates for a wrong IPA in tool/words.tsv).
"""

import collections
import json
import sys

for path in sys.argv[1:]:
    rows = json.load(open(path, encoding="utf-8"))
    print(f"== {path}")
    by_voice = collections.defaultdict(list)
    by_word = collections.defaultdict(list)
    for r in rows:
        by_voice[r["voice"]].append(r["stars"])
        by_word[(r["lang"], r["p"])].append(r)
    for voice, stars in sorted(by_voice.items()):
        dist = collections.Counter(stars)
        print(f"{voice:36} {sum(stars) / len(stars):.2f} stars  "
              + " ".join(f"{s}★:{dist[s]}" for s in range(4)))
    deaf = [r for r in rows if r.get("notHeard")]
    if deaf:
        print(f"{len(deaf)} not heard (the app would say \"nothing heard\"): "
              + ", ".join(f"{r['voice']}/{r['p']}" for r in deaf[:20]))
    bad = [(k, v) for k, v in sorted(by_word.items()) if max(r["stars"] for r in v) <= 1]
    print(f"{len(bad)} words with at most 1 star from every voice:")
    for (lang, word), v in bad:
        print(f"  {lang} {word:16} {v[0]['ipa']:20} heard: {', '.join(r['recognized'] for r in v)}")
