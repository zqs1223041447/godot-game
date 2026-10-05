#!/usr/bin/env python3
"""Run only the faster-burn rules suite after the shared project import is ready."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="/usr/local/bin/godot")
    args = parser.parse_args()
    output = Path(__file__).resolve().parent
    root = output.parents[2]
    relative_inputs = [
        "project.godot",
        "scripts/combat/burn_rules.gd",
        "scripts/combat/burn_runtime.gd",
        "tests/faster_burn_rules_test.gd",
        "docs/qa/v054-rules/v053_burn_rules.gd",
        "docs/qa/v054-rules/oracle-manifest.json",
        "docs/qa/v054-rules/run_rules.py",
    ]

    def hashes() -> dict[str, str]:
        return {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
                for name in relative_inputs}

    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    isolated = Path(tempfile.mkdtemp(prefix="godot-m1-v054-rules-"))
    env = os.environ.copy()
    for key, folder in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                        ("XDG_CACHE_HOME", "cache")]:
        directory = isolated / folder
        directory.mkdir()
        env[key] = str(directory)
    command = [args.godot, "--headless", "--path", str(root), "--script",
               "res://tests/faster_burn_rules_test.gd"]
    before = hashes()
    started = time.monotonic()
    process = subprocess.run(command, env=env, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, check=False, timeout=60)
    elapsed = time.monotonic() - started
    log = output / f"{stamp}-rules.log.txt"
    log.write_bytes(process.stdout)
    text = process.stdout.decode("utf-8", errors="replace")
    after = hashes()
    summary = re.search(r"Faster burn rules: (\d+) checks, (\d+) failures", text)
    errors = bool(re.search(r"(^|\s)(SCRIPT ERROR:|ERROR:)", text))
    passed = process.returncode == 0 and before == after and not errors and bool(summary) and int(summary[2]) == 0
    result = {
        "command": command,
        "started_utc": stamp,
        "elapsed_seconds": elapsed,
        "exit_code": process.returncode,
        "passed": passed,
        "checks": int(summary[1]) if summary else None,
        "failures": int(summary[2]) if summary else None,
        "script_or_engine_errors": errors,
        "xdg_root": str(isolated),
        "log": log.name,
        "input_sha256_before": before,
        "input_sha256_after": after,
        "inputs_unchanged": before == after,
    }
    result_path = output / f"{stamp}-results.json"
    result_path.write_text(json.dumps(result, indent=2) + "\n")
    print(text, end="")
    print(f"Evidence: {result_path}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
