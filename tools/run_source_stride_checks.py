#!/usr/bin/env python3
"""Run bounded v74 integration with isolated saves and immutable dependency evidence.
Editor/import is intentionally excluded: run only after the parent import gate.
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
EVIDENCE = ROOT / "docs/qa/v074-integration-tests"
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
    args = parser.parse_args()
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    before = snapshot()
    manifest = json.loads((EVIDENCE / "frozen/manifest.json").read_text())
    for item in manifest["files"]:
        fixture = ROOT / item["fixture"]
        assert digest(fixture) == item["fixture_sha256"], f"Changed frozen fixture: {fixture}"
        original = fixture.with_suffix(".original.txt")
        assert digest(original) == item["original_sha256"], f"Changed frozen original: {original}"
    command = [args.godot, "--headless", "--path", str(ROOT), "--script", "res://tests/source_stride_integration_test.gd"]
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="godot-m1-v074-", dir="/tmp") as fixture_root:
        env = os.environ.copy()
        for key, suffix in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
            env[key] = str(Path(fixture_root) / suffix)
            Path(env[key]).mkdir()
        env["V074_INTEGRATION_REPORT"] = str(EVIDENCE / "integration-report.json")
        report_file = Path(env["V074_INTEGRATION_REPORT"])
        if report_file.exists():
            report_file.unlink()
        try:
            process = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=150)
            output, code = process.stdout, process.returncode
        except subprocess.TimeoutExpired as exc:
            output = exc.stdout or b""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            output += "\nRUNNER ERROR: 150-second bounded timeout\n"
            code = 124
    (EVIDENCE / "integration.log.txt").write_text(output)
    after = snapshot()
    changed = sorted(key for key in before.keys() | after.keys() if before.get(key) != after.get(key))
    error_lines = [line for line in output.splitlines() if re.search(r"(^|\s)(?:SCRIPT ERROR:|ERROR:|RUNNER ERROR:)", line)]
    report = json.loads(report_file.read_text()) if report_file.exists() else {}
    ok = code == 0 and not changed and not error_lines and report.get("failures") == 0 and report.get("checks", 0) > 0
    evidence = {"command":command,"exit_code":code,"elapsed_seconds":round(time.monotonic()-started,3),
        "passed":ok,"production_files_checked":len(before),"production_changed":changed,
        "errors":error_lines,"before":before,"after":after,"test_sha256":digest(ROOT / "tests/source_stride_integration_test.gd"),
        "baseline_commit":manifest["baseline_commit"],"isolation":"disposable /tmp/godot-m1-v074-* XDG roots"}
    (EVIDENCE / "dependency-evidence.json").write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    print(output, end="")
    print(json.dumps({key:evidence[key] for key in ("passed","exit_code","elapsed_seconds","production_files_checked","production_changed")}, indent=2))
    return 0 if ok else 1

if __name__ == "__main__":
    raise SystemExit(main())
