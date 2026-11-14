#!/usr/bin/env python3
"""Builds assets/phrases/<lang>.json from tool/words.tsv.

IPA comes from English Wiktionary (like guettli/pp): the pronunciation of
the word in the study language's section, preferring Received Pronunciation
for en-GB and Spain for es-ES. Multi-word entries are looked up as a whole
first, then word by word. A cell "a|b" makes "b" an accepted alternative. tool/ipa_overrides.tsv wins over Wiktionary.

Usage: python3 tool/build_words.py <cache dir>
Prints every word whose IPA could not be found and exits 1 in that case.
"""

import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANGS = ["de-DE", "en-GB", "fr-FR", "it-IT", "es-ES"]
HEADING = {
    "de-DE": "German",
    "en-GB": "English",
    "fr-FR": "French",
    "it-IT": "Italian",
    "es-ES": "Spanish",
}
UA = "phoneme-party-app/0.1 (offline pronunciation game for kids)"


class _Section(HTMLParser):
    """Collects (line text, IPA) pairs from one language section."""

    def __init__(self, heading: str):
        super().__init__(convert_charrefs=True)
        self.heading = heading
        self.inside = False
        self.done = False
        self.li: list[list] = []  # stack of [text parts, ipas]
        self.ipa_depth = 0  # >0 while inside <span class="IPA">
        self.span_depth = 0
        self.ipa_text: list[str] = []
        self.out: list[tuple[str, str]] = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "h2":
            if self.inside:
                self.inside, self.done = False, True
            elif not self.done and a.get("id") == self.heading:
                self.inside = True
            return
        if not self.inside:
            return
        if tag == "li":
            self.li.append([[], []])
        elif tag == "span":
            self.span_depth += 1
            if self.ipa_depth == 0 and "IPA" in (a.get("class") or "").split():
                self.ipa_depth = self.span_depth
                self.ipa_text = []

    def handle_endtag(self, tag):
        if not self.inside:
            return
        if tag == "span":
            if self.ipa_depth and self.span_depth == self.ipa_depth:
                ipa = "".join(self.ipa_text).strip()
                if ipa and self.li:
                    self.li[-1][1].append(ipa)
                self.ipa_depth = 0
            self.span_depth -= 1
        elif tag == "li" and self.li:
            parts, ipas = self.li.pop()
            text = "".join(parts)
            for ipa in ipas:
                self.out.append((text, ipa))

    def handle_data(self, data):
        if not self.inside:
            return
        if self.ipa_depth:
            self.ipa_text.append(data)
        for parts, _ in self.li:
            parts.append(data)


def fetch(title: str, cache: Path) -> str | None:
    f = cache / (urllib.parse.quote(title, safe="") + ".html")
    if f.exists():
        text = f.read_text(encoding="utf-8")
        return text or None
    url = "https://en.wiktionary.org/w/index.php?" + urllib.parse.urlencode(
        {"title": title, "action": "render"}
    )
    for attempt in range(6):
        time.sleep(1.0)  # be polite
        try:
            with urllib.request.urlopen(
                urllib.request.Request(url, headers={"User-Agent": UA}), timeout=30
            ) as r:
                text = r.read().decode("utf-8")
            break
        except urllib.error.HTTPError as e:
            if e.code == 404:
                text = ""
                break
            time.sleep(5 * (attempt + 1))
        except OSError:
            time.sleep(5 * (attempt + 1))
    else:
        raise SystemExit(f"cannot fetch {title}")
    f.write_text(text, encoding="utf-8")
    return text or None


def choose(cands: list[tuple[str, str]], lang: str) -> str | None:
    phonemic = [(t, i) for t, i in cands if i.startswith("/")] or cands
    if not phonemic:
        return None

    def pref(c):
        t = c[0]
        if lang == "en-GB":
            return 0 if re.search(r"Received Pronunciation|\bUK\b", t) else 1
        if lang == "es-ES":
            if "Spain" in t:
                return 0
            return 2 if re.search(r"Latin America|seseo", t) else 1
        return 0

    return sorted(phonemic, key=pref)[0][1]


def lookup(title: str, lang: str, cache: Path) -> str | None:
    for t in dict.fromkeys([title, title.lower(), title[:1].upper() + title[1:]]):
        page = fetch(t, cache)
        if not page:
            continue
        p = _Section(HEADING[lang])
        p.feed(page)
        ipa = choose(p.out, lang)
        if ipa:
            return ipa
    return None


def ipa_for(word: str, lang: str, cache: Path) -> str | None:
    whole = lookup(word, lang, cache)
    if whole or not re.search(r"[\s-]", word):
        return whole
    parts = []
    for w in re.split(r"[\s-]+", word):
        ipa = lookup(w, lang, cache)
        if not ipa:
            return None
        parts.append(ipa.strip("/[]"))
    return "/" + " ".join(parts) + "/"


def syllables(ipa: str) -> int:
    v = re.findall(r"[aeiouyæøœɑɒɔəɛɜɪʊʏɐɯɤʌɨʉ]+", ipa)
    return max(1, len(v))


def level(ipa: str) -> int:
    """Rough difficulty: syllables, length and consonant clusters."""
    core = re.sub(r"[/\[\]ˈˌ.ː̀-ͯʰ-˿]", "", html.unescape(ipa))
    clusters = len(re.findall(r"[^aeiouyæøœɑɒɔəɛɜɪʊʏɐɯɤʌɨʉ\s]{2,}", core))
    return syllables(core) * 100 + len(core) * 10 + clusters * 30


def main() -> int:
    cache = Path(sys.argv[1])
    cache.mkdir(parents=True, exist_ok=True)
    overrides: dict[tuple[str, str], str] = {}
    ov = ROOT / "tool/ipa_overrides.tsv"
    if ov.exists():
        for line in ov.read_text(encoding="utf-8").splitlines():
            if line.strip() and not line.startswith("#"):
                lang, word, ipa = line.split("\t")
                overrides[(lang, word)] = ipa

    rows = []
    for line in (ROOT / "tool/words.tsv").read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            cols = line.split("\t")
            assert len(cols) == 6, line
            rows.append((cols[0], dict(zip(LANGS, cols[1:]))))

    missing = []
    for lang in LANGS:
        out = []
        for emoji, words in rows:
            if words[lang] == "-":
                continue
            # "a|b": the app says a, b is accepted too
            accepted = []
            for word in words[lang].split("|"):
                ipa = overrides.get((lang, word)) or ipa_for(word, lang, cache)
                if not ipa or re.search(r"[()ᵑ]", ipa):
                    # optional sounds "(ə)" cannot be scored: needs an override
                    missing.append(f"{lang}\t{word}\t{ipa or ''}")
                    break
                accepted.append({"p": word, "ipa": ipa})
            else:
                first, *alt = accepted
                entry = {
                    **first,
                    "e": emoji,
                    "lvl": level(first["ipa"]),
                    "tr": {
                        l: w.split("|")[0]
                        for l, w in words.items()
                        if l != lang and w != "-"
                    },
                }
                if alt:
                    entry["alt"] = alt
                out.append(entry)
        out.sort(key=lambda p: (p["lvl"], p["p"]))
        (ROOT / f"assets/phrases/{lang}.json").write_text(
            json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        print(f"{lang}: {len(out)} words", file=sys.stderr)
    for m in missing:
        print("missing\t" + m)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
