#!/usr/bin/env python3
"""Run only the focused pure suite, after the parent's shared Godot import."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
TEST = "tests/precise_technique_rules_test.gd"


def inputs():
    pending = [TEST, "project.godot"]
    files = {}
    while pending:
        rel = pending.pop()
        if rel in files:
            continue
        path = ROOT / rel
        data = path.read_bytes()
        files[rel] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
        if path.suffix == ".gd":
            for dep in re.findall(r'(?:preload|load)\(\s*"res://([^"\n]+)"\s*\)', data.decode()):
                pending.append(dep)
            uid = path.with_suffix(".gd.uid")
            if uid.exists():
                pending.append(str(uid.relative_to(ROOT)))
    return dict(sorted(files.items()))


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
prefix = QA / stamp
before = inputs()
save(Path(str(prefix) + "-inputs-before.json"), before)
isolation = tempfile.mkdtemp(prefix="v070-precise-rules-")
env = os.environ.copy()
for name, suffix in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
    env[name] = str(Path(isolation) / suffix)
env["PRECISE_RULES_REPORT"] = str(prefix) + "-checks.json"
command = ["godot", "--headless", "--path", str(ROOT), "--script", "res://" + TEST]
started = time.monotonic()
timed_out = False
try:
    result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
    log = result.stdout
    exit_code = result.returncode
except subprocess.TimeoutExpired as exc:
    timed_out = True
    log = exc.stdout or b""
    exit_code = 124
elapsed = time.monotonic() - started
Path(str(prefix) + "-raw.log.txt").write_bytes(log)
after = inputs()
save(Path(str(prefix) + "-inputs-after.json"), after)
errors = bool(re.search(rb"(?:SCRIPT ERROR:|(?m:^ERROR:))", log))
receipt = {"command": command, "exit_code": exit_code, "elapsed_seconds": round(elapsed, 3),
           "timed_out": timed_out, "xdg_isolation": isolation, "engine_errors": errors,
           "inputs_identical_before_after": before == after, "input_file_count": len(before),
           "raw_log": str(Path(str(prefix) + "-raw.log.txt").relative_to(QA)),
           "checks_report": str(Path(str(prefix) + "-checks.json").relative_to(QA))}
save(Path(str(prefix) + "-receipt.json"), receipt)
print(log.decode(errors="replace"), end="")
print(json.dumps(receipt, indent=2))
raise SystemExit(exit_code if exit_code else int(errors or before != after))
