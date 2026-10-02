"""Reuse the shipped font checker and export its Han set for native Godot checks."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--source-project", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    sandbox = Path(os.environ["GODOT_V014_QA_ROOT"]).resolve(strict=True)
    expected = Path(os.environ["GODOT_V014_QA_PROJECT"]).resolve(strict=True)
    token = os.environ["GODOT_V014_QA_TOKEN"]
    if root != expected or not root.is_relative_to(sandbox) or len(token) != 32:
        raise ValueError("Refusing font output outside the verified disposable project")
    source_project = args.source_project.resolve(strict=True)
    source_root = Path(os.environ["GODOT_V014_QA_SOURCE"]).resolve(strict=True)
    source_hash = hashlib.sha256(source_project.read_bytes()).hexdigest()
    if source_project != source_root / "project.godot" or source_hash != os.environ["GODOT_V014_QA_CONFIG_SHA256"]:
        raise ValueError("Original source project configuration does not match its frozen hash")
    spec = importlib.util.spec_from_file_location("v014_shipped_font_checker", root / "tools/check_font_coverage.py")
    if spec is None or spec.loader is None:
        raise ValueError("Shipped font checker is missing")
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    manifest = json.loads((root / checker.MANIFEST_PATH).read_text(encoding="utf-8"))
    locations, files = checker.collect_required(root, manifest)
    # Isolation changes only the copied project configuration. Replace that
    # configuration's character evidence with the exact original production text.
    for cp in list(locations):
        locations[cp] = {place for place in locations[cp] if not place.startswith("project.godot:")}
        if not locations[cp]:
            del locations[cp]
    for line, text in checker.file_strings(source_project):
        for cp in checker.printable_codepoints(text):
            locations.setdefault(cp, set()).add(f"project.godot:{line}")
    font_path = root / checker.FONT_PATH
    with checker.TTFont(font_path) as font:
        report = checker.check_font(font, set(locations), manifest)
        cmap = font.getBestCmap() or {}
        mapped = sorted(cp for cp, name in cmap.items() if name != ".notdef" and font.getGlyphID(name) != 0)
    report["runtime_files"] = files
    report["source_project_sha256"] = source_hash
    report["font_sha256"] = hashlib.sha256(font_path.read_bytes()).hexdigest()
    report["generation_hash_matches"] = report["font_sha256"] == manifest["generation"]["font_sha256"]
    license_path = root / manifest["license"]["path"]
    report["license_hash_matches"] = hashlib.sha256(license_path.read_bytes()).hexdigest() == manifest["license"]["sha256"]
    report["missing_locations"] = {
        f"U+{cp:04X}": sorted(locations[cp]) for cp in report["missing"]
    }
    report["ok"] = report["ok"] and report["generation_hash_matches"] and report["license_hash_matches"]
    characters = "".join(chr(cp) for cp in sorted(locations) if checker.is_han(cp))
    if not report["ok"] or len(characters) < 700:
        print("V014_FONT_RESULT " + json.dumps(report, ensure_ascii=False))
        return 1
    # The independent PowerShell probe precedes this write. No userdata/save I/O.
    output = root / "tests/windows/v014_required_han.json"
    output.write_text(json.dumps({
        "characters": characters,
        "mapped_characters": "".join(map(chr, mapped)),
        "mapped_han": "".join(chr(cp) for cp in mapped if checker.is_han(cp)),
        "mapped_count": len(mapped),
    }, ensure_ascii=False), encoding="utf-8")
    print("V014_FONT_RESULT " + json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
