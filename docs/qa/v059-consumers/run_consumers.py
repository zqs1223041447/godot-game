#!/usr/bin/env python3
"""Bounded v59 main/model consumers plus independently frozen v58 oracle.

No project copy and no edits to the frozen production tree. Every invocation
gets a fresh /tmp XDG directory. Keep failed logs and manifests for review.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import gzip
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
TEST = ROOT / "tests/elemental_resistance_cap_gameplay_test.gd"
BASE = "71f4863"
GODOT = "/usr/local/bin/godot"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def tracked_inputs() -> list[str]:
    return subprocess.check_output(
        ["git", "ls-tree", "-r", "--name-only", BASE, "scripts", "data", "scenes", "assets", "project.godot"],
        cwd=ROOT, text=True,
    ).splitlines()


def manifest(project: Path) -> dict[str, str]:
    paths = set(tracked_inputs())
    paths.update(str(p.relative_to(project)) for p in (project / "scripts").rglob("*.gd"))
    return {path: digest((project / path).read_bytes()) for path in sorted(paths)}


def verify_frozen(project: Path) -> dict:
    entries = {}
    mismatches = []
    for path in tracked_inputs():
        expected = subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT)
        actual = (project / path).read_bytes()
        entries[path] = digest(actual)
        if actual != expected:
            mismatches.append(path)
    return {"base": BASE, "frozen_project": str(project), "checked_files": len(entries),
            "mismatches": mismatches, "sha256": entries}


def execute(project: Path, stem: str, legacy: bool = False) -> dict:
    prefix = OUT / stem
    env = os.environ.copy()
    xdg = Path(tempfile.mkdtemp(prefix="godot-m1-v059-consumers-"))
    env.update({"XDG_DATA_HOME": str(xdg), "XDG_CONFIG_HOME": str(xdg / "config"),
                "XDG_CACHE_HOME": str(xdg / "cache")})
    env.pop("RESISTANCE_CAP_LEGACY_OUTPUT", None)
    env.pop("RESISTANCE_CAP_REPORT", None)
    env["RESISTANCE_CAP_LEGACY_OUTPUT" if legacy else "RESISTANCE_CAP_REPORT"] = str(prefix if legacy else prefix.with_suffix(".json"))
    command = [GODOT, "--headless", "--path", str(project), "--script", str(TEST)]
    before = manifest(project)
    started = time.monotonic()
    timed_out = False
    with prefix.with_suffix(".log.txt").open("w") as log:
        try:
            completed = subprocess.run(command, cwd=ROOT, env=env, stdout=log,
                                       stderr=subprocess.STDOUT, timeout=120)
            code = completed.returncode
        except subprocess.TimeoutExpired:
            code = 124
            timed_out = True
    after = manifest(project)
    report = {"command": command, "exit_code": code, "timed_out": timed_out,
              "elapsed_seconds": time.monotonic() - started, "xdg": str(xdg),
              "harness_sha256": digest(TEST.read_bytes()), "source_sha256_before": before,
              "source_sha256_after": after, "source_unchanged_during_run": before == after}
    write(prefix.with_name(prefix.name + "-run.json"), report)
    print(json.dumps({key: report[key] for key in ("exit_code", "elapsed_seconds", "source_unchanged_during_run")}), flush=True)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--frozen", type=Path, default=ROOT.parent / "v058-final-source-snapshot")
    parser.add_argument("--only", choices=("gameplay", "legacy", "all"), default="all")
    args = parser.parse_args()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    summary = {"stamp": stamp, "base": BASE, "runs": {}, "comparisons": {}}
    if args.only in ("gameplay", "all"):
        summary["runs"]["gameplay"] = execute(ROOT, stamp + "-gameplay")
    if args.only in ("legacy", "all"):
        frozen = verify_frozen(args.frozen)
        write(OUT / (stamp + "-frozen-inputs.json"), frozen)
        if frozen["mismatches"]:
            raise RuntimeError("Frozen tree differs from released v58 inputs")
        for label, project in (("v058", args.frozen), ("v059", ROOT)):
            summary["runs"][label] = execute(project, stamp + "-" + label, legacy=True)
        first = OUT / (stamp + "-v058")
        second = OUT / (stamp + "-v059")
        for suffix in (".bin", ".projected-save.json"):
            a, b = first.with_suffix(suffix), second.with_suffix(suffix)
            summary["comparisons"][suffix] = {
                "both_exist": a.exists() and b.exists(),
                "equal": a.exists() and b.exists() and a.read_bytes() == b.read_bytes(),
                "v058_sha256": digest(a.read_bytes()) if a.exists() else None,
                "v059_sha256": digest(b.read_bytes()) if b.exists() else None,
            }
        for label, prefix in (("v058", first), ("v059", second)):
            binary = prefix.with_suffix(".bin")
            if binary.exists():
                raw = binary.read_bytes()
                archive = binary.with_suffix(".bin.gz")
                archive.write_bytes(gzip.compress(raw, mtime=0))
                if gzip.decompress(archive.read_bytes()) != raw:
                    raise RuntimeError("Observation archive failed round-trip verification")
                summary["comparisons"][".bin"][label + "_archive"] = archive.name
                binary.unlink()
        # Raw save versions intentionally differ; never claim cross-schema raw
        # bytes equal. Same-version read-only byte preservation is asserted by
        # the gameplay harness around profile/panel, hit and burn consumers.
        summary["save_note"] = "Only schema35/schema36 version is projected; three zero derived maximum stats are projected only in observations. Cross-version raw save bytes are not compared."
        summary["frozen_production_unchanged"] = manifest(args.frozen) == frozen["sha256"]
    summary["ok"] = (
        all(run["exit_code"] == 0 and run["source_unchanged_during_run"] for run in summary["runs"].values())
        and all(value["equal"] for value in summary["comparisons"].values())
        and summary.get("frozen_production_unchanged", True)
    )
    write(OUT / (stamp + "-summary.json"), summary)
    print(json.dumps({"summary": str(OUT / (stamp + "-summary.json")), "ok": summary["ok"],
                      "comparisons": summary["comparisons"]}), flush=True)
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
