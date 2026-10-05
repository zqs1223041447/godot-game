#!/usr/bin/env python3
"""Run the v057 compatibility fixture once, after the shared first import."""
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
SCRIPT = "tests/passive_localization_compatibility_test.gd"
SUMMARY = re.compile(
    r"Passive localization compatibility: (\d+) checks, (\d+) failures; (\d+) read-only phases"
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def as_text(value: str | bytes | None) -> str:
    return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else (value or "")


def main() -> int:
    if sys.platform != "linux":
        print("This fixture requires Linux /tmp and XDG userdata isolation", file=sys.stderr)
        return 78
    if not (PROJECT / ".godot/global_script_class_cache.cfg").is_file():
        print("Run the parent's shared first import before this runner; this runner never imports", file=sys.stderr)
        return 78
    run_root = Path(tempfile.mkdtemp(prefix="godot-m1-v057-compat.", dir="/tmp"))
    env = os.environ.copy()
    for kind in ("DATA", "CONFIG", "CACHE"):
        target = run_root / kind.lower()
        target.mkdir()
        env[f"XDG_{kind}_HOME"] = str(target)
    command = [
        env.get("GODOT_BIN", "/usr/local/bin/godot"),
        "--headless", "--path", str(PROJECT), "--script", f"res://{SCRIPT}",
    ]
    # Guard the entire authored production script/data/scene inventory, including
    # the English source and Chinese map; exclude generated .godot import files.
    production = sorted({
        path
        for directory in ("scripts", "data", "scenes")
        for path in (PROJECT / directory).rglob("*")
        if path.is_file() and path.suffix not in {".uid", ".import"}
    } | {PROJECT / "project.godot"})
    tracked = production + [PROJECT / SCRIPT, Path(__file__).resolve()]
    inputs = {str(path.relative_to(PROJECT)): digest(path) for path in tracked}
    started = time.monotonic()
    timed_out = False
    launch_error = ""
    try:
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        exit_code = result.returncode
    except subprocess.TimeoutExpired as error:
        timed_out = True
        output = as_text(error.stdout) + as_text(error.stderr)
        output += "\nCompatibility runner exceeded its 60-second process guard\n"
        exit_code = 124
    except OSError as error:
        launch_error = str(error)
        output = f"Could not start Godot: {error}\n"
        exit_code = 127
    token = run_root.name.rsplit(".", 1)[-1]
    log_path = QA / f"compatibility-{token}.log.txt"
    log_path.write_text(output, encoding="utf-8")
    match = SUMMARY.search(output)
    changed = [
        str(path.relative_to(PROJECT)) for path in tracked
        if not path.is_file() or digest(path) != inputs[str(path.relative_to(PROJECT))]
    ]
    script_errors = any(marker in output for marker in ("SCRIPT ERROR:", "Parse Error:", "ERROR:"))
    checks = int(match[1]) if match else None
    failures = int(match[2]) if match else None
    readonly_phases = int(match[3]) if match else None
    passed = (
        exit_code == 0 and not script_errors and not changed
        and checks is not None and checks > 0 and failures == 0
        and readonly_phases is not None and readonly_phases >= 19
    )
    record = {
        "scope": "v057 localized passive tree display/state compatibility only",
        "command": command,
        "exit_code": exit_code,
        "elapsed_seconds": round(time.monotonic() - started, 3),
        "timed_out": timed_out,
        "launch_error": launch_error,
        "script_errors": script_errors,
        "checks": checks,
        "failures": failures,
        "readonly_phases": readonly_phases,
        "passed": passed,
        "log": log_path.name,
        "log_sha256": digest(log_path),
        "isolated_userdata": env["XDG_DATA_HOME"],
        "source_sha256": inputs,
        "changed_inputs": changed,
        "production_file_count": len(production),
        "source_unchanged_during_run": not changed,
        "import_performed": False,
    }
    evidence = QA / f"evidence-{token}.json"
    evidence.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(output, end="" if output.endswith("\n") else "\n", flush=True)
    print(f"Evidence: {evidence.relative_to(PROJECT)}", flush=True)
    return 0 if passed else (exit_code or 1)


if __name__ == "__main__":
    raise SystemExit(main())
