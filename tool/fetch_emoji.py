#!/usr/bin/env python3
"""Fetch Fluent Emoji 3D images (MIT, github.com/microsoft/fluentui-emoji).

Usage: python3 tool/fetch_emoji.py <fluentui-emoji checkout> <emojis.txt>

The checkout may be a sparse/blobless clone; image paths are taken from
`git ls-tree` and the PNGs are downloaded individually. Output:
assets/emoji/<codepoints>.png where <codepoints> is the lowercase hex
sequence without FE0F, joined by "-" (same key as lib/emoji.dart).
"""
import json
import pathlib
import subprocess
import sys
import urllib.request

RAW = "https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/"


def key(emoji: str) -> str:
    return "-".join(f"{ord(c):x}" for c in emoji if ord(c) != 0xFE0F)


def main() -> None:
    repo = pathlib.Path(sys.argv[1])
    wanted = [l.strip() for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
    out = pathlib.Path(__file__).resolve().parent.parent / "assets" / "emoji"
    out.mkdir(parents=True, exist_ok=True)

    files = subprocess.run(["git", "-C", str(repo), "ls-tree", "-r", "--name-only", "HEAD", "assets"],
                           capture_output=True, text=True, check=True).stdout.splitlines()
    pngs_by_folder: dict[str, list[str]] = {}
    for f in files:
        if "/3D/" in f and f.endswith(".png"):
            pngs_by_folder.setdefault(f.split("/")[1], []).append(f)

    by_key: dict[str, str] = {}
    for meta in (repo / "assets").glob("*/metadata.json"):
        m = json.loads(meta.read_text(encoding="utf-8"))
        k = "-".join(f"{int(p, 16):x}" for p in m.get("unicode", "").split() if int(p, 16) != 0xFE0F)
        by_key[k] = meta.parent.name

    missing = []
    for e in wanted:
        k = key(e)
        folder = by_key.get(k)
        cands = pngs_by_folder.get(folder or "", [])
        # skin-tone emojis: prefer the "Default" tone
        cands.sort(key=lambda p: (0 if "/Default/" in p or p.count("/") == 3 else 1, p))
        if not cands:
            missing.append(e)
            continue
        dest = out / f"{k}.png"
        if not dest.exists():
            urllib.request.urlretrieve(RAW + urllib.request.quote(cands[0]), dest)
    print(f"{len(wanted) - len(missing)} images, missing: {' '.join(missing)}")


if __name__ == "__main__":
    main()
