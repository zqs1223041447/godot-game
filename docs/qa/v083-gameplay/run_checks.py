#!/usr/bin/env python3
"""One bounded actual-Main pass, after the parent-owned editor import only."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
ENTRY = "res://tests/ginkgo_map_gameplay_test.gd"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suffix", default="")
    args = parser.parse_args()
    output = HERE / ("results" + args.suffix)
    output.mkdir(exist_ok=True)
    isolated = tempfile.mkdtemp(prefix="godot-m1-v083-ginkgo-")
    env = os.environ.copy()
    env.update(XDG_DATA_HOME=isolated, GINKGO_GAMEPLAY_OUTPUT=str(output), GODOT_SILENCE_ROOT_WARNING="1")
    command = [shutil.which("godot") or "godot", "--headless", "--path", str(ROOT), "--script", ENTRY]
    began = time.monotonic()
    with (output / "main.log").open("w") as log:
        try:
            result = subprocess.run(command, env=env, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=90)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
    receipt = {
        "command":command, "cwd":str(ROOT), "xdg_data_home":isolated,
        "seconds":time.monotonic()-began, "exit_code":code,
        "entry_sha256":hashlib.sha256((ROOT / ENTRY.removeprefix("res://")).read_bytes()).hexdigest(),
        "editor_import":False, "native_window":False,
    }
    (output / "execution.json").write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps(receipt,ensure_ascii=False))
    print((output / "main.log").read_text())
    return code


if __name__ == "__main__":
    raise SystemExit(main())
