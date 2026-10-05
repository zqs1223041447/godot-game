#!/usr/bin/env python3
"""Two short headless probes, using the already imported complete release trees."""
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

BASE_COMMIT = "63d84b2db67feb51595caf786e0c311736f08a74"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="/usr/local/bin/godot")
    parser.add_argument("--baseline", type=Path,
                        default=Path("/workspace/scratch/a51485f153de/v055-final-source-snapshot"))
    parser.add_argument("--manifest", type=Path,
                        default=Path("/workspace/scratch/a51485f153de/v055-final-release/source-manifest.json"))
    parser.add_argument("--reuse-oracle", type=Path, help="Replay a verified existing v055 capture after a focused fix")
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
                raise RuntimeError("Frozen v055 original bytes changed: " + name)
            baseline_sources[name] = actual
    prior_probe = "docs/qa/v055-weapon-rules/capture_v054.gd"
    if sha(root / prior_probe) != sha(args.baseline / prior_probe):
        raise RuntimeError("Previously published shared probe changed")

    def current_sources():
        paths = [root / "project.godot", root / "scripts/game_data.gd",
                 root / "tests/forgeblade_basic_rules_test.gd", root / prior_probe,
                 output / "capture_v055.gd", Path(__file__)]
        for directory in ["scripts/combat", "scripts/items"]:
            paths += sorted((root / directory).glob("*.gd"))
        return {str(path.relative_to(root)): sha(path) for path in paths}

    isolated = Path(tempfile.mkdtemp(prefix="godot-m1-v056-rules-"))
    env = os.environ.copy()
    for key, folder in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        path = isolated / folder
        path.mkdir()
        env[key] = str(path)
    oracle = args.reuse_oracle or output / f"{stamp}-v55FrozenOracle.bin"
    reused_capture = None
    if args.reuse_oracle:
        capture_report = oracle.with_name(oracle.name.replace("-v55FrozenOracle.bin", "-results.json"))
        original = json.loads(capture_report.read_text())
        if (original["base_commit"] != BASE_COMMIT or not original["baseline_unchanged"]
                or original["oracle_sha256"] != sha(oracle)
                or original["baseline_original_source_sha256"] != baseline_sources
                or not original["runs"][0]["passed"] or original["runs"][0]["name"] != "frozen-v055"):
            raise RuntimeError("Existing oracle lacks an unchanged verified release capture")
        reused_capture = {"report": str(capture_report), "sha256": sha(capture_report),
                          "verified_baseline_run": original["runs"][0]}
    env["V056_ORACLE_OUTPUT"] = str(oracle)
    env["V056_ORACLE_INPUT"] = str(oracle)
    runs = []
    before = current_sources()
    probes = [
        ("frozen-v055", args.baseline, str(output / "capture_v055.gd"),
         r"Frozen v055 basic oracle: (\d+) complete result rows, (\d+) original in-flight carriers"),
        ("basic-rules", root, "res://tests/forgeblade_basic_rules_test.gd",
         r"Forgeblade basic rules: (\d+) checks, (\d+) failures"),
    ]
    if args.reuse_oracle:
        probes = probes[1:]
    for label, project, script, pattern in probes:
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
        if label != "frozen-v055" and summary:
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
              "reused_capture": reused_capture, "runs": runs, "input_sha256_before": before, "input_sha256_after": after,
              "inputs_unchanged": before == after}
    result["passed"] = (len(runs) == len(probes) and all(run["passed"] for run in runs)
                        and result["inputs_unchanged"] and result["baseline_unchanged"])
    report = output / f"{stamp}-results.json"
    report.write_text(json.dumps(result, indent=2) + "\n")
    print("Evidence:", report)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
