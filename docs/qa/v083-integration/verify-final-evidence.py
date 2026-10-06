"""Read existing v83 evidence and compare hashes; never launch Godot or rebuild F8."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).with_name("source-evidence-audit.json")
BASE = "f18cf07fdd15355766e2b762a8bb0af3a4e7bb04"
STAGE = "dce0c7718ca60cd258fc356227efeeae8f9048b2"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    return json.loads((ROOT / path).read_text())


matches = {}
for line in (ROOT / "docs/qa/v083-layout/inputs.sha256.txt").read_text().splitlines():
    expected, path = line.split(None, 1)
    matches[path] = expected
for path, expected in read("docs/qa/v083-save/tested-input-sha256.json").items():
    assert path not in matches or matches[path] == expected, path
    matches[path] = expected
runtime_export = read("docs/qa/v083-reference/corrected-ginkgo-fragment-input-sha256.json")
for path, expected in runtime_export.items():
    if path.startswith(("scripts/", "data/")) or path == "project.godot":
        assert path not in matches or matches[path] == expected, path
        matches[path] = expected
for path, expected in matches.items():
    assert sha((ROOT / path).read_bytes()) == expected, path

final_docs = read("docs/qa/v083-reference/final-files-sha256.json")["files_sha256"]
for path, expected in final_docs.items():
    assert sha((ROOT / path).read_bytes()) == expected, path
main_evidence = read("docs/qa/v083-gameplay/acceptance.json")
for path, expected in main_evidence["files_sha256"].items():
    assert sha((ROOT / "docs/qa/v083-gameplay/results" / path).read_bytes()) == expected, path

unchanged = {}
for path in ["scripts/main.gd", "scripts/monsters/monster_runtime.gd",
             "scripts/combat/burn_runtime.gd", "scripts/combat/shock_runtime.gd",
             "scripts/combat/freeze_runtime.gd", "scripts/passives/source_tree_runtime.gd",
             "scripts/passives/source_stat_patterns.gd", "scripts/items/equipment_catalog.gd"]:
    old = subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT)
    current = (ROOT / path).read_bytes()
    assert old == current, path
    unchanged[path] = sha(current)
stage_paths = subprocess.check_output(["git", "diff", "--name-only", BASE, STAGE], cwd=ROOT, text=True).splitlines()
stage_files = {}
for path in stage_paths:
    if path.startswith(("scripts/", "assets/")) or path == "project.godot":
        old = subprocess.check_output(["git", "show", f"{STAGE}:{path}"], cwd=ROOT)
        assert old == (ROOT / path).read_bytes(), path
        stage_files[path] = sha(old)
font = read("docs/qa/v083-integration/font-final-check.json")
assert font["ok"] and sha((ROOT / "assets/fonts/arena_sans.otf").read_bytes()) == font["font_sha256"]
assert read("docs/qa/v083-save/save-report.json")["failures"] == 0
assert read("docs/qa/v083-gameplay/results/main-result.json")["failures"] == 0
report = {
    "ok": True, "baseline": BASE, "backed_production_stage": STAGE,
    "matched_tested_or_exported_inputs": matches,
    "matched_reference_files": len(final_docs), "matched_main_receipt_files": len(main_evidence["files_sha256"]),
    "production_unchanged_since_stage": stage_files, "unchanged_shared_runtime": unchanged,
    "functional_checks": {"layout": 38219, "save": 199, "main_stdout": 213, "visual_rules": 10, "total": 38641},
    "main_json_count_boundary": "212 before the final successful report-file-open check; stdout 213.",
    "structural_receipt_checks": 52, "font": font,
    "native_visual_review": "pending; startup readiness alone is not a visual result",
    "godot_rerun": False, "reference_rebuild": False,
}
OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"ok": True, "input_count": len(matches), "reference_files": len(final_docs), "stage_files": len(stage_files), "report": str(OUT.relative_to(ROOT))}))
