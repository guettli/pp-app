"""Speaks every word of assets/phrases/*.json with Piper voices.

Writes <out>/<lang>/<voice>/<n>.f32 (16 kHz mono float32, with silence
around the word like a real recording) and <out>/index.json.
Usage: python synth.py <phrases dir> <voices dir> <out dir>
"""

import json
import os
import sys
from math import gcd
from pathlib import Path

import numpy as np
from piper import PiperVoice
from scipy.signal import resample_poly

phrases, voices, out = map(Path, sys.argv[1:4])
# experiment knobs: TTS_OPTIONS="gain=0.6 lead=0.4 tail=0.8 noise=0.002"
opt = {"gain": 0.6, "lead": 0.4, "tail": 0.8, "noise": 0.002}
for kv in os.environ.get("TTS_OPTIONS", "").split():
    k, v = kv.split("=")
    opt[k] = float(v)
index = []
for onnx in sorted(voices.glob("*.onnx")):
    voice_name = onnx.stem  # e.g. de_DE-thorsten-medium
    lang = voice_name.split("-")[0].replace("_", "-")
    words = json.loads((phrases / f"{lang}.json").read_text(encoding="utf-8"))
    voice = PiperVoice.load(str(onnx))
    d = out / lang / voice_name
    d.mkdir(parents=True, exist_ok=True)
    for n, w in enumerate(words):
        chunks = list(voice.synthesize(w["p"]))
        sr = chunks[0].sample_rate
        audio = np.concatenate([c.audio_float_array for c in chunks])
        g = gcd(16000, sr)
        audio = resample_poly(audio, 16000 // g, sr // g).astype(np.float32)
        # reaction time before, trailing silence after (as the endpointer
        # leaves it); a little noise so it is not digital silence
        rng = np.random.default_rng(n)
        pad = lambda s: (rng.standard_normal(int(16000 * s)) * opt["noise"]).astype(np.float32)
        audio = np.concatenate([pad(opt["lead"]), audio * opt["gain"], pad(opt["tail"])])
        (d / f"{n}.f32").write_bytes(audio.tobytes())
        index.append({"lang": lang, "voice": voice_name, "file": f"{lang}/{voice_name}/{n}.f32",
                      "p": w["p"], "e": w["e"], "ipa": w["ipa"]})
    print(voice_name, len(words), "words", file=sys.stderr)
(out / "index.json").write_text(json.dumps(index, ensure_ascii=False), encoding="utf-8")
