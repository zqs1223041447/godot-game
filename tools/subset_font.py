#!/usr/bin/env python3
"""Regenerate the same-font subset while preserving all shipped glyph coverage.

Requires fontTools; the bundled font is enough to run/export the game.
Usage: python tools/subset_font.py /path/to/NotoSansCJK-Regular.ttc
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path

import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont

from check_font_coverage import (
    FONT_PATH, MANIFEST_PATH, ROOT, check_font, collect_required,
    glyph_fingerprint, is_han, layout_metrics,
)


def regenerate(source: Path, root: Path = ROOT, font_number: int = 2) -> dict:
    manifest_path = root / MANIFEST_PATH
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    source_bytes = source.read_bytes()
    if hashlib.sha256(source_bytes).hexdigest() != manifest["source"]["sha256"]:
        raise ValueError("Source SHA256 does not match the recorded, verified Noto CJK source")
    if font_number != manifest["source"]["font_number"]:
        raise ValueError("Source face must be the recorded Simplified Chinese face")
    license_path = root / manifest["license"]["path"]
    if hashlib.sha256(license_path.read_bytes()).hexdigest() != manifest["license"]["sha256"]:
        raise ValueError("Source license must be preserved")
    locations, files = collect_required(root, manifest)
    required = set(locations)
    out = root / FONT_PATH
    with TTFont(out) as previous, TTFont(io.BytesIO(source_bytes), fontNumber=font_number, recalcTimestamp=False) as font:
        retained = set(previous.getBestCmap())
        baseline = set(map(ord, manifest["baseline"]["characters"]))
        requested = (required - set(map(ord, manifest["source_unsupported_symbols"]))) | retained | baseline
        if requested - set(font.getBestCmap()):
            raise ValueError("Verified source lacks requested characters")
        if font["name"].getDebugName(3) != manifest["source"]["version"]:
            raise ValueError("Source version/region changed")
        if layout_metrics(font) != manifest["baseline"]["layout_metrics"]:
            raise ValueError("Source layout metrics differ from the shipped font")
        if glyph_fingerprint(font, baseline) != manifest["baseline"]["glyphs_sha256"]:
            raise ValueError("Source glyphs differ from the frozen baseline")
        if glyph_fingerprint(font, retained) != glyph_fingerprint(previous, retained):
            raise ValueError("Source would change existing glyph outlines/advances")
        options = subset.Options()
        options.name_IDs = ["*"]
        options.name_legacy = True
        options.name_languages = ["*"]
        subsetter = subset.Subsetter(options=options)
        subsetter.populate(unicodes=requested)
        subsetter.subset(font)
        # Keep the existing modified-family name and every license/name record.
        for record in font["name"].names:
            if record.nameID in (1, 4, 6, 16):
                name = "ArenaSansSC-Regular" if record.nameID == 6 else "Arena Sans SC"
                record.string = name.encode(record.getEncoding(), errors="replace")
        font["head"].created = manifest["baseline"]["head_created"]
        font["head"].modified = manifest["baseline"]["head_modified"]
        buffer = io.BytesIO()
        font.save(buffer)
        data = buffer.getvalue()
    # Validate complete output before replacing the shipped binary.
    with TTFont(io.BytesIO(data)) as regenerated:
        report = check_font(regenerated, requested, manifest)
        if not report["ok"]:
            raise ValueError(f"Regenerated font failed coverage/baseline checks: {report}")
    record = {
        "fonttools_version": fontTools.__version__,
        "source_sha256": hashlib.sha256(source_bytes).hexdigest(),
        "font_sha256": hashlib.sha256(data).hexdigest(),
        "font_bytes": len(data),
        "mapped_codepoints": report["mapped_codepoints"],
        "runtime_files": files,
        "required_codepoints": len(required),
        "required_han": sum(map(is_han, required)),
        "added_since_baseline": "".join(map(chr, sorted(requested - baseline))),
        "baseline_glyphs_unchanged": True,
    }
    out.write_bytes(data)
    manifest["generation"] = record
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return record


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--font-number", type=int, default=2, help="SC index in the recorded Noto CJK TTC")
    args = parser.parse_args()
    record = regenerate(args.source, font_number=args.font_number)
    print(json.dumps(record, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
