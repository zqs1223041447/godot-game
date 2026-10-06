#!/usr/bin/env python3
"""Pure cold ailment duration proof. Run only after the parent's shared Godot import."""
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
STAMP = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
PROFILE = pathlib.Path(tempfile.mkdtemp(prefix="godot-v082-rules-"))
env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
for key, directory in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
    target = PROFILE / directory
    target.mkdir()
    env[key] = str(target)
inputs = [ROOT / path for path in [
    "scripts/combat/cold_ailment_duration_rules.gd",
    "scripts/combat/frost_lock_rules.gd",
    "scripts/combat/freeze_runtime.gd",
    "tests/cold_ailment_duration_rules_test.gd",
    "project.godot",
]]


def hashes():
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}


before = hashes()
command = [os.environ.get("GODOT_BIN", "/usr/local/bin/godot"), "--headless", "--path", str(ROOT),
           "--script", "tests/cold_ailment_duration_rules_test.gd"]
start = time.monotonic()
try:
    result = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    log, code = result.stdout, result.returncode
except subprocess.TimeoutExpired as error:
    log, code = error.stdout or b"", 124
(OUT / f"{STAMP}-run.log.txt").write_bytes(log)
after = hashes()
receipt = dict(command=command, exit_code=code, elapsed_seconds=round(time.monotonic() - start, 3),
               isolated_user_dir=str(PROFILE), log=f"{STAMP}-run.log.txt", script_errors=log.count(b"SCRIPT ERROR"),
               engine_errors=log.count(b"ERROR:"), inputs_before=before, inputs_after=after,
               inputs_unchanged=before == after)
(OUT / f"{STAMP}-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(log.decode(errors="replace"), flush=True)
print(json.dumps({key: receipt[key] for key in ["exit_code", "elapsed_seconds", "script_errors", "engine_errors", "inputs_unchanged", "log"]}), flush=True)
raise SystemExit(code or int(bool(receipt["script_errors"] or receipt["engine_errors"] or before != after)))
