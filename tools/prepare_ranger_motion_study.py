#!/usr/bin/env python3
"""Pack the unchanged authored east frames; no rendering or pose correction."""
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art-studies/v125"
OUTPUT = ROOT / "assets/actors/studies"
metadata = json.loads((SOURCE / "reports/trial-metadata.json").read_text())
records = {row["path"]: row for row in json.loads((SOURCE / "MANIFEST.json").read_text())["files"]}
frames = metadata["variants"]["candidate"]["frames"]
assert len(frames) == 16 and metadata["blend"]["walk_weight"] == 0.8 and metadata["blend"]["jog_weight"] == 0.2
atlas = Image.new("RGBA", (128 * 16, 192))
for index, path in enumerate(frames):
    raw = (SOURCE / path).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == records[path]["sha256"]
    with Image.open(SOURCE / path) as frame:
        assert frame.mode == "RGBA" and frame.size == (128, 192)
        atlas.paste(frame, (index * 128, 0))
        assert atlas.crop((index * 128, 0, (index + 1) * 128, 192)).tobytes() == frame.tobytes()
OUTPUT.mkdir(parents=True, exist_ok=True)
atlas.save(OUTPUT / "ranger_v125_east.png")
definition = {
    "schema_version": 1,
    "coordinate_space": "world",
    "texture_path": "res://assets/actors/studies/ranger_v125_east.png",
    "direction_count": 1,
    "world_units_per_source_pixel": 1 / (2 * 0.65),
    "frames_per_direction": 16,
    "fps": 16 / metadata["variants"]["candidate"]["cycle_seconds"],
    "clips": {"idle": [0, 1], "walk": [0, 16]},
    "frames": [{"region": [i * 128, 0, 128, 192], "foot": [64, 158]} for i in range(16)],
    "contact_shadow_half_size_world": [32, 10],
    "provenance": {
        "source_commit": "1cd353b68be4f45922de8de31ba4fff93252dc36",
        "source": "art-studies/v125",
        "heading": "screen_right_only",
        "cycle_seconds": metadata["variants"]["candidate"]["cycle_seconds"],
        "walk_weight": 0.8,
        "jog_weight": 0.2,
        "idle_policy": "hold locomotion frame zero; no authored Idle art",
        "attack_policy": "hold locomotion frame zero; no authored Attack art",
        "sources_and_licenses": "art-studies/v125/SOURCES.md",
    },
}
(OUTPUT / "ranger_v125_east.json").write_text(json.dumps(definition, indent=2) + "\n")
print("Packed 16 unchanged RGBA regions, one east heading, 128x192 source cells.")
