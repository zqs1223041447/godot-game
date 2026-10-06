#!/usr/bin/env python3
"""Bounded actual-Main acceptance; imports are deliberately never run here."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

BASE = "587c195d2a78c2028f1ae781b3aa460426fc898c"
ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/combat_outcome_gameplay_test.gd"
QA = ROOT / "docs/qa/v077-gameplay"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sources(root: Path, enforce_base: bool = False) -> dict:
    raw = subprocess.check_output(["git", "ls-tree", "-rz", BASE], cwd=root)
    result = {}
    for entry in raw.split(b"\0"):
        if not entry:
            continue
        meta, name = entry.split(b"\t", 1)
        path = name.decode()
        if not (path.startswith(("scripts/", "scenes/", "data/")) or path == "project.godot"):
            continue
        data = (root / path).read_bytes()
        blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        expected = meta.split()[2].decode()
        if enforce_base and blob != expected:
            raise RuntimeError(f"Frozen source differs from {BASE}: {path}")
        result[path] = {"sha256": digest(data), "git_blob": blob, "base_blob": expected}
    return result


def execute(label: str, root: Path, env_extra: dict, godot: str) -> dict:
    isolated = Path(tempfile.mkdtemp(prefix=f"godot-m1-v077-{label}-"))
    env = dict(os.environ, XDG_DATA_HOME=str(isolated / "data"),
               XDG_CONFIG_HOME=str(isolated / "config"), XDG_CACHE_HOME=str(isolated / "cache"))
    env.update(env_extra)
    log = QA / f"{label}.log"
    start = time.monotonic()
    command = [godot, "--headless", "--path", str(root), "--script", str(FIXTURE)]
    print(f"RUN {label}", flush=True)
    try:
        with log.open("w") as stream:
            proc = subprocess.run(command, cwd=root, env=env, stdout=stream,
                                  stderr=subprocess.STDOUT, timeout=45)
        output = log.read_text()
        result = {"label": label, "exit": proc.returncode, "seconds": round(time.monotonic()-start, 3),
                  "log": str(log.relative_to(ROOT)), "log_sha256": digest(log.read_bytes()),
                  "isolated_data": str(isolated), "command": command}
        (QA / f"{label}-run.json").write_text(json.dumps(result, indent=2)+"\n")
        if proc.returncode or "SCRIPT ERROR" in output or "ERROR:" in output:
            print(output, flush=True)
            raise RuntimeError(f"{label} failed: {result}")
        print(output.strip(), flush=True)
        return result
    except BaseException:
        print(f"Preserved failure log: {log}", flush=True)
        raise


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["gameplay", "legacy", "all"], default="all")
    parser.add_argument("--sections", default="")
    parser.add_argument("--label", default="first")
    parser.add_argument("--baseline", type=Path, default=ROOT.parent / "v076-source-shield-recharge")
    parser.add_argument("--godot", default="/usr/local/bin/godot")
    args = parser.parse_args()
    QA.mkdir(parents=True, exist_ok=True)
    before = sources(ROOT)
    version_env = dict(os.environ, XDG_CACHE_HOME=tempfile.mkdtemp(prefix="godot-m1-v077-version-"))
    manifest = {"base": BASE, "godot": subprocess.check_output([args.godot, "--version"], text=True, env=version_env, stderr=subprocess.DEVNULL).strip(),
                "fixture_sha256": digest(FIXTURE.read_bytes()), "current": before}
    if args.mode in ("legacy", "all"):
        manifest["frozen"] = sources(args.baseline, enforce_base=True)
        if not (args.baseline / ".godot/global_script_class_cache.cfg").is_file():
            raise RuntimeError("Existing frozen import cache is required; runner never imports")
    manifest_path = QA / f"{args.label}-sources.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True)+"\n")
    results = []
    if args.mode in ("gameplay", "all"):
        label = f"{args.label}-gameplay"
        results.append(execute(label, ROOT, {"OUTCOME_GAMEPLAY_REPORT":str(QA / f"{label}.json"),
                                            "OUTCOME_GAMEPLAY_SECTIONS":args.sections}, args.godot))
    if args.mode in ("legacy", "all"):
        for version, root in [("v076",args.baseline),("v077",ROOT)]:
            label = f"{args.label}-{version}"
            results.append(execute(label, root, {"OUTCOME_LEGACY_OUTPUT":str(QA / label)}, args.godot))
        comparison = {}
        for suffix in (".bin", ".save"):
            old = (QA / f"{args.label}-v076{suffix}").read_bytes()
            new = (QA / f"{args.label}-v077{suffix}").read_bytes()
            comparison[suffix] = {"equal":old==new,"bytes":len(old),"old_sha256":digest(old),"new_sha256":digest(new)}
        (QA / f"{args.label}-comparison.json").write_text(json.dumps(comparison,indent=2)+"\n")
        if not all(value["equal"] for value in comparison.values()):
            raise RuntimeError(f"Unprojected legacy bytes differ: {comparison}")
        print("EXACT_LEGACY_MATCH "+json.dumps(comparison),flush=True)
    if sources(ROOT) != before:
        raise RuntimeError("Production sources changed during run; do not claim a frozen acceptance")
    if "frozen" in manifest and sources(args.baseline, enforce_base=True) != manifest["frozen"]:
        raise RuntimeError("Frozen baseline sources changed during run")
    (QA / f"{args.label}-result.json").write_text(json.dumps({"runs":results,"sources":manifest_path.name},indent=2)+"\n")


if __name__ == "__main__":
    main()
