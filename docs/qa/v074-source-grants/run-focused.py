#!/usr/bin/env python3
"""Run only the source grant adapter and unchanged SourceTreeData contract checks."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
TESTS = ["tests/source_monster_grants_test.gd", "tests/source_tree_data_test.gd"]


def input_hashes():
    pending = TESTS + ["project.godot"]
    found = {}
    while pending:
        relative = pending.pop()
        if relative in found:
            continue
        source = ROOT / relative
        if not source.is_file():
            continue
        content = source.read_bytes()
        found[relative] = hashlib.sha256(content).hexdigest()
        if source.suffix in {".gd", ".tscn", ".tres", ".godot"}:
            pending.extend(re.findall(r'["\']res://([^"\']+)["\']', content.decode()))
    return dict(sorted(found.items()))


stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
isolation = Path(tempfile.mkdtemp(prefix="godot-v074-source-grants-"))
environment = os.environ.copy()
for key, leaf in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
    environment[key] = str(isolation / leaf)
    (isolation / leaf).mkdir()
before = input_hashes()
runs = []
for test in TESTS:
    command = [os.environ.get("GODOT_BIN", "/usr/local/bin/godot"), "--headless", "--path", str(ROOT), "--script", "res://" + test]
    try:
        process = subprocess.run(command, env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        output, code = process.stdout, process.returncode
    except subprocess.TimeoutExpired as error:
        output = (error.stdout or b"").decode() if isinstance(error.stdout, bytes) else error.stdout or ""
        code = 124
    log = QA / (stamp + "-" + Path(test).stem + ".log.txt")
    log.write_text(output)
    passed = code == 0 and "SCRIPT ERROR:" not in output and "ERROR:" not in output
    runs.append({"test": test, "command": command, "exit_code": code, "passed": passed, "log": log.name})
    print(output, end="")
after = input_hashes()
receipt = {"utc": stamp, "scope": "source monster grant adapter plus SourceTreeData public contract", "shared_import": "performed by parent before these runs", "isolation": str(isolation), "runs": runs, "inputs_before": before, "inputs_after": after, "inputs_unchanged": before == after, "passed": all(run["passed"] for run in runs) and before == after}
path = QA / (stamp + "-receipt.json")
path.write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps({"receipt": str(path), "passed": receipt["passed"], "inputs_unchanged": receipt["inputs_unchanged"]}))
raise SystemExit(0 if receipt["passed"] else 1)
