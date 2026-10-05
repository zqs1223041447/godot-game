#!/usr/bin/env python3
"""Run only the two current source/schema tests after the shared first import."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

project = Path(__file__).resolve().parents[3]
qa = Path(__file__).resolve().parent
run_root = Path(tempfile.mkdtemp(prefix="godot-m1-v054-source.", dir="/tmp"))
records = []
tests = sys.argv[1:] or ["source_faster_burn_rules", "source_faster_burn_migration"]
if any(test not in ("source_faster_burn_rules", "source_faster_burn_migration") for test in tests):
    raise SystemExit("Only the two focused source/schema tests are supported")
for test in tests:
    env = os.environ.copy()
    for kind in ("DATA", "CONFIG", "CACHE"):
        target = run_root / test / kind.lower()
        target.mkdir(parents=True)
        env[f"XDG_{kind}_HOME"] = str(target)
    env["V054_SOURCE_REPORT"] = str(qa / "source-coverage.json")
    command = [env.get("GODOT_BIN", "/usr/local/bin/godot"), "--headless", "--path", str(project), "--script", f"res://tests/{test}_test.gd"]
    tracked = [project / f"tests/{test}_test.gd"] + [project / p for p in ("scripts/passives/source_stat_patterns.gd", "scripts/passives/source_tree_runtime.gd", "scripts/passives/source_tree_data.gd", "scripts/save/canonical_build_rules.gd", "scripts/save/canonical_build_store.gd", "scripts/save/fire_dot_migration.gd", "scripts/save/faster_burn_migration.gd", "scripts/canonical_game_state.gd", "data/passives/official_tree_runtime.json")]
    inputs = {str(p.relative_to(project)):hashlib.sha256(p.read_bytes()).hexdigest() for p in tracked}
    started = time.time()
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=180)
    text = result.stdout + result.stderr
    log = qa / f"{test}-{run_root.name.rsplit('.',1)[-1]}.log"
    log.write_text(text)
    record = {"test":test,"command":command,"exit_code":result.returncode,"elapsed_seconds":round(time.time()-started,3),"log":log.name,"xdg_data":env["XDG_DATA_HOME"],"script_errors":any(marker in text for marker in ("SCRIPT ERROR:","Parse Error:","ERROR:")),"source_sha256":inputs}
    records.append(record)
    (qa / f"evidence-{run_root.name.rsplit('.',1)[-1]}.json").write_text(json.dumps(records,indent=2)+"\n")
    print(text, flush=True)
    if result.returncode or record["script_errors"] or "0 failures" not in text:
        raise SystemExit(result.returncode or 1)
print("Focused source/schema tests passed", flush=True)
