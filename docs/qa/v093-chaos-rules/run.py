#!/usr/bin/env python3
"""Run only the v093 pure defense script after the shared project import."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

project = Path(__file__).resolve().parents[3]
output = Path(__file__).resolve().parent
engine = os.environ.get("GODOT_BIN", "godot")
if not (project / ".godot/global_script_class_cache.cfg").is_file():
    raise SystemExit("Wait for the coordinator's shared project import; this runner never imports.")
command = [engine, "--headless", "--path", str(project), "--script", "res://tests/chaos_resistance_rules_test.gd"]
with tempfile.TemporaryDirectory(prefix="godot-m1-v093-chaos-rules-", dir="/tmp") as temporary:
    sandbox = Path(temporary)
    environment = os.environ.copy()
    for key, directory in {"XDG_DATA_HOME": "data", "XDG_CONFIG_HOME": "config", "XDG_CACHE_HOME": "cache", "XDG_STATE_HOME": "state", "XDG_RUNTIME_DIR": "runtime"}.items():
        location = sandbox / directory
        location.mkdir(mode=0o700)
        environment[key] = str(location)
    environment.update(GODOT_SILENCE_ROOT_WARNING="1", CHAOS_RULES_REPORT=str(output / "chaos-rules.json"))
    started = time.monotonic()
    result = subprocess.run(command, cwd=project, env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
    elapsed = time.monotonic() - started
    (output / "chaos-rules.log").write_text(result.stdout)
    print(result.stdout, end="")
    errors = bool(re.search(r"(^|\s)(SCRIPT ERROR:|ERROR:)", result.stdout))
    success = result.returncode == 0 and not errors and "CHAOS_RESISTANCE_RULES " in result.stdout
    paths = ["scripts/mechanics/defense_rules.gd", "scripts/combat/damage_resolver.gd", "scripts/combat/hit_penetration_rules.gd", "tests/chaos_resistance_rules_test.gd"]
    record = {"command": command, "engine": shutil.which(engine) or engine, "exit_code": result.returncode, "engine_errors": errors, "elapsed_seconds": round(elapsed, 3), "passed": success, "engine_import_invoked": False, "isolation": "Independent disposable /tmp/godot-m1-v093-chaos-rules-* XDG roots", "input_sha256": {path: hashlib.sha256((project / path).read_bytes()).hexdigest() for path in paths}}
    (output / "run-record.json").write_text(json.dumps(record, indent=2) + "\n")
    raise SystemExit(0 if success else 1)
