#!/usr/bin/env python3
"""Run only v069's bounded actual-Main test, retaining every attempt verbatim.

This runner deliberately neither imports assets nor runs the old-byte oracle.
Run it only after the coordinating process has completed the unified import.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs(project: Path) -> dict[str, str]:
    selected = [project / "project.godot", project / "tests/physical_fire_conversion_gameplay_test.gd",
                project / "tools/run_physical_fire_conversion_gameplay.py"]
    for directory in ("scripts", "scenes", "data"):
        selected.extend(path for path in (project / directory).rglob("*") if path.is_file())
    return {str(path.relative_to(project)): digest(path) for path in sorted(set(selected))}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output-root", type=Path)
    parser.add_argument("--timeout", type=float, default=45.0)
    args = parser.parse_args()
    project = args.project.resolve()
    root = args.output_root or project / "docs/qa/v069-conversion/gameplay"
    root.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    attempt = root / stamp
    attempt.mkdir()
    sandbox = Path(tempfile.mkdtemp(prefix="godot-m1-v069-conversion-"))
    before = inputs(project)
    (attempt / "inputs-before.json").write_text(json.dumps(before, indent=2, sort_keys=True) + "\n")
    env = os.environ.copy()
    (sandbox / "cache").mkdir()
    env.update(XDG_DATA_HOME=str(sandbox), XDG_CACHE_HOME=str(sandbox / "cache"), GODOT_SILENCE_ROOT_WARNING="1",
               CONVERSION_GAMEPLAY_REPORT=str((attempt / "gameplay-report.json").resolve()))
    command = [args.godot, "--headless", "--path", str(project), "--script",
               "res://tests/physical_fire_conversion_gameplay_test.gd"]
    started = datetime.now(timezone.utc)
    timed_out = False
    with (attempt / "stdout.log").open("wb") as stdout, (attempt / "stderr.log").open("wb") as stderr:
        try:
            result = subprocess.run(command, env=env, stdout=stdout, stderr=stderr,
                                    timeout=args.timeout, check=False)
            raw_exit = result.returncode
        except subprocess.TimeoutExpired:
            timed_out = True
            raw_exit = 124
        except OSError as error:
            stderr.write((str(error) + "\n").encode())
            raw_exit = 127
    after = inputs(project)
    (attempt / "inputs-after.json").write_text(json.dumps(after, indent=2, sort_keys=True) + "\n")
    changed = sorted(name for name in set(before) | set(after) if before.get(name) != after.get(name))
    errors = (attempt / "stderr.log").read_text(errors="replace")
    output = (attempt / "stdout.log").read_text(errors="replace")
    report_path = attempt / "gameplay-report.json"
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    passed = (raw_exit == 0 and not timed_out and not changed and
              report.get("failures") == 0 and len(report.get("sections", {})) == 6 and
              "CONVERSION_GAMEPLAY " in output and "SCRIPT ERROR" not in errors and "ERROR:" not in errors)
    summary = {
        "command": command, "engine": shutil.which(args.godot) or args.godot,
        "started_utc": started.isoformat(), "finished_utc": datetime.now(timezone.utc).isoformat(),
        "isolated_data_home": str(sandbox), "raw_exit": raw_exit, "timeout": timed_out,
        "input_hashes_match": not changed, "changed_inputs": changed,
        "checks": report.get("checks"), "failures": report.get("failures"),
        "sections": report.get("sections", {}), "passed": passed,
        "stdout_sha256": digest(attempt / "stdout.log"), "stderr_sha256": digest(attempt / "stderr.log"),
        "scope": "Current v069 actual Main only. Unified import is external. No historical byte oracle, editor UI, Windows pack, or long performance run.",
    }
    (attempt / "run-summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"attempt": str(attempt), **summary}, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
