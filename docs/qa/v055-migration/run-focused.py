#!/usr/bin/env python3
"""One focused schema boundary check after the parent completes shared import."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

project = Path(__file__).resolve().parents[3]
qa = Path(__file__).resolve().parent
run_root = Path(tempfile.mkdtemp(prefix="godot-m1-v055-migration.", dir="/tmp"))
env = os.environ.copy()
for kind in ("DATA", "CONFIG", "CACHE"):
    target = run_root / kind.lower()
    target.mkdir()
    env[f"XDG_{kind}_HOME"] = str(target)
command = [env.get("GODOT_BIN", "/usr/local/bin/godot"), "--headless", "--path", str(project), "--script", "res://tests/forgeblade_migration_test.gd"]
tracked = ["tests/forgeblade_migration_test.gd", "scripts/save/canonical_build_rules.gd", "scripts/save/canonical_build_store.gd", "scripts/save/faster_burn_migration.gd", "scripts/save/forgeblade_migration.gd", "scripts/canonical_game_state.gd", "scripts/items/equipment_catalog.gd", "scripts/items/forgeblade_profile.gd", "scripts/items/unified_item_catalog.gd", "scripts/passives/source_tree_runtime.gd"]
inputs = {name: hashlib.sha256((project / name).read_bytes()).hexdigest() for name in tracked if (project / name).is_file()}
started = time.time()
result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=120)
output = result.stdout + result.stderr
suffix = run_root.name.rsplit(".", 1)[-1]
log = qa / f"forgeblade-migration-{suffix}.log"
log.write_text(output)
record = {"test": "forgeblade_migration", "command": command, "exit_code": result.returncode, "elapsed_seconds": round(time.time() - started, 3), "log": log.name, "xdg_data": env["XDG_DATA_HOME"], "script_errors": any(marker in output for marker in ("SCRIPT ERROR:", "Parse Error:", "ERROR:")), "source_sha256": inputs}
(qa / f"evidence-{suffix}.json").write_text(json.dumps(record, indent=2) + "\n")
print(output, flush=True)
if result.returncode or record["script_errors"] or "0 failures" not in output:
    raise SystemExit(result.returncode or 1)
