"""Runs ZIPA on every <name>.fb (float32 fbank, 80 bins) listed in index.json.

Writes <name>.lp (float32 log-probs) and <name>.shape ("T V").
Usage: python infer.py <work dir> <model.onnx>
"""

import json
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort

work, model = Path(sys.argv[1]), sys.argv[2]
sess = ort.InferenceSession(model, providers=["CPUExecutionProvider"])
names = [o.name for o in sess.get_outputs()]
key = next((n for n in ("log_probs", "logits") if n in names), names[0])
for item in json.loads((work / "index.json").read_text(encoding="utf-8")):
    f = work / item["file"]
    feats = np.fromfile(f.with_suffix(".fb"), dtype=np.float32).reshape(1, -1, 80)
    if feats.shape[1] < 10:
        continue
    out = sess.run([key], {"x": feats, "x_lens": np.array([feats.shape[1]], dtype=np.int64)})[0]
    out[0].astype(np.float32).tofile(f.with_suffix(".lp"))
    f.with_suffix(".shape").write_text(f"{out.shape[1]} {out.shape[2]}")
