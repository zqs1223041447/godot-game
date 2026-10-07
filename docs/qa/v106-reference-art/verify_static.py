#!/usr/bin/env python3
"""Read-only JSON/HTML/hash checks; no image generation or editing."""
from hashlib import sha256
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
QA = ROOT / "docs/qa/v106-reference-art"
BEFORE = json.loads((QA / "before.json").read_text())
BASELINE = BEFORE["baseline_commit"]
checks = {}


def digest(data):
    return sha256(data).hexdigest()


def check(name, condition):
    checks[name] = bool(condition)


def baseline(path):
    return subprocess.check_output(["git", "show", f"{BASELINE}:{path}"], cwd=ROOT)


def current(path):
    return (ROOT / path).read_bytes()


class Images(HTMLParser):
    def __init__(self):
        super().__init__()
        self.paths = []

    def handle_starttag(self, tag, attrs):
        if tag == "img":
            self.paths.append(dict(attrs)["src"])


for group in ["protected_reference_files", "source_atlases", "frozen_production_files"]:
    for path, old_hash in BEFORE[group].items():
        check(f"unchanged:{path}", digest(current(path)) == old_hash)

catalog = "docs/reference/catalog.json"
check("catalog_exact_baseline_bytes", current(catalog) == baseline(catalog))
html_path = "docs/reference/index.html"
old_html = baseline(html_path)
new_html = current(html_path)
expected_html = old_html
placeholder = '<span class="fallback-emblem" aria-hidden="true">✧</span>'
replacements = []
for template in ["mist_skitter", "chaos_guard"]:
    prefix = f'<article class="entry" id="monsters-{template}" data-category="monsters" tabindex="-1"><div class="entry-heading">'
    image = f'<img class="emblem" src="art/monsters/{template}.png" width="64" height="64" alt="" loading="lazy">'
    old = (prefix + placeholder).encode()
    new = (prefix + image).encode()
    check(f"one_old_placeholder:{template}", old_html.count(old) == 1)
    check(f"one_new_header:{template}", new_html.count(new) == 1)
    expected_html = expected_html.replace(old, new)
    replacements.append({"template": template, "before": placeholder, "after": image})
check("html_only_two_exact_card_header_replacements", new_html == expected_html)
for tag in ["style", "script"]:
    pattern = rb"<" + tag.encode() + rb"\b[^>]*>.*?</" + tag.encode() + rb">"
    check(f"all_{tag}_blocks_exact_baseline_bytes", re.findall(pattern, new_html, re.S) == re.findall(pattern, old_html, re.S))

manifest_path = "docs/reference/art/manifest.json"
old_manifest_bytes = baseline(manifest_path)
new_manifest_bytes = current(manifest_path)
old_manifest = json.loads(old_manifest_bytes)
manifest = json.loads(new_manifest_bytes)
old_nonmonsters = [e for e in old_manifest["entries"] if e["category"] != "monsters"]
new_nonmonsters = [e for e in manifest["entries"] if e["category"] != "monsters"]
check("nonmonster_manifest_entries_content_unchanged", old_nonmonsters == new_nonmonsters)
start_marker = b'\t"entries": [\n'
stop_marker = b'\t\t{\n\t\t\t"category": "monsters",'
entry_bytes = lambda data: data[data.index(start_marker):data.index(stop_marker)]
check("nonmonster_manifest_entries_exact_baseline_bytes", entry_bytes(old_manifest_bytes) == entry_bytes(new_manifest_bytes))
for key, value in old_manifest.items():
    if key not in ["entries", "counts", "written_images"]:
        check(f"legacy_manifest_value_unchanged:{key}", manifest[key] == value)
check("nonmonster_manifest_counts_unchanged", all(manifest["counts"][k] == v for k, v in old_manifest["counts"].items() if k != "monsters"))
check("legacy_image_size_explicit_override", "legacy default" in manifest["image_size_scope"] and "entry.image_size overrides" in manifest["image_size_scope"])
check("legacy_capture_explicit_scope", "non-monster" in manifest["capture_scope"] and "monster_capture" in manifest["capture_scope"])

exports = json.loads((QA / "export.json").read_text())
verified = json.loads((QA / "verify.json").read_text())
monsters = [e for e in manifest["entries"] if e["category"] == "monsters"]
source_templates = (ROOT / "scripts/monsters/monster_catalog.gd").read_text().split("const TEMPLATES: Dictionary = {", 1)[1].split("\n}\n", 1)[0]
template_ids = sorted(re.findall(r'^\t"([a-z_]+)": \{', source_templates, re.M))
check("all_authoritative_templates_present_once", sorted(e["id"] for e in monsters) == template_ids and len(monsters) == 11)
check("four_expected_families", {e["family"] for e in monsters} == {"crawler", "skitter", "brute", "rift_warden"})
check("manifest_matches_direct_runtime_authority", monsters == verified["entries"] == exports["entries"])
check("all_png_checks_passed", all(verified[k] == v for k, v in {"status": "pass", "template_count": 11, "family_count": 4, "source_atlases_unchanged": True}.items()) and all(c["format"] == "RGBA8" and c["nonempty_pixels"] > 0 and all(c[k] for k in ["core_pixels_equal_source", "complete_image_equals_expected", "transparent_border_8px", "used_bounds_match"]) for c in verified["checks"]))
check("all_source_frame_contracts_match", all(e["source_frame"] == {"direction_index": 2, "direction": "south", "animation": "idle", "seconds": 0, "frame_index": 36} and e["source_frame_rect"] == [512, 384, 128, 192] and e["transparent_border_px"] == 8 and e["tint_applied"] is False for e in monsters))
check("exactly_four_distinct_source_frame_images", len({c["png_sha256"] for c in verified["checks"]}) == 4)
check("all_counts_match_actual_entries", manifest["counts"]["monsters"] == 11 and manifest["written_images"] == len(manifest["entries"]) == 66)
check("all_manifest_image_paths_exist", all((ROOT / "docs/reference/art" / e["file"]).is_file() for e in manifest["entries"]))
parser = Images()
parser.feed(new_html.decode())
missing = [p for p in parser.paths if not (ROOT / "docs/reference" / p).is_file()]
check("all_html_image_links_exist", not missing)
check("all_eleven_monster_cards_link_images", all(parser.paths.count("art/" + e["file"]) == 1 for e in monsters))
check("exactly_eleven_monster_pngs", sorted(p.stem for p in (ROOT / "docs/reference/art/monsters").glob("*.png")) == template_ids)

report = {
    "status": "pass" if all(checks.values()) else "fail",
    "baseline_commit": BASELINE,
    "checks_passed": sum(checks.values()), "checks_total": len(checks), "checks": checks,
    "catalog_sha256": digest(current(catalog)), "catalog_baseline_sha256": digest(baseline(catalog)),
    "protected_reference_files": len(BEFORE["protected_reference_files"]),
    "nonmonster_manifest_entries": len(new_nonmonsters), "html_image_links_checked": len(parser.paths),
    "missing_html_images": missing, "html_replacements": replacements,
    "source_atlas_sha256": BEFORE["source_atlases"],
    "frozen_production_file_sha256": BEFORE["frozen_production_files"],
    "scope": "JSON, HTML, links and SHA256 only. PNG pixel checks performed by Godot verify-only mode.",
}
(QA / "static-verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(f"STATIC_REFERENCE_ART_{report['status'].upper()}: {report['checks_passed']}/{report['checks_total']} checks; {len(monsters)} monster cards, {len(parser.paths)} image links")
for key, value in checks.items():
    if not value:
        print("FAIL:", key)
raise SystemExit(0 if all(checks.values()) else 1)
