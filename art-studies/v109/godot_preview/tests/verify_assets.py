#!/usr/bin/env python3
"""Read-only asset/foot checks. Never rewrites any source PNG or collision data."""
from pathlib import Path
import hashlib
import json
import argparse
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source-env", type=Path, help="Optional original environment export directory")
parser.add_argument("--source-character", type=Path, help="Optional original character/font directory")
parser.add_argument("--report", type=Path, help="Write a new report; original QA evidence is retained")
options = parser.parse_args()
SOURCE_ENV = options.source_env
SOURCE_CHARACTER = options.source_character
SOURCE_HASHES = json.loads((ROOT / "qa/input-sha256.json").read_text())
checks = []


def check(name, passed, detail=None):
    checks.append({"name": name, "passed": bool(passed), "detail": detail})
    print(("PASS " if passed else "FAIL ") + name)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_sha(relative, source_root, original_relative):
    if source_root is not None:
        return sha(source_root / original_relative)
    # Frozen original source hashes, not hashes computed from the archive input.
    return SOURCE_HASHES[relative]


manifest_path = ROOT / "assets/environment/runtime-manifest.json"
manifest = json.loads(manifest_path.read_text())
check("runtime_manifest_copied_byte_for_byte", sha(manifest_path) == source_sha("assets/environment/runtime-manifest.json", SOURCE_ENV, manifest_path.name))
for name in ("arena_sans.otf", "hero_direction_study.png"):
    check(name + "_source_bytes_preserved", sha(ROOT / "assets" / name) == source_sha("assets/" + name, SOURCE_CHARACTER, name))

empty_layers = []
for entry in manifest["layers"]:
    destination = ROOT / "assets/environment" / entry["image"]
    source_digest = source_sha("assets/environment/" + entry["image"], SOURCE_ENV, entry["image"])
    with Image.open(destination) as im:
        check(entry["id"] + "_png_contract", im.mode == "RGBA" and list(im.size) == entry["image_size_pixel"] and sha(destination) == source_digest)
        alpha_bounds = im.getchannel("A").getbbox()
        if alpha_bounds is None:
            empty_layers.append(entry["id"])
        check(entry["id"] + "_visibility_contract", bool(alpha_bounds) == entry["visible_in_original"])
check("exactly_two_hidden_layers", empty_layers == ["arch_07", "rock_11"], empty_layers)

# Matches the eight existing illustrations selected by player.gd.
regions = [(i * 384, 0, 384, 480) for i in range(4)] + [(i * 384, 488, 384, 512) for i in range(4)]
feet = [(206, 470), (205, 470), (210, 467), (211, 471), (174, 479), (172, 473), (191, 479), (190, 484)]
directions = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
foot_report = []
with Image.open(ROOT / "assets/hero_direction_study.png") as atlas:
    check("original_atlas_dimensions", atlas.size == (1536, 1024))
    for direction, (x, y, w, h), foot in zip(directions, regions, feet):
        alpha = atlas.crop((x, y, x+w, y+h)).getchannel("A")
        # Reading crop regions is a test only, not image asset generation.
        bounds = alpha.point(lambda a: 255 if a >= 128 else 0).getbbox()
        foot_gap = (foot[1] - (bounds[3] - 1)) * 0.115
        height = (bounds[3] - bounds[1]) * 0.115
        item = {"direction": direction, "source_rect": [x, y, w, h], "foot_local": foot, "opaque_bounds": bounds, "foot_gap_pixel": foot_gap, "visible_height_pixel": height}
        foot_report.append(item)
        check(direction + "_whole_figure_and_ground_baseline", bounds[1] > 0 and bounds[3] < h and abs(foot_gap) < 0.8 and 47 <= height <= 55, item)
check("height_consistency_under_4px", max(r["visible_height_pixel"] for r in foot_report) - min(r["visible_height_pixel"] for r in foot_report) < 4)

failures = sum(not c["passed"] for c in checks)
report = {"passed": failures == 0, "failures": failures, "checks": checks, "direction_feet": foot_report, "limitations": ["Illustration identity, pose quality and direction generation errors are not repaired or accepted here", "No animated frames; no screenshot/FPS/full-game acceptance"]}
report_path = (options.report or ROOT / "qa/asset-recheck.json").resolve()
if report_path == (ROOT / "qa/asset-verification.json").resolve():
    raise ValueError("Choose a new report path; preserve the original 74-check evidence")
report["source_comparison_mode"] = "original directories where supplied; otherwise frozen original input-sha256"
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(f"RESULT: {len(checks)} checks, {failures} failures")
raise SystemExit(1 if failures else 0)
