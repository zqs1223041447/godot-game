#!/usr/bin/env python3
"""Resume with isolated cases after the preserved first fixture-path error."""
from pathlib import Path
import hashlib
import json
import os
import selectors
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / "docs/qa/v095-profile"
COMMAND = ["/usr/local/bin/godot", "--headless", "--path", str(ROOT), "--script", "res://tools/diagnostics/burn_profile_allocation_audit.gd"]
RUNS = json.loads((QA / "run_manifest.json").read_text())


def run_one(label, instrumented, mode):
    output = QA / (label + ".json")
    log = QA / (label + ".txt")
    if output.exists() or log.exists():
        raise RuntimeError("Refusing an implicit rerun: " + label)
    isolated = Path(tempfile.mkdtemp(prefix="godot-m1-v095-" + label + "-"))
    env = os.environ.copy()
    env.update({"XDG_DATA_HOME": str(isolated / "data"), "XDG_CACHE_HOME": str(isolated / "cache"), "XDG_CONFIG_HOME": str(isolated / "config"), "V095_INSTRUMENTED": str(int(instrumented)), "V095_PROFILE_OUT": str(output), "V095_MODE": mode})
    record = {"label": label, "command": COMMAND, "environment": {k: env[k] for k in ["XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "V095_INSTRUMENTED", "V095_PROFILE_OUT", "V095_MODE"]}, "frames": {mode: {"ember_deaths": 20, "no_burn": 4}[mode]}, "started_at_unix": time.time()}
    RUNS.append(record)
    (QA / "run_manifest.json").write_text(json.dumps(RUNS, indent=2) + "\n")
    print("START " + label + " " + json.dumps(record), flush=True)
    process = subprocess.Popen(COMMAND, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    start = time.monotonic()
    buffer = b""
    failed = ""
    complete = False
    with log.open("wb") as handle:
        while selector.get_map():
            if time.monotonic() - start > 90:
                failed = "External 90-second watchdog"
                os.killpg(process.pid, signal.SIGKILL)
                break
            for key, _ in selector.select(timeout=0.1):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                handle.write(chunk)
                handle.flush()
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    text = line.decode("utf-8", errors="replace")
                    print(text, flush=True)
                    if "ERROR" in text or "Assertion failed" in text:
                        failed = text
                        os.killpg(process.pid, signal.SIGKILL)
                        break
                    complete = complete or "V095_BURN_PROFILE_AUDIT_COMPLETE" in text
                if failed:
                    break
            if failed:
                break
    exit_code = process.wait(timeout=10)
    record.update({"exit_code": exit_code, "elapsed_seconds": time.monotonic() - start, "first_error": failed, "completion_marker": complete})
    (QA / "run_manifest.json").write_text(json.dumps(RUNS, indent=2) + "\n")
    if failed or exit_code != 0 or not complete:
        raise RuntimeError("Stopped diagnostic; no further process will run: " + (failed or str(exit_code)))
    return json.loads(output.read_text())


def digest(data):
    return hashlib.sha256(data).hexdigest()


assert len(RUNS) == 1 and RUNS[0]["first_error"] == "ERROR: Fresh diagnostic save rejected", "Only the explicitly approved first attempt may resume"
clean = json.loads((QA / "clean.json").read_text())
assert len(clean["rows"]) == 1 and clean["rows"][0]["mode"] == "ember_deaths" and clean["rows"][0]["frames"] == 20
initial_row = clean["rows"][0]
for suffix, hash_key, size_key in [(".bin", "observation_sha256", "observation_bytes"), ("-final.bin", "final_observation_sha256", "final_observation_bytes")]:
    previous = (QA / ("clean-ember_deaths" + suffix)).read_bytes()
    assert len(previous) == initial_row[size_key] and digest(previous) == initial_row[hash_key]
assert len(initial_row["samples"]) == 20
json.loads((QA / "clean-ember_deaths.save").read_text())
# Preserve all first-attempt evidence; the completed ember case is not repeated.
clean_control = run_one("clean_no_burn", False, "no_burn")
instrumented = run_one("instrumented_ember", True, "ember_deaths")
instrumented_control = run_one("instrumented_no_burn", True, "no_burn")
clean["rows"].extend(clean_control["rows"])
instrumented["rows"].extend(instrumented_control["rows"])
(QA / "clean_completed.json").write_text(json.dumps(clean, indent=2) + "\n")
(QA / "instrumented_completed.json").write_text(json.dumps(instrumented, indent=2) + "\n")
checks = []
for left, right in zip(clean["rows"], instrumented["rows"], strict=True):
    mode = left["mode"]
    assert mode == right["mode"]
    assert left["frames"] == right["frames"] == {"ember_deaths": 20, "no_burn": 4}[mode]
    for lframe, rframe in zip(left["samples"], right["samples"], strict=True):
        assert lframe["frame"] == rframe["frame"]
        assert lframe["observation_sha256"] == rframe["observation_sha256"], (mode, lframe["frame"])
    for suffix in [".bin", "-final.bin", ".save"]:
        clean_prefix = "clean" if mode == "ember_deaths" else "clean_no_burn"
        instrumented_prefix = "instrumented_ember" if mode == "ember_deaths" else "instrumented_no_burn"
        a = (QA / (clean_prefix + "-" + mode + suffix)).read_bytes()
        b = (QA / (instrumented_prefix + "-" + mode + suffix)).read_bytes()
        assert a == b, (mode, suffix, digest(a), digest(b))
        checks.append({"mode": mode, "suffix": suffix, "exact_bytes_equal": True, "bytes": len(a), "sha256": digest(a)})
    for frame in right["samples"]:
        meter = frame["meter"]
        for phase in ["planning", "settlement", "other"]:
            counts = [meter[k + "/" + phase]["calls"] for k in ["incoming_burn", "defense_profile_body", "defense_profile_call_envelope"]]
            assert len(set(counts)) == 1, (mode, frame["frame"], phase, counts)
    print("EXACT_OBSERVATION_ACCEPTED " + mode + " " + str(left["frames"]) + " frames and final save", flush=True)
result = {"accepted": True, "checks": checks, "per_frame_sha256_equal": True, "incoming_profile_call_counts_equal": True, "production_improvement_claim": False}
(QA / "verification.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2), flush=True)
