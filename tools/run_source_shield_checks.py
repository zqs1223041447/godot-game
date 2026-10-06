#!/usr/bin/env python3
"""Bounded v76 sections after the shared import gate; never invokes editor/import.

Each selected section runs in a disposable /tmp XDG root. Retry only affected
sections with --section. Stop the running engine immediately on SCRIPT ERROR.
Keep every attempt and count each logical section once in the final aggregate.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs/qa/v076-integration-tests"
SECTIONS = ("registry", "sampling", "camps", "factory_maps", "snapshot_transactions",
            "cache_atomicity", "special_lineages", "main_adoption", "recharge_lifecycle")
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


def run_engine(command: list[str], env: dict[str, str]) -> tuple[str, int]:
    """Read continuously so a script failure cannot become a misleading timeout."""
    process = subprocess.Popen(command, env=env, text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, bufsize=1)
    lines: queue.Queue[str | None] = queue.Queue()
    def read_output() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            lines.put(line)
        lines.put(None)
    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    output: list[str] = []
    deadline = time.monotonic() + 90
    forced_code = 0
    while True:
        try:
            line = lines.get(timeout=max(0.01, min(0.2, deadline - time.monotonic())))
        except queue.Empty:
            if time.monotonic() < deadline:
                continue
            output.append("RUNNER ERROR: bounded 90-second section timeout\n")
            process.kill(); forced_code = 124
            break
        if line is None:
            break
        output.append(line)
        if "SCRIPT ERROR:" in line:
            output.append("RUNNER ERROR: fail-fast after SCRIPT ERROR\n")
            process.kill(); forced_code = 125
            break
    process.wait(timeout=10)
    reader.join(timeout=2)
    while not lines.empty():
        line = lines.get_nowait()
        if line is not None:
            output.append(line)
    return "".join(output), forced_code or process.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--section", action="append", choices=SECTIONS,
                        help="Run only named section(s); preserves unaffected successful evidence")
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
    before = snapshot()
    test_hash = digest(ROOT / "tests/source_shield_integration_test.gd")
    command = [args.godot, "--headless", "--path", str(ROOT), "--script", "res://tests/source_shield_integration_test.gd"]
    started = time.monotonic()
    results: dict = {}
    observations: dict = {}
    all_output: list[str] = []
    section_errors: dict[str, list[str]] = {}
    section_codes: dict[str, int] = {}
    for section in selected:
        report_file = attempt / f"{section}.json"
        with tempfile.TemporaryDirectory(prefix="godot-m1-v076-", dir="/tmp") as fixture_root:
            env = os.environ.copy()
            for key, suffix in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
                env[key] = str(Path(fixture_root) / suffix)
                Path(env[key]).mkdir()
            env["V076_INTEGRATION_REPORT"] = str(report_file)
            env["V076_INTEGRATION_SECTIONS"] = section
            output, code = run_engine(command, env)
        (attempt / f"{section}.log.txt").write_text(output)
        all_output.append(f"SECTION {section}\n" + output)
        print(output, end="", flush=True)
        errors = [line for line in output.splitlines() if re.search(r"(^|\s)(?:SCRIPT ERROR:|ERROR:|RUNNER ERROR:)", line)]
        section_errors[section] = errors
        section_codes[section] = code
        report = json.loads(report_file.read_text()) if report_file.exists() else {}
        result = report.get("sections", {}).get(section, {"checks":0, "failures":1, "incomplete":True})
        results[section] = {**result, "exit_code":code, "errors":errors}
        observations.update(report.get("observations", {}))
        if code == 125:
            # All sections load the same script; retry only after fixing the parser/runtime failure.
            break
    output = "\n".join(all_output)
    (attempt / "raw.log.txt").write_text(output)
    after = snapshot()
    changed = sorted(key for key in before.keys() | after.keys() if before.get(key) != after.get(key))
    errors = [line for lines in section_errors.values() for line in lines]
    ok = (not changed and not errors and set(results) == set(selected)
          and all(row["exit_code"] == 0 and row.get("failures") == 0 and row.get("checks",0) > 0 for row in results.values()))
    evidence = {"command":command, "section_exit_codes":section_codes,
                "elapsed_seconds":round(time.monotonic()-started,3), "passed":ok,
                "selected_sections":selected,"executed_sections":list(results),
                "production_files_checked":len(before), "production_changed":changed,
                "errors":errors,"before":before,"after":after,"test_sha256":test_hash,
                "runner_sha256":digest(Path(__file__)),"baseline_commit":manifest["baseline_commit"],
                "isolation":"disposable /tmp/godot-m1-v076-* XDG roots", "engine_import_invoked":False}
    (attempt / "dependency-evidence.json").write_text(json.dumps(evidence,indent=2,sort_keys=True)+"\n")
    if not ok and not (EVIDENCE / "first-failed.log.txt").exists():
        (EVIDENCE / "first-failed.log.txt").write_text(output)
        (EVIDENCE / "first-failed.json").write_text(json.dumps({"attempt":index,"sections":selected,
            "section_exit_codes":section_codes,"errors":errors,"production_changed":changed},indent=2)+"\n")
    aggregate_file = EVIDENCE / "integration-report.json"
    aggregate = json.loads(aggregate_file.read_text()) if aggregate_file.exists() else {
        "baseline_commit":manifest["baseline_commit"],"sections":{},"attempts":[],"observations":{}}
    for name, result in results.items():
        aggregate["sections"][name] = {**result,"attempt":index,"test_sha256":test_hash,
            "production_unchanged":not changed,"production_snapshot_sha256":hashlib.sha256(json.dumps(before,sort_keys=True).encode()).hexdigest(),
            "raw_log":str((attempt/f"{name}.log.txt").relative_to(ROOT))}
    aggregate["observations"].update(observations)
    aggregate["attempts"].append({"attempt":index,"selected_sections":selected,"executed_sections":list(results),"passed":ok,
        "checks":sum(row.get("checks",0) for row in results.values()),"elapsed_seconds":evidence["elapsed_seconds"],"errors":errors})
    aggregate["unique_checks"] = sum(row["checks"] for row in aggregate["sections"].values())
    aggregate["unique_failures"] = sum(row["failures"] for row in aggregate["sections"].values())
    aggregate["complete"] = set(aggregate["sections"]) == set(SECTIONS)
    aggregate["passed"] = (aggregate["complete"] and aggregate["unique_failures"] == 0 and
        all(row.get("production_unchanged") and not row.get("incomplete") and not row.get("errors") and row.get("exit_code")==0 for row in aggregate["sections"].values()))
    aggregate_file.write_text(json.dumps(aggregate,indent=2,sort_keys=True)+"\n")
    print(json.dumps({"attempt":index,"passed":ok,"elapsed_seconds":evidence["elapsed_seconds"],
        "production_files_checked":len(before),"production_changed":changed,"unique_checks":aggregate["unique_checks"],
        "aggregate_passed":aggregate["passed"]},indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
