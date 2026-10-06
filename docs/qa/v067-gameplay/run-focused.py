#!/usr/bin/env python3
"""Bounded actual-Main test, with input hashes captured before execution."""
import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent
GODOT = os.environ.get("GODOT_BIN", "/usr/local/bin/godot")
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
home = pathlib.Path(tempfile.mkdtemp(prefix="godot-m1-v067-gameplay-"))
env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
for kind in ("data", "config", "cache"):
    (home / kind).mkdir()
    env[f"XDG_{kind.upper()}_HOME"] = str(home / kind)

paths = sorted((ROOT / "scripts").rglob("*.gd"))
paths += sorted((ROOT / "scenes").rglob("*.tscn"))
paths += sorted((ROOT / "data").rglob("*.json"))
paths += [ROOT / "project.godot", ROOT / "tests/inward_pull_gameplay_test.gd", pathlib.Path(__file__)]


def hashes():
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


before = hashes()
command = [GODOT, "--headless", "--path", str(ROOT), "--script", "res://tests/inward_pull_gameplay_test.gd"]
manifest = OUT / f"{stamp}-input-sha256.json"
manifest.write_text(json.dumps({"captured_before_execution": True, "command": command, "files": before}, indent=2) + "\n")
start = time.monotonic()
try:
    result = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=55)
    log, code = result.stdout, result.returncode
except subprocess.TimeoutExpired as exc:
    log, code = exc.stdout or b"", 124
log_path = OUT / f"{stamp}-gameplay.log.txt"
log_path.write_bytes(log)
after = hashes()
summary = {"command": command, "exit_code": code, "elapsed_seconds": round(time.monotonic() - start, 3),
           "isolated_user_dir": str(home), "input_manifest": manifest.name, "log": log_path.name,
           "script_errors": log.count(b"SCRIPT ERROR"), "engine_errors": log.count(b"ERROR:"),
           "completed": b"INWARD_PULL_GAMEPLAY_COMPLETE" in log, "inputs_unchanged": before == after,
           "changed_inputs": [key for key in before if before[key] != after.get(key)]}
(OUT / f"{stamp}-result.json").write_text(json.dumps(summary, indent=2) + "\n")
print(log.decode(errors="replace"), flush=True)
print(json.dumps(summary), flush=True)
raise SystemExit(code or (0 if summary["completed"] and not summary["script_errors"] and not summary["engine_errors"] and summary["inputs_unchanged"] else 1))
