#!/usr/bin/env python3
"""Check the bundled font against runtime strings and its frozen coverage baseline.

Requires fontTools. Runs offline and does not rely on installed fallback fonts.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import re
import subprocess
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.ttLib import TTFont, TTLibError

ROOT = Path(__file__).resolve().parents[1]
FONT_PATH = Path("assets/fonts/arena_sans.otf")
MANIFEST_PATH = Path("assets/fonts/coverage_manifest.json")
TEXT_SUFFIXES = {".gd", ".tscn", ".tres", ".godot", ".json", ".csv"}
ESCAPES = dict(zip('ntrabfv"\'\\', '\n\t\r\a\b\f\v"\'\\'))


def string_literals(source: str, comments: str = "#") -> list[tuple[int, str]]:
    """Lex GDScript/resource strings, skipping comments and decoding escapes.

    Also handles raw/triple strings, StringNames, NodePaths and surrogate pairs.
    Malformed/unknown escapes fail rather than silently hiding a needed glyph.
    """
    result = []
    index, line = 0, 1
    while index < len(source):
        char = source[index]
        if char in comments:
            end = source.find("\n", index)
            index = len(source) if end < 0 else end
            continue
        if char not in "\"'":
            line += char == "\n"
            index += 1
            continue
        start_line = line
        raw = index > 0 and source[index - 1] == "r" and (
            index == 1 or not (source[index - 2].isalnum() or source[index - 2] == "_")
        )
        quote = char * (3 if source.startswith(char * 3, index) else 1)
        index += len(quote)
        parts = []
        while index < len(source) and not source.startswith(quote, index):
            char = source[index]
            if char == "\\":
                if index + 1 >= len(source):
                    raise ValueError(f"Unterminated escape at line {line}")
                escaped = source[index + 1]
                if raw:
                    parts.append(source[index:index + 2])
                    line += escaped == "\n"
                    index += 2
                    continue
                if escaped in "uU":
                    length = 4 if escaped == "u" else 6
                    digits = source[index + 2:index + 2 + length]
                    if len(digits) != length or not re.fullmatch("[0-9a-fA-F]+", digits):
                        raise ValueError(f"Invalid Unicode escape at line {line}")
                    parts.append(chr(int(digits, 16)))
                    index += 2 + length
                    continue
                if escaped == "\n":
                    line += 1
                elif escaped in ESCAPES:
                    parts.append(ESCAPES[escaped])
                else:
                    raise ValueError(f"Unknown escape \\{escaped} at line {line}")
                index += 2
                continue
            parts.append(char)
            line += char == "\n"
            index += 1
        if index >= len(source):
            raise ValueError(f"Unterminated string at line {start_line}")
        index += len(quote)
        text = "".join(parts).encode("utf-16-le", "surrogatepass").decode("utf-16-le")
        result.append((start_line, text))
    return result


def json_strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield key
            yield from json_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from json_strings(item)


def file_strings(path: Path) -> list[tuple[int, str]]:
    text = path.read_text(encoding="utf-8-sig")
    if path.suffix == ".json":
        return [(1, item) for item in json_strings(json.loads(text))]
    if path.suffix == ".csv":
        return [(line, cell) for line, row in enumerate(csv.reader(io.StringIO(text)), 1) for cell in row]
    return string_literals(text, "#" if path.suffix == ".gd" else "#;")


def runtime_paths(root: Path) -> list[Path]:
    paths = [root / "project.godot"]
    for folder in ("scripts", "scenes", "data", "assets"):
        base = root / folder
        for path in base.rglob("*"):
            if not path.is_file() or path.suffix not in TEXT_SUFFIXES:
                continue
            if folder == "assets" and path.suffix in {".json", ".csv"}:
                continue  # Asset generation metadata/font records are not UI text.
            if any((parent / ".gdignore").exists() for parent in path.parents if parent == base or base in parent.parents):
                continue
            paths.append(path)
    return sorted(paths)


def is_han(codepoint: int) -> bool:
    return unicodedata.name(chr(codepoint), "").startswith(("CJK UNIFIED IDEOGRAPH", "CJK COMPATIBILITY IDEOGRAPH"))


def printable_codepoints(text: str) -> set[int]:
    return {ord(char) for char in text if char.isprintable()}


def collect_required(root: Path, manifest: dict) -> tuple[dict[int, set[str]], int]:
    locations = defaultdict(set)
    paths = runtime_paths(root)
    for path in paths:
        for line, text in file_strings(path):
            for codepoint in printable_codepoints(text):
                locations[codepoint].add(f"{path.relative_to(root)}:{line}")
    for source in manifest["supplemental_sources"]:
        for item in source["strings"]:
            for codepoint in printable_codepoints(item["text"]):
                locations[codepoint].add(f"{source['commit']}:{source['path']}:{item['line']}")
    return dict(locations), len(paths)


def glyph_fingerprint(font: TTFont, codepoints: set[int]) -> str:
    """Hash decomposed outlines and advances, independent of glyph reindexing."""
    cmap, glyphs = font.getBestCmap(), font.getGlyphSet()
    records = []
    for codepoint in sorted(codepoints):
        name = cmap[codepoint]
        pen = DecomposingRecordingPen(glyphs)
        glyphs[name].draw(pen)
        vertical = font["vmtx"][name] if "vmtx" in font else None
        origin = font["VORG"].VOriginRecords.get(name, font["VORG"].defaultVertOriginY) if "VORG" in font else None
        records.append((codepoint, pen.value, font["hmtx"][name], vertical, origin))
    return hashlib.sha256(json.dumps(records, separators=(",", ":")).encode()).hexdigest()


def layout_metrics(font: TTFont) -> dict:
    return {
        "unitsPerEm": font["head"].unitsPerEm,
        "hhea": [getattr(font["hhea"], key) for key in ("ascent", "descent", "lineGap")],
        "vhea": [getattr(font["vhea"], key) for key in ("ascent", "descent", "lineGap")],
        "OS/2": [getattr(font["OS/2"], key) for key in ("sTypoAscender", "sTypoDescender", "sTypoLineGap", "usWinAscent", "usWinDescent", "sxHeight", "sCapHeight")],
    }


def check_font(font: TTFont, required: set[int], manifest: dict) -> dict:
    cmap = font.getBestCmap() or {}
    mapped = {cp for cp, name in cmap.items() if name != ".notdef" and font.getGlyphID(name) != 0}
    baseline = set(map(ord, manifest["baseline"]["characters"]))
    fallback_symbols = set(map(ord, manifest["source_unsupported_symbols"]))
    if any(is_han(cp) for cp in fallback_symbols):
        raise ValueError("Chinese characters cannot be exempted from coverage")
    missing, lost = required - mapped - fallback_symbols, baseline - mapped
    empty = set()
    glyphs = font.getGlyphSet()
    for codepoint in required & mapped:
        if is_han(codepoint):
            pen = DecomposingRecordingPen(glyphs)
            glyphs[cmap[codepoint]].draw(pen)
            if not any(op in ("lineTo", "curveTo", "qCurveTo") for op, _ in pen.value):
                empty.add(codepoint)
    errors = []
    if not lost and glyph_fingerprint(font, baseline) != manifest["baseline"]["glyphs_sha256"]:
        errors.append("Existing glyph outlines/advances changed")
    if layout_metrics(font) != manifest["baseline"]["layout_metrics"]:
        errors.append("Font layout metrics changed")
    if font["name"].getDebugName(1) != "Arena Sans SC" or font["name"].getDebugName(6) != "ArenaSansSC-Regular":
        errors.append("Font family changed")
    return {
        "mapped_codepoints": len(mapped),
        "required_codepoints": len(required),
        "required_han": sum(map(is_han, required)),
        "baseline_codepoints": len(baseline),
        "fallback_symbols": sorted((required - mapped) & fallback_symbols),
        "missing": sorted(missing), "lost_baseline": sorted(lost), "empty_han": sorted(empty),
        "errors": errors,
        "ok": not (missing or lost or empty or errors),
    }


def verify_supplemental(root: Path, manifest: dict) -> None:
    """Explicit opt-in: verify the frozen strings against their exact Git blobs."""
    for source in manifest["supplemental_sources"]:
        data = subprocess.check_output(["git", "show", f"{source['commit']}:{source['path']}"], cwd=root)
        if hashlib.sha256(data).hexdigest() != source["blob_sha256"]:
            raise ValueError(f"Supplemental blob changed: {source['path']}")
        strings = [{"line": line, "text": text} for line, text in string_literals(data.decode()) if any(is_han(ord(char)) for char in text)]
        if strings != source["strings"]:
            raise ValueError(f"Supplemental string record is incomplete: {source['path']}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--font", type=Path, help="Check another font (e.g. the pre-fix baseline)")
    parser.add_argument("--json", action="store_true", help="Print a machine-readable report")
    parser.add_argument("--verify-supplemental", action="store_true", help="Verify recorded crafting strings against local Git objects")
    parser.add_argument("--strict-symbols", action="store_true", help="Also fail for documented, pre-existing same-source symbol gaps")
    args = parser.parse_args(argv)
    try:
        manifest = json.loads((args.root / MANIFEST_PATH).read_text(encoding="utf-8"))
        if args.verify_supplemental:
            verify_supplemental(args.root, manifest)
        locations, files = collect_required(args.root, manifest)
        with TTFont(args.font or args.root / FONT_PATH) as font:
            report = check_font(font, set(locations), manifest)
        if args.strict_symbols and report["fallback_symbols"]:
            report["ok"] = False
        license_path = args.root / manifest["license"]["path"]
        if hashlib.sha256(license_path.read_bytes()).hexdigest() != manifest["license"]["sha256"]:
            report["errors"].append("Bundled source license changed or missing")
            report["ok"] = False
        report["runtime_files"] = files
        report["missing_locations"] = {f"U+{cp:04X}": sorted(locations[cp]) for cp in report["missing"]}
    except (OSError, ValueError, KeyError, TTLibError, subprocess.CalledProcessError) as error:
        print(f"Font coverage check failed: {error}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(f"Font coverage: {report['required_han']} Han / {report['required_codepoints']} printable characters in {files} runtime files + pinned crafting strings; {report['mapped_codepoints']} mapped; {report['baseline_codepoints']} baseline characters retained")
        for kind in ("missing", "lost_baseline", "empty_han"):
            for cp in report[kind]:
                print(f"{kind}: {chr(cp)!r} U+{cp:04X}")
                for location in sorted(locations.get(cp, ())):
                    print(f"  {location}")
        for error in report["errors"]:
            print(error)
        if report["fallback_symbols"]:
            print("Same-source unsupported symbols (existing fallback): " + " ".join(f"{chr(cp)} U+{cp:04X}" for cp in report["fallback_symbols"]))
        print("PASS" if report["ok"] else "FAIL")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
