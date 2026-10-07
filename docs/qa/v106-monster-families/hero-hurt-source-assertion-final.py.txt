#!/usr/bin/env python3
"""New-family raw pixels/manifests and exact source-authority delta audit."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "e2fa6db67fb9c4c7f201c795df12bdeb9b699832"
NEW = ("skitter", "brute", "rift_warden")
VISUAL = ("scripts/visuals/actor_sprite_catalog.gd", "scripts/visuals/actor_visual.gd")
checks = 0
failures = []

def check(ok, label):
    global checks
    checks += 1
    if not ok:
        failures.append(label)
        print("FAIL:", label)

def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])

def sha(data):
    return hashlib.sha256(data).hexdigest()

def audit_sources():
    paths = git("ls-tree", "-r", "--name-only", BASELINE, "scripts", "data", "scenes", "project.godot").decode().splitlines()
    results = {}
    for path in paths:
        before = git("show", BASELINE + ":" + path)
        current = (ROOT / path).read_bytes()
        results[path] = {"baseline_sha256": sha(before), "current_sha256": sha(current)}
        if path not in VISUAL:
            check(before == current, "Authoritative/existing source unchanged: " + path)
    for path in ("assets/actors/hero_atlas.png", "assets/actors/hero_atlas.json", "assets/actors/hero_atlas.png.import", "assets/actors/crawler_atlas.png", "assets/actors/crawler_atlas.json", "assets/actors/crawler_atlas.png.import"):
        before = git("show", BASELINE + ":" + path)
        current = (ROOT / path).read_bytes()
        check(before == current, "Existing v105 resource unchanged: " + path)
        results[path] = {"baseline_sha256": sha(before), "current_sha256": sha(current)}
    baseline_catalog = git("show", BASELINE + ":" + VISUAL[0]).decode()
    current_catalog = (ROOT / VISUAL[0]).read_text()
    check(baseline_catalog.split("static func resource(", 1)[1] == current_catalog.split("static func resource(", 1)[1], "Resource admission, pixel bounds, head anchor and fallback implementation unchanged")
    for function in ("direction_index", "frame_index", "frame_rect"):
        marker = "static func " + function + "("
        old = baseline_catalog.split(marker, 1)[1].split("static func ", 1)[0]
        new = current_catalog.split(marker, 1)[1].split("static func ", 1)[0]
        check(old == new, "Existing frame-selection implementation unchanged: " + function)
    baseline_actor = git("show", BASELINE + ":" + VISUAL[1]).decode()
    current_actor = (ROOT / VISUAL[1]).read_text()
    old_tint = '\t\t\tvar tint := Color(1.22,1.13,1.02) if actor.hurt else Color.WHITE\n'
    # Match the existing v105 tint line verbatim before accepting a delta.
    if old_tint not in baseline_actor:
        old_tint = next((line + "\n" for line in baseline_actor.splitlines() if "var tint" in line), "")
    new_tint = '\t\t\tvar tint: Color = Color.WHITE if actor.is_hero else Catalog.enemy_tint(actor.enemy)\n\t\t\tif actor.hurt: tint = Color(1.22,1.13,1.02) if actor.is_hero else tint.lerp(Color(1.22,1.13,1.02),0.75)\n'
    check(bool(old_tint) and baseline_actor.replace(old_tint, new_tint, 1) == current_actor, "Actor code delta is exclusively family tint with retained hurt feedback")
    return results

def audit_asset(family):
    path = ROOT / "assets/actors" / (family + "_atlas.png")
    manifest_path = path.with_suffix(".json")
    check(path.exists() and manifest_path.exists(), "New PNG and manifest exist: " + family)
    if not path.exists() or not manifest_path.exists():
        return {}
    manifest = json.loads(manifest_path.read_text())
    source_sha = sha(path.read_bytes())
    check(source_sha == manifest.get("atlas_sha256"), "Raw PNG SHA matches render manifest: " + family)
    image = Image.open(path)
    check(image.mode == "RGBA" and image.size == (2048, 1728), "Atlas is actual full-size RGBA: " + family)
    check(manifest.get("frame_width") == 128 and manifest.get("frame_height") == 192 and manifest.get("columns", manifest.get("atlas_columns")) == 16 and manifest.get("frame_count", len(manifest.get("frames", []))) == 144, "Normalized runtime schema is exact: " + family)
    check(manifest.get("direction_order") == ["E", "SE", "S", "SW", "W", "NW", "N", "NE"] and manifest.get("fps") == 12, "Eight directions and 12fps agree: " + family)
    anchor = manifest.get("foot_anchor_px", manifest.get("foot_anchor"))
    check(isinstance(anchor, list) and len(anchor) == 2 and all(isinstance(v, (float, int)) for v in anchor), "Render manifest supplies a numeric family foot: " + family)
    frames = manifest.get("frames", [])
    check(len(frames) == 144, "All 144 frame records exist: " + family)
    merged = None
    partially_transparent = 0
    for index, frame in enumerate(frames):
        phase = index % 18
        clip = "idle" if phase < 4 else "walk" if phase < 12 else "attack"
        local_index = phase if phase < 4 else phase - 4 if phase < 12 else phase - 12
        x, y = (index % 16) * 128, (index // 16) * 192
        tile = image.crop((x, y, x + 128, y + 192))
        alpha = tile.getchannel("A")
        bbox = alpha.getbbox()
        hist = alpha.histogram()
        check(frame.get("index") == index and frame.get("direction") == index // 18 and frame.get("animation") == clip and frame.get("frame", frame.get("animation_frame")) == local_index, f"Direction/clip/frame record agrees: {family}/{index}")
        check(bbox is not None and 0 < bbox[0] < bbox[2] < 128 and 0 < bbox[1] < bbox[3] < 192, f"Nonempty body has transparent margins on four sides: {family}/{index}")
        check(bbox is not None and list(bbox) == frame.get("alpha_bounds_px", frame.get("alpha_bounds")), f"Raw alpha pixels exactly match declared bounds: {family}/{index}")
        check(hist[0] > 0 and hist[255] > 0 and sum(hist[1:255]) > 0, f"Real transparent background and antialiased silhouette: {family}/{index}")
        if "anchor_px" in frame:
            check(frame["anchor_px"] == anchor, f"Per-frame render foot is stable: {family}/{index}")
        if bbox:
            merged = bbox if merged is None else (min(merged[0], bbox[0]), min(merged[1], bbox[1]), max(merged[2], bbox[2]), max(merged[3], bbox[3]))
        partially_transparent += sum(hist[1:255])
    declared_union = manifest.get("all_frame_alpha_bounds_px")
    if declared_union is not None:
        check(list(merged) == declared_union, "All-frame alpha union agrees: " + family)
    return {"sha256": source_sha, "frames": len(frames), "alpha_bounds": merged, "foot_anchor": anchor, "antialiased_pixels": partially_transparent}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", nargs="+", choices=NEW, default=list(NEW))
    parser.add_argument("--skip-sources", action="store_true")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    source_results = {} if args.skip_sources else audit_sources()
    resources = {key: audit_asset(key) for key in args.assets}
    result = {"baseline": BASELINE, "checks": checks, "failures": len(failures), "first_failure": failures[0] if failures else "", "failure_labels": failures, "sources": source_results, "resources": resources}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(f"Monster family source/raw-pixel v106: {checks} checks, {len(failures)} failures")
    raise SystemExit(bool(failures))

if __name__ == "__main__":
    main()
