#!/usr/bin/env python3
"""Bounded v071 Main consumer test; shared editor import must already be complete."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
QA = ROOT / "docs/qa/v071-gameplay"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs() -> dict[str, str]:
    files = [ROOT / "project.godot", ROOT / "tests/mist_skitter_gameplay_test.gd", Path(__file__).resolve()]
    for directory in ("scripts", "scenes", "data", "assets", "docs/qa/v071-gameplay/frozen"):
        files.extend(p for p in (ROOT / directory).rglob("*") if p.is_file() and not p.name.endswith(".uid") and "assets/fonts/" not in str(p.relative_to(ROOT)))
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(set(files))}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sections", default="")
    args = parser.parse_args()
    attempt = QA / "attempts" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    attempt.mkdir(parents=True)
    sandbox = Path(tempfile.mkdtemp(prefix="godot-m1-v071-mist-"))
    env = os.environ.copy()
    for key, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"), ("XDG_STATE_HOME", "state"), ("XDG_RUNTIME_DIR", "runtime")):
        (sandbox / name).mkdir(mode=0o700)
        env[key] = str(sandbox / name)
    env.update(GODOT_SILENCE_ROOT_WARNING="1", MIST_GAMEPLAY_REPORT=str(attempt / "gameplay-report.json"), MIST_GAMEPLAY_SECTIONS=args.sections)
    command = ["godot", "--headless", "--path", str(ROOT), "--script", "res://tests/mist_skitter_gameplay_test.gd"]
    before = inputs()
    (attempt / "inputs-before.json").write_text(json.dumps(before, indent=2, sort_keys=True) + "\n")
    started = datetime.now(timezone.utc).isoformat()
    clock = time.monotonic()
    process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, "stdout")
    selector.register(process.stderr, selectors.EVENT_READ, "stderr")
    output = {"stdout": bytearray(), "stderr": bytearray()}
    abort = ""
    while selector.get_map():
        if time.monotonic() - clock > 45 and not abort:
            abort = "45-second watchdog"
            process.kill()
        for key, _ in selector.select(0.1):
            chunk = os.read(key.fileobj.fileno(), 65536)
            if not chunk:
                selector.unregister(key.fileobj)
                continue
            output[key.data].extend(chunk)
            if not abort and re.search(rb"SCRIPT ERROR|ERROR:|Assertion failed", output[key.data]):
                abort = "Stopped on first Godot error"
                process.kill()
    raw_exit = process.wait(timeout=5)
    elapsed = time.monotonic() - clock
    for kind, content in output.items():
        (attempt / (kind + ".log")).write_bytes(content)
    after = inputs()
    (attempt / "inputs-after.json").write_text(json.dumps(after, indent=2, sort_keys=True) + "\n")
    changed = sorted(name for name in set(before) | set(after) if before.get(name) != after.get(name))
    report_file = attempt / "gameplay-report.json"
    report = json.loads(report_file.read_text()) if report_file.exists() else {}
    expected = 5 if not args.sections else len(set(args.sections.split(",")) | {"legal_source_setup"})
    passed = raw_exit == 0 and not abort and not changed and report.get("failures") == 0 and len(report.get("sections", {})) == expected
    receipt = {"command": command, "started_utc": started, "elapsed_seconds": elapsed, "raw_exit": raw_exit, "abort": abort,
               "isolated_environment": {k: v for k, v in env.items() if k.startswith("XDG_") or k.startswith("MIST_")},
               "input_hashes_match": not changed, "changed_inputs": changed, "requested_sections": args.sections,
               "hash_boundary": "All scripts/scenes/data/non-font assets plus test/runner/frozen catalog. Assets/fonts are excluded because independent glyph work is concurrent; this test does not claim font/render validation.",
               "checks": report.get("checks"), "failures": report.get("failures"), "sections": report.get("sections", {}), "passed": passed,
               "stdout_sha256": digest(attempt / "stdout.log"), "stderr_sha256": digest(attempt / "stderr.log")}
    (attempt / "receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"attempt": str(attempt), **receipt}, sort_keys=True))
    for kind, content in output.items():
        if content:
            print(kind + ":\n" + content.decode(errors="replace"))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
