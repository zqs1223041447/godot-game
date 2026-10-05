#!/usr/bin/env python3
"""One bounded real-main/crafting run; no import, historical matrix or UI capture."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
TEST = ROOT / "tests/elemental_defense_affix_gameplay_test.gd"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest():
    paths = [ROOT / "project.godot"]
    for directory in ["scripts", "data", "scenes", "assets"]:
        paths.extend(p for p in (ROOT / directory).rglob("*") if p.is_file())
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(paths)}


stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
prefix = OUT / stamp
xdg = Path(tempfile.mkdtemp(prefix="godot-m1-v060-consumers-"))
env = os.environ.copy()
env.update(XDG_DATA_HOME=str(xdg), XDG_CONFIG_HOME=str(xdg / "config"),
           XDG_CACHE_HOME=str(xdg / "cache"), ELEMENTAL_AFFIX_REPORT=str(prefix) + "-checks.json")
command = ["/usr/local/bin/godot", "--headless", "--path", str(ROOT), "--script", str(TEST)]
before = manifest()
started = time.monotonic()
timed_out = False
with Path(str(prefix) + ".log.txt").open("w") as log:
    try:
        code = subprocess.run(command, cwd=ROOT, env=env, stdout=log,
                              stderr=subprocess.STDOUT, timeout=90).returncode
    except subprocess.TimeoutExpired:
        code = 124
        timed_out = True
after = manifest()
report = {"command": command, "exit_code": code, "timed_out": timed_out,
          "elapsed_seconds": time.monotonic() - started, "isolated_user_dir": str(xdg),
          "harness_sha256": digest(TEST), "source_sha256_before": before,
          "source_sha256_after": after, "source_unchanged_during_run": before == after,
          "log": prefix.name + ".log.txt", "checks": prefix.name + "-checks.json"}
Path(str(prefix) + "-run.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({key: report[key] for key in ["exit_code", "timed_out", "elapsed_seconds", "source_unchanged_during_run", "log", "checks"]}))
raise SystemExit(code)
