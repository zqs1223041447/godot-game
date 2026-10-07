#!/usr/bin/env python3
"""One v095 typed-byte rules check; no import, benchmark, or historical suite."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
BASE = "eaf298a8cbd22c8387da28da118a15afdcd2afb5"
TEST = "tests/burn_profile_shortcut_equivalence_test.gd"
DEFENSE = "scripts/mechanics/defense_rules.gd"
REFERENCE_PATTERN = re.compile(r'(?:preload|load)\s*\(\s*[\"\']res://([^\"\']+)[\"\']\s*\)')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def write_json(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2) + "\n")


def verify_git_oracle():
    manifest = json.loads((OUT / "manifest.json").read_text())
    assert manifest["source_commit"] == BASE
    assert len(manifest["entries"]) == 1
    oracle = manifest["entries"][0]
    assert oracle["path"] == DEFENSE
    source = git("show", f"{BASE}:{DEFENSE}")
    assert git("rev-parse", f"{BASE}:{DEFENSE}").decode().strip() == oracle["git_blob"]
    assert digest(source) == oracle["source_sha256"]
    assert (OUT / "source" / (DEFENSE + ".txt")).read_bytes() == source
    frozen = re.sub(rb"^class_name [^\n]+\n", b"", source, flags=re.M)
    assert (OUT / "frozen" / DEFENSE).read_bytes() == frozen
    assert digest(frozen) == oracle["frozen_sha256"]
    dependencies = {item["path"]: item for item in manifest["shared_dependency_closure"]}
    visited, pending = set(), REFERENCE_PATTERN.findall(source.decode())
    while pending:
        path = pending.pop()
        if path in visited:
            continue
        visited.add(path)
        entry = dependencies[path]
        baseline = git("show", f"{BASE}:{path}")
        assert git("rev-parse", f"{BASE}:{path}").decode().strip() == entry["git_blob"]
        assert digest(baseline) == entry["source_sha256"]
        assert (ROOT / path).read_bytes() == baseline, path
        pending.extend(REFERENCE_PATTERN.findall(baseline.decode()))
    assert visited == set(dependencies), "Shared dependency manifest must cover full literal preload/load closure"
    current = (ROOT / DEFENSE).read_text()
    function_pattern = r"(?ms)^static func (\w+)\(.*?(?=^static func |\Z)"
    old_functions = {m.group(1): m.group(0) for m in re.finditer(function_pattern, source.decode())}
    new_functions = {m.group(1): m.group(0) for m in re.finditer(function_pattern, current)}
    assert old_functions.keys() == new_functions.keys()
    changed = [name for name in old_functions if old_functions[name] != new_functions[name]]
    assert changed == ["incoming_burn"], changed
    return {
        "oracle_git_blob": oracle["git_blob"],
        "shared_dependency_paths": sorted(visited),
        "shared_dependency_closure_matches_baseline": True,
        "changed_production_functions": changed,
        "independently_frozen_full_closure": False,
    }


def main():
    assert (ROOT / ".godot/global_script_class_cache.cfg").is_file(), "Coordinator import must already exist; this runner does not import"
    assert not (OUT / "run-record.json").exists(), "Preserve the first run; do not overwrite or repeat evidence"
    initial = verify_git_oracle()
    paths = sorted({DEFENSE, TEST, "project.godot", "docs/qa/v095-rules/run.py",
                    "docs/qa/v095-rules/manifest.json", "docs/qa/v095-rules/source/" + DEFENSE + ".txt",
                    "docs/qa/v095-rules/frozen/" + DEFENSE, *initial["shared_dependency_paths"]})
    before = {path: digest((ROOT / path).read_bytes()) for path in paths}
    write_json("input-sha256-before.json", before)
    engine = shutil.which("godot") or "/usr/local/bin/godot"
    command = [engine, "--headless", "--path", str(ROOT), "--script", "res://" + TEST]
    isolation = Path(tempfile.mkdtemp(prefix="godot-m1-v095-rules-", dir="/tmp"))
    env = os.environ.copy()
    for key, name in {"XDG_DATA_HOME": "data", "XDG_CONFIG_HOME": "config", "XDG_CACHE_HOME": "cache",
                      "XDG_STATE_HOME": "state", "XDG_RUNTIME_DIR": "runtime"}.items():
        location = isolation / name
        location.mkdir(mode=0o700)
        env[key] = str(location)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    record = {
        "baseline_commit": BASE, "command": command,
        "isolation": str(isolation), "xdg": {key: value for key, value in env.items() if key.startswith("XDG_")},
        "verification_start": initial, "engine_import_invoked": False, "microbenchmark_run": False,
        "historical_suite_run": False, "started_at_unix": time.time(),
    }
    write_json("run-start.json", record)
    started = time.monotonic()
    code, stdout, stderr = None, b"", b""
    try:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        code, stdout, stderr = result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired as error:
        stdout, stderr = error.stdout or b"", error.stderr or b""
        record["timeout_seconds"] = 60
    except Exception as error:
        record["runner_error"] = repr(error)
    finally:
        (OUT / "stdout.log.txt").write_bytes(stdout)
        (OUT / "stderr.log.txt").write_bytes(stderr)
        after = {path: digest((ROOT / path).read_bytes()) for path in paths}
        write_json("input-sha256-after.json", after)
        record.update(exit_code=code, elapsed_seconds=round(time.monotonic() - started, 6), input_hashes_unchanged=before == after)
        try:
            record["verification_finish"] = verify_git_oracle()
        except Exception as error:
            record["verification_finish_error"] = repr(error)
        merged = (stdout + stderr).decode(errors="replace")
        record["engine_errors"] = bool(re.search(r"(^|\s)(SCRIPT ERROR:|ERROR:)", merged))
        record["passed"] = (code == 0 and not record["engine_errors"] and before == after
                            and "verification_finish_error" not in record
                            and "BURN_PROFILE_SHORTCUT_EQUIVALENCE " in merged)
        write_json("run-record.json", record)
    print(stdout.decode(errors="replace"), end="")
    print(stderr.decode(errors="replace"), end="")
    print(json.dumps({key: record[key] for key in ["passed", "exit_code", "elapsed_seconds", "engine_errors", "input_hashes_unchanged"]}))
    return 0 if record["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
