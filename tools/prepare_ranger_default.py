#!/usr/bin/env python3
"""Copy the verified v126 atlas unchanged into the runtime resource directory."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art-studies/v126"
OUTPUT = ROOT / "assets/actors"
records = {row["path"]: row for row in json.loads((SOURCE / "MANIFEST.json").read_text())["files"]}
for name in ["atlas/ranger_v126.png", "atlas/ranger_v126.json"]:
    assert hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() == records[name]["sha256"]
definition = json.loads((SOURCE / "atlas/ranger_v126.json").read_text())
assert definition["direction_count"] == 8 and definition["frames_per_direction"] == 45
assert definition["fps"] == 12 and definition["clips"] == {"idle": [0, 30], "walk": [30, 9], "attack": [39, 6]}
shutil.copyfile(SOURCE / "atlas/ranger_v126.png", OUTPUT / "ranger_v126.png")
definition["texture_path"] = "res://assets/actors/ranger_v126.png"
(OUTPUT / "ranger_v126.json").write_text(json.dumps(definition, indent=2) + "\n")
assert (OUTPUT / "ranger_v126.png").read_bytes() == (SOURCE / "atlas/ranger_v126.png").read_bytes()
print("Copied unchanged v126 PNG; runtime metadata differs only in texture_path.")
