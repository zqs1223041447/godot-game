#!/usr/bin/env python3
"""Run bounded v75 integration after the shared import gate.

The runner never invokes editor/import. Each attempt keeps its raw log and result;
--section retries only affected sections, and aggregate counts count each section
once. Test saves live in disposable /tmp/godot-m1-v075-* XDG roots.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs/qa/v075-integration-tests"
SECTIONS = ("registry", "sampling", "camps", "arithmetic_maps", "special_lineages",
            "cache_transactions", "main_adoption", "combat_consumers")
RUNTIME_DIRS = ("scripts", "data", "scenes", "assets", "fonts", "audio", "shaders")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot() -> dict[str, str]:
    paths = [ROOT / "project.godot"]
    for directory in RUNTIME_DIRS:
        folder = ROOT / directory
        if folder.exists():
            paths.extend(path for path in folder.rglob("*") if path.is_file())
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted(paths)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--section", action="append", choices=SECTIONS,
                        help="Run only the named section; may be repeated")
    args = parser.parse_args()
    selected = list(dict.fromkeys(args.section or SECTIONS))
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((EVIDENCE / "frozen/manifest.json").read_text())
    for item in manifest["files"]:
        fixture = ROOT / item["fixture"]
        assert digest(fixture) == item["fixture_sha256"], f"Changed frozen fixture: {fixture}"
        original = fixture.with_suffix(".original.txt")
        assert digest(original) == item["original_sha256"], f"Changed frozen original: {original}"
    attempts_dir = EVIDENCE / "attempts"
    attempts_dir.mkdir(exist_ok=True)
    index = 1 + max([int(p.name) for p in attempts_dir.iterdir() if p.is_dir() and p.name.isdigit()] or [0])
    attempt = attempts_dir / f"{index:02d}"
    attempt.mkdir()
    report_file = attempt / "result.json"
    before = snapshot()
    command = [args.godot, "--headless", "--path", str(ROOT), "--script",
               "res://tests/source_damage_life_integration_test.gd"]
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="godot-m1-v075-", dir="/tmp") as fixture_root:
        env = os.environ.copy()
        for key, suffix in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            env[key] = str(Path(fixture_root) / suffix)
            Path(env[key]).mkdir()
        env["V075_INTEGRATION_REPORT"] = str(report_file)
        env["V075_INTEGRATION_SECTIONS"] = ",".join(selected)
        try:
            process = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, timeout=150)
            output, code = process.stdout, process.returncode
        except subprocess.TimeoutExpired as exc:
            output = exc.stdout or b""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            output += "\nRUNNER ERROR: 150-second bounded timeout\n"
            code = 124
    (attempt / "raw.log.txt").write_text(output)
    after = snapshot()
    changed = sorted(key for key in before.keys() | after.keys() if before.get(key) != after.get(key))
    error_lines = [line for line in output.splitlines() if re.search(r"(^|\s)(?:SCRIPT ERROR:|ERROR:|RUNNER ERROR:)", line)]
    report = json.loads(report_file.read_text()) if report_file.exists() else {}
    reported_sections = report.get("sections", {})
    ok = (code == 0 and not changed and not error_lines and report.get("failures") == 0
          and set(reported_sections) == set(selected) and report.get("checks", 0) > 0)
    evidence = {"command":command, "exit_code":code, "elapsed_seconds":round(time.monotonic()-started,3),
                "passed":ok, "selected_sections":selected, "production_files_checked":len(before),
                "production_changed":changed, "errors":error_lines,
                "before":before, "after":after,
                "test_sha256":digest(ROOT / "tests/source_damage_life_integration_test.gd"),
                "baseline_commit":manifest["baseline_commit"],
                "isolation":"disposable /tmp/godot-m1-v075-* XDG roots"}
    (attempt / "dependency-evidence.json").write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    if not ok and not (EVIDENCE / "first-failed.log.txt").exists():
        (EVIDENCE / "first-failed.log.txt").write_text(output)
        (EVIDENCE / "first-failed.json").write_text(json.dumps({"attempt":index,"sections":selected,
            "exit_code":code,"errors":error_lines,"production_changed":changed}, indent=2) + "\n")
    aggregate_file = EVIDENCE / "integration-report.json"
    aggregate = json.loads(aggregate_file.read_text()) if aggregate_file.exists() else {
        "baseline_commit":manifest["baseline_commit"], "sections":{}, "attempts":[], "observations":{}}
    # These are the latest result for each logical section, never a rerun sum.
    for name in selected:
        result = reported_sections.get(name, {"checks":0, "failures":1, "incomplete":True})
        aggregate["sections"][name] = {**result, "attempt":index,
            "test_sha256":evidence["test_sha256"], "production_unchanged":not changed,
            "raw_log":str((attempt / "raw.log.txt").relative_to(ROOT))}
    aggregate["observations"].update(report.get("observations", {}))
    aggregate["attempts"].append({"attempt":index, "selected_sections":selected,
        "passed":ok, "checks":report.get("checks",0), "failures":report.get("failures"),
        "elapsed_seconds":evidence["elapsed_seconds"], "errors":error_lines})
    aggregate["unique_checks"] = sum(row["checks"] for row in aggregate["sections"].values())
    aggregate["unique_failures"] = sum(row["failures"] for row in aggregate["sections"].values())
    aggregate["complete"] = set(aggregate["sections"]) == set(SECTIONS)
    aggregate["passed"] = (aggregate["complete"] and aggregate["unique_failures"] == 0
        and all(row.get("production_unchanged") and not row.get("incomplete")
                for row in aggregate["sections"].values()))
    aggregate_file.write_text(json.dumps(aggregate, indent=2, sort_keys=True) + "\n")
    print(output, end="")
    print(json.dumps({"attempt":index, "passed":ok, "exit_code":code,
        "elapsed_seconds":evidence["elapsed_seconds"], "production_files_checked":len(before),
        "production_changed":changed, "unique_checks":aggregate["unique_checks"],
        "aggregate_passed":aggregate["passed"]}, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
