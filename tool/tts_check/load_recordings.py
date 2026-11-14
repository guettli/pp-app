"""Uses real recordings instead of synthesized speech.

<rec dir>/recordings.json: [{"lang", "voice", "p", "e", "ipa", "src"}], src
is an audio file next to it (FLAC/WAV, any rate). Writes the same layout as
synth.py.
Usage: python load_recordings.py <rec dir> <out dir>
"""

import json
import sys
from math import gcd
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

rec, out = map(Path, sys.argv[1:3])
index = []
for n, item in enumerate(json.loads((rec / "recordings.json").read_text(encoding="utf-8"))):
    audio, sr = sf.read(rec / item.pop("src"), dtype="float32", always_2d=True)
    audio = audio.mean(axis=1)
    g = gcd(16000, sr)
    audio = resample_poly(audio, 16000 // g, sr // g).astype(np.float32)
    f = f"{item['lang']}/rec/{n}.f32"
    (out / f).parent.mkdir(parents=True, exist_ok=True)
    (out / f).write_bytes(audio.tobytes())
    index.append({**item, "file": f})
(out / "index.json").write_text(json.dumps(index, ensure_ascii=False), encoding="utf-8")
