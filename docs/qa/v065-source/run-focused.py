#!/usr/bin/env python3
"""Run only the v65 source/pure proof after the coordinated project import."""
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
OUT = Path(__file__).resolve().parent
TEST = "tests/zealots_oath_source_test.gd"
REFERENCE = re.compile(r'(?:preload|load)\("res://([^\"]+)"\)')
subprocess.run(["python3", str(OUT / "freeze_oracle.py"), "--verify"], cwd=ROOT, check=True)
inputs = {TEST, "data/passive_balance.json", "data/passives/official_tree_runtime.json", "data/passive_source/localization_zh_CN.json", "docs/qa/v065-source/manifest.json", "scripts/main.gd", "scripts/canonical_game_state.gd"}
pending = [TEST]
seen = set()
while pending:
    path = pending.pop()
    if path in seen:
        continue
    seen.add(path)
    inputs.add(path)
    pending.extend(REFERENCE.findall((ROOT / path).read_text()))
sha = lambda p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
source_hashes = {p: sha(p) for p in sorted(inputs)}
(OUT / "tested-input-sha256.json").write_text(json.dumps(source_hashes, indent=2) + "\n")
env = os.environ.copy()
env.update(XDG_DATA_HOME=tempfile.mkdtemp(prefix="godot-m1-v065-source-"), XDG_CACHE_HOME=tempfile.mkdtemp(prefix="godot-m1-v065-source-cache-"), V065_SOURCE_REPORT=str(OUT / "results.json"))
command = ["godot", "--headless", "--path", str(ROOT), "--script", "res://" + TEST]
start = time.monotonic()
run = subprocess.run(command, cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
log = run.stdout
(OUT / "focused.log.txt").write_text(log)
receipt = {"command": command, "exit_code": run.returncode, "duration_seconds": round(time.monotonic() - start, 3), "xdg_data_home": env["XDG_DATA_HOME"], "xdg_cache_home": env["XDG_CACHE_HOME"], "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "test_sha256": sha(TEST), "inputs_unchanged_during_run": all(sha(p) == digest for p,digest in source_hashes.items())}
(OUT / "execution-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(log, end="")
print(json.dumps(receipt, indent=2))
raise SystemExit(run.returncode if run.returncode else 1 if "SCRIPT ERROR" in log or "ERROR:" in log or not receipt["inputs_unchanged_during_run"] else 0)
