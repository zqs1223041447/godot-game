#!/usr/bin/env python3
"""One short test window, reusing both complete projects' existing imports."""
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

BASE_COMMIT = "5e442d98e82b248efc3a553fdf9bf95733929096"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="/usr/local/bin/godot")
    parser.add_argument("--baseline", type=Path,
                        default=Path("/workspace/scratch/a51485f153de/v054-final-source-snapshot"))
    parser.add_argument("--manifest", type=Path,
                        default=Path("/workspace/scratch/a51485f153de/v054-final-release/source-manifest.json"))
    args = parser.parse_args()
    output = Path(__file__).resolve().parent
    root = output.parents[2]
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    manifest = json.loads(args.manifest.read_text())
    if manifest["commit"] != BASE_COMMIT:
        raise RuntimeError("Wrong frozen release manifest")
    baseline_sources = {}
    for name, metadata in manifest["files"].items():
        if name == "project.godot" or name.startswith("scripts/") and name.endswith(".gd"):
            actual = sha(args.baseline / name)
            if actual != metadata["sha256"]:
                raise RuntimeError("Frozen v054 original bytes changed: " + name)
            baseline_sources[name] = actual

    def current_sources():
        paths = [root / "project.godot", root / "tests/forgeblade_hit_rules_test.gd",
                 root / "tests/local_weapon_compiler_test.gd", output / "capture_v054.gd", Path(__file__)]
        paths += sorted((root / "scripts").rglob("*.gd"))
        return {str(path.relative_to(root)): sha(path) for path in paths}

    isolated = Path(tempfile.mkdtemp(prefix="godot-m1-v055-weapon-"))
    env = os.environ.copy()
    for key, folder in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        path = isolated / folder
        path.mkdir()
        env[key] = str(path)
    oracle = output / f"{stamp}-v54FrozenOracle.bin"
    env["V055_ORACLE_OUTPUT"] = str(oracle)
    env["V055_ORACLE_INPUT"] = str(oracle)
    runs = []
    before = current_sources()
    for label, project, script, pattern in [
        ("frozen-v054", args.baseline, str(output / "capture_v054.gd"), r"Frozen v054 weapon oracle: (\d+) complete result rows"),
        ("forgeblade", root, "res://tests/forgeblade_hit_rules_test.gd", r"Forgeblade hit rules: (\d+) checks, (\d+) failures"),
        ("legacy-weapon", root, "res://tests/local_weapon_compiler_test.gd", r"Local weapon compiler: (\d+) checks, (\d+) failures"),
    ]:
        command = [args.godot, "--headless", "--path", str(project), "--script", script]
        started = time.monotonic()
        process = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 check=False, timeout=60)
        elapsed = time.monotonic() - started
        log = output / f"{stamp}-{label}.log.txt"
        log.write_bytes(process.stdout)
        text = process.stdout.decode("utf-8", errors="replace")
        summary = re.search(pattern, text)
        errors = bool(re.search(r"(^|\s)(SCRIPT ERROR:|ERROR:)", text))
        passed = process.returncode == 0 and not errors and bool(summary)
        if label != "frozen-v054" and summary:
            passed = passed and int(summary[2]) == 0
        runs.append({"name": label, "command": command, "exit_code": process.returncode,
                     "elapsed_seconds": elapsed, "log": log.name, "passed": passed,
                     "script_or_engine_errors": errors, "summary": summary.group(0) if summary else None})
        print(text, end="")
        if not passed:
            break
    after = current_sources()
    baseline_after = {name: sha(args.baseline / name) for name in baseline_sources}
    result = {"started_utc": stamp, "base_commit": BASE_COMMIT, "baseline": str(args.baseline),
              "baseline_manifest_sha256": sha(args.manifest), "baseline_original_source_sha256": baseline_sources,
              "baseline_unchanged": baseline_sources == baseline_after, "xdg_root": str(isolated),
              "oracle": oracle.name if oracle.exists() else None,
              "oracle_sha256": sha(oracle) if oracle.exists() else None,
              "runs": runs, "input_sha256_before": before, "input_sha256_after": after,
              "inputs_unchanged": before == after}
    result["passed"] = (len(runs) == 3 and all(run["passed"] for run in runs)
                        and result["inputs_unchanged"] and result["baseline_unchanged"])
    report = output / f"{stamp}-results.json"
    report.write_text(json.dumps(result, indent=2) + "\n")
    print("Evidence:", report)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
