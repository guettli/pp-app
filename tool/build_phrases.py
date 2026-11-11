#!/usr/bin/env python3
"""Convert guettli/pp phrase YAML files into compact JSON assets for the app.

Usage: python3 tool/build_phrases.py <path-to-pp-checkout>

Writes assets/phrases/<lang>.json and prints the set of emojis used
(input for tool/fetch_emoji.py).
"""
import json
import pathlib
import sys

import yaml

LANGS = ["de-DE", "en-GB", "fr-FR", "it-IT", "es-ES"]


def main() -> None:
    pp = pathlib.Path(sys.argv[1])
    out_dir = pathlib.Path(__file__).resolve().parent.parent / "assets" / "phrases"
    out_dir.mkdir(parents=True, exist_ok=True)
    emojis: set[str] = set()
    for lang in LANGS:
        rows = yaml.safe_load((pp / f"phrases-{lang}.yaml").read_text(encoding="utf-8"))
        phrases = []
        for r in rows:
            ipas = [i["ipa"] for i in r.get("ipas", []) if i.get("ipa")]
            if not ipas:
                continue
            item = {"p": r["phrase"], "e": r["emoji"], "ipa": ipas[0], "lvl": int(r["level"])}
            # translations into the other languages (for the UI hint)
            tr = {k: r[k] for k in LANGS if k in r and k != lang}
            if tr:
                item["tr"] = tr
            phrases.append(item)
            emojis.add(r["emoji"])
        phrases.sort(key=lambda x: x["lvl"])
        (out_dir / f"{lang}.json").write_text(
            json.dumps(phrases, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
        )
        print(f"{lang}: {len(phrases)} phrases", file=sys.stderr)
    print("\n".join(sorted(emojis)))


if __name__ == "__main__":
    main()
