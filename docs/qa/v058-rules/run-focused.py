#!/usr/bin/env python3
"""Run only the v058 pure rules fixture, after the parent's shared import."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

PROJECT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
SCRIPT = "tests/mana_guard_rules_test.gd"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def as_text(value: str | bytes | None) -> str:
    return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else (value or "")


def main() -> int:
    if sys.platform != "linux":
        print("Requires Linux /tmp and XDG isolation", file=sys.stderr)
        return 78
    if not (PROJECT / ".godot/global_script_class_cache.cfg").is_file():
        print("Wait for the parent's shared import; this runner never imports", file=sys.stderr)
        return 78
    run_root = Path(tempfile.mkdtemp(prefix="godot-m1-v058-rules-", dir="/tmp"))
    env = os.environ.copy()
    for kind in ("DATA", "CONFIG", "CACHE"):
        target = run_root / kind.lower()
        target.mkdir()
        env[f"XDG_{kind}_HOME"] = str(target)
    command = [
        env.get("GODOT_BIN", "/usr/local/bin/godot"), "--headless", "--path",
        str(PROJECT), "--script", f"res://{SCRIPT}",
    ]
    # Fingerprint only this pure test's complete inputs, so unrelated ongoing
    # integration edits do not invalidate or race its independent evidence.
    paths = [PROJECT / SCRIPT, Path(__file__).resolve(),
             PROJECT / "scripts/mechanics/defense_rules.gd",
             PROJECT / "scripts/combat/damage_resolver.gd",
             QA / "v057-defense-rules.txt", PROJECT / "project.godot"]
    inputs = {str(path.relative_to(PROJECT)): digest(path) for path in paths}
    started = time.monotonic()
    timed_out = False
    try:
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        exit_code = result.returncode
    except subprocess.TimeoutExpired as error:
        timed_out = True
        output = as_text(error.stdout) + as_text(error.stderr) + "\n60-second process guard exceeded\n"
        exit_code = 124
    except OSError as error:
        output = f"Could not start Godot: {error}\n"
        exit_code = 127
    token = run_root.name.removeprefix("godot-m1-v058-rules-")
    log_path = QA / f"rules-{token}.log.txt"
    log_path.write_text(output, encoding="utf-8")
    matches = re.findall(r"^MANA_GUARD_RULES (.+)$", output, re.MULTILINE)
    summary = json.loads(matches[-1]) if matches else {}
    changed = [str(path.relative_to(PROJECT)) for path in paths
               if not path.is_file() or digest(path) != inputs[str(path.relative_to(PROJECT))]]
    script_errors = any(marker in output for marker in ("SCRIPT ERROR:", "Parse Error:", "ERROR:"))
    passed = (exit_code == 0 and not script_errors and not changed
              and summary.get("checks", 0) > 0 and summary.get("failures") == 0
              and summary.get("legacy_typed_byte_cases", 0) > 0)
    record = {
        "scope": "v058 pure mana-before-life Defense rules and independent v57 typed-byte baseline",
        "command": command, "exit_code": exit_code,
        "elapsed_seconds": round(time.monotonic() - started, 3),
        "timed_out": timed_out, "script_errors": script_errors, "passed": passed,
        "summary": summary, "log": log_path.name, "log_sha256": digest(log_path),
        "isolated_userdata": env["XDG_DATA_HOME"], "source_sha256": inputs,
        "changed_inputs": changed, "import_performed": False,
    }
    evidence = QA / f"evidence-{token}.json"
    evidence.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(output, end="" if output.endswith("\n") else "\n", flush=True)
    print(f"Evidence: {evidence.relative_to(PROJECT)}", flush=True)
    return 0 if passed else (exit_code or 1)


if __name__ == "__main__":
    raise SystemExit(main())
