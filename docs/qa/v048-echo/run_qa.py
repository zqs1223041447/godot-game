#!/usr/bin/env python3
"""Focused headless evidence. Terminate Godot immediately on engine/script errors."""
import hashlib
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time

PROJECT = Path(__file__).resolve().parents[3]
EVIDENCE = Path(__file__).resolve().parent
PACK = PROJECT.parent / "v047-final-release/game.pck"
ISOLATION = Path("/tmp/godot-m1-v048-echo")
CAPTURE = EVIDENCE / "capture_legacy.gd"
SOURCES = [
    "scripts/combat/telegraphed_area_runtime.gd",
    "scripts/monsters/map_boss_profiles.gd",
    "scripts/monsters/monster_catalog.gd",
    "scripts/monsters/telegraph_profiles.gd",
    "scripts/world/map_admission.gd",
    "scripts/world/map_compiler.gd",
    "tests/sunwell_echo_runtime_test.gd",
    "docs/qa/v048-echo/capture_legacy.gd",
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(label, args):
    env = dict(os.environ)
    for variable, subdir in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        destination = ISOLATION / label / subdir
        destination.mkdir(parents=True, exist_ok=True)
        env[variable] = str(destination)
    command = ["godot", "--headless"] + args
    started = time.monotonic()
    log_path = EVIDENCE / (label + ".log.txt")
    attempt = 1
    while log_path.exists():
        attempt += 1
        log_path = EVIDENCE / (label + "-run%d.log.txt" % attempt)
    status = {"command": command, "cwd": str(PROJECT), "isolation": str(ISOLATION / label), "log": log_path.name}
    with log_path.open("w") as log:
        log.write("COMMAND " + json.dumps(command) + "\n")
        log.flush()
        process = subprocess.Popen(command, cwd=PROJECT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        captured = b""
        terminated = False
        while selector.get_map():
            for key, _ in selector.select(0.1):
                chunk = os.read(key.fd, 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                captured += chunk
                decoded = chunk.decode("utf-8", errors="replace")
                log.write(decoded)
                log.flush()
                sys.stdout.write(decoded)
                sys.stdout.flush()
                if not terminated and any(marker in captured for marker in [b"SCRIPT ERROR:", b"ERROR:", b"Parse Error:"]):
                    status["stopped_on_error"] = True
                    process.terminate()
                    terminated = True
            if time.monotonic() - started > 90 and not terminated:
                status["timeout"] = True
                process.terminate()
                terminated = True
            if terminated and process.poll() is None:
                try:
                    process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    process.kill()
        status["exit_code"] = process.wait()
        status["elapsed_seconds"] = round(time.monotonic() - started, 3)
        log.write("\nSTATUS " + json.dumps(status) + "\n")
    return status


def main():
    initial = {path: sha(PROJECT / path) for path in SOURCES}
    manifest = {"scope": "Pure Echo scheduler and six unfiltered legacy telegraph trajectories; no GUI, renderer or main damage settlement",
                "pack": {"path": str(PACK), "sha256": sha(PACK)}, "files_before": initial, "runs": []}
    labels = sys.argv[1:] or ["legacy-v047", "legacy-v048", "focused"]
    commands = {
        "legacy-v047": ["--main-pack", str(PACK), "--script", str(CAPTURE), "--", "--out=" + str(EVIDENCE / "legacy-v047.bin")],
        "legacy-v048": ["--path", str(PROJECT), "--script", str(CAPTURE), "--", "--out=" + str(EVIDENCE / "legacy-v048.bin")],
        "focused": ["--path", str(PROJECT), "--script", "res://tests/sunwell_echo_runtime_test.gd"],
    }
    for label in labels:
        result = run(label, commands[label])
        manifest["runs"].append(result)
        if result["exit_code"] or result.get("stopped_on_error") or result.get("timeout"):
            break
    manifest["files_after"] = {path: sha(PROJECT / path) for path in SOURCES}
    for filename in ["legacy-v047.bin", "legacy-v048.bin"]:
        path = EVIDENCE / filename
        if path.exists(): manifest[filename] = {"size": path.stat().st_size, "sha256": sha(path)}
    if all((EVIDENCE / filename).exists() for filename in ["legacy-v047.bin", "legacy-v048.bin"]):
        manifest["legacy_bytes_equal"] = (EVIDENCE / "legacy-v047.bin").read_bytes() == (EVIDENCE / "legacy-v048.bin").read_bytes()
    manifest_path = EVIDENCE / ("tested-files-" + "-".join(labels) + ".json")
    attempt = 1
    while manifest_path.exists():
        attempt += 1
        manifest_path = EVIDENCE / ("tested-files-" + "-".join(labels) + "-run%d.json" % attempt)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    return 1 if any(result["exit_code"] or result.get("stopped_on_error") or result.get("timeout") for result in manifest["runs"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())
