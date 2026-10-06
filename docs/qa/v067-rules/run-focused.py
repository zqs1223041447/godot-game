#!/usr/bin/env python3
"""Run only v067's pure rules/compiler/oracle checks after the shared import."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
TESTS = {
    "rules": "tests/inward_pull_rules_test.gd",
    "compiler": "tests/inward_pull_support_compiler_test.gd",
    "legacy": "tests/inward_pull_legacy_compile_test.gd",
}
REFERENCES = re.compile(r'(?:preload|load)\("res://([^\"]+)"\)')


def dependencies(script):
    pending = [script, "project.godot"]
    found = set()
    while pending:
        relative = pending.pop()
        path = ROOT / relative
        if relative in found or not path.is_file():
            continue
        found.add(relative)
        if relative.endswith(".gd"):
            pending.extend(REFERENCES.findall(path.read_text()))
    if "legacy" in script:
        found.add("docs/qa/v066-runtime/legacy-support-after.json")
    return sorted(found)


def hashes(paths):
    return {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in paths}


def run(script, label):
    name = Path(script).stem
    paths = dependencies(script)
    before = hashes(paths)
    isolated = Path(tempfile.mkdtemp(prefix="godot-v067-rules-"))
    env = os.environ.copy()
    for key, directory in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        env[key] = str(isolated / directory)
    command = ["/usr/local/bin/godot", "--headless", "--path", str(ROOT), "--script", "res://" + script]
    start = time.monotonic()
    try:
        process = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
        code, output = process.returncode, process.stdout
    except subprocess.TimeoutExpired as error:
        code = 124
        output = error.stdout or ""
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
    elapsed = round(time.monotonic() - start, 3)
    after = hashes(paths)
    log_name = name + "." + label + ".log.txt"
    (OUT / log_name).write_text(output)
    report = {
        "script": script, "command": command, "exit_code": code, "elapsed_seconds": elapsed,
        "isolated_xdg": str(isolated), "error_lines": [line for line in output.splitlines() if "ERROR:" in line or "SCRIPT ERROR" in line],
        "same_input_hashes": before == after, "inputs_before": before, "inputs_after": after, "stdout": log_name,
    }
    (OUT / (name + "." + label + ".json")).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(output, end="", flush=True)
    print(f"exit={code}, seconds={elapsed}, unchanged_inputs={before == after}", flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="+", choices=tuple(TESTS))
    parser.add_argument("--label", required=True, help="Unique evidence label; existing logs cannot be overwritten")
    args = parser.parse_args()
    selected = args.tests
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", args.label):
        parser.error("label must contain only letters, numbers, underscores or hyphens")
    for test in selected:
        if (OUT / (Path(TESTS[test]).stem + "." + args.label + ".json")).exists():
            parser.error("label already exists for " + test)
    reports = [run(TESTS[test], args.label) for test in selected]
    return int(any(report["exit_code"] != 0 or report["error_lines"] or not report["same_input_hashes"] for report in reports))


if __name__ == "__main__":
    raise SystemExit(main())
