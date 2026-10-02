#!/usr/bin/env python3
"""Run save-identity regressions only after probing a disposable Linux project."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile
import uuid


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    args = parser.parse_args()
    if platform.system() != "Linux":
        parser.error("This runner requires native Linux; use the Windows isolated runner there.")
    source = Path(__file__).resolve().parents[1]
    sandbox = Path(tempfile.mkdtemp(prefix="godot-save-linux-"))
    token = uuid.uuid4().hex
    project = sandbox / "中文 工程"
    project.mkdir()
    userdata = sandbox / "data" / ("存档 沙箱 " + token)
    settings = {'config/name': 'Linux Save QA ' + token,
                'config/use_custom_user_dir': True,
                'config/custom_user_dir_name': '存档 沙箱 ' + token}
    (project / "project.godot").write_text('config_version=5\n[application]\n' +
        '\n'.join(key + '=' + json.dumps(value, ensure_ascii=False) for key, value in settings.items()) + '\n', encoding="utf-8")
    pending = ["scripts/build_state.gd", "tests/windows/save_linux_identity_test.gd"]
    copied: dict[str, str] = {}
    while pending:
        relative = pending.pop()
        if relative in copied:
            continue
        path = source / relative
        if not path.resolve().is_relative_to(source):
            raise RuntimeError("Dependency escapes repository: " + relative)
        if path.is_dir():
            pending.extend(str(item.relative_to(source)) for item in path.rglob("*") if item.is_file())
            continue
        if not path.is_file():
            raise RuntimeError("Missing literal dependency: " + relative)
        data = path.read_bytes()
        target = project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        copied[relative] = hashlib.sha256(data).hexdigest()
        if path.suffix == ".gd":
            pending.extend(re.findall(r'''res://([^"'\r\n]+)''', data.decode("utf-8")))
    env = os.environ.copy()
    env.update(XDG_DATA_HOME=str(sandbox / "data"), XDG_CONFIG_HOME=str(sandbox / "config"),
        XDG_CACHE_HOME=str(sandbox / "cache"), GODOT_SAVE_QA_ROOT=str(sandbox),
        GODOT_SAVE_QA_PROJECT=str(project), GODOT_SAVE_QA_USERDATA=str(userdata),
        GODOT_SAVE_QA_TOKEN=token)
    env.pop("GODOT_SAVE_QA_PROBE_VERIFIED", None)
    command = [args.godot, "--headless", "--path", str(project), "--script",
               "res://tests/windows/save_linux_identity_test.gd"]
    records = []

    def run(name: str, extra: list[str], overrides: dict[str, str], expected: int) -> str:
        process = subprocess.run(command + extra, env=env | overrides, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        output = process.stdout
        (sandbox / (name + ".log")).write_text(output, encoding="utf-8")
        gates = [json.loads(line.removeprefix("SAVE_QA_GATE ")) for line in output.splitlines()
                 if line.startswith("SAVE_QA_GATE ")]
        if process.returncode != expected or len(gates) != 1 or re.search(r"(?:SCRIPT ERROR:|ERROR:)", output):
            raise RuntimeError(name + " failed; inspect " + str(sandbox))
        gate = gates[0]
        if gate["user_data_dir"] != str(userdata) or gate["project"] != str(project) or gate["token"] != token:
            raise RuntimeError("Actual paths or token differ from isolated contract")
        if gate["ok"] != (expected == 0):
            raise RuntimeError("Unexpected isolation gate state")
        records.append({"name": name, "exit_code": process.returncode, "gate": gate})
        return output

    print("Linux save isolation sandbox: " + str(sandbox), flush=True)
    run("probe", ["--", "probe"], {}, 0)
    run("negative-probe", ["--", "probe"], {"GODOT_SAVE_QA_USERDATA": str(userdata / "mismatch")}, 78)
    output = run("save-identity", [], {"GODOT_SAVE_QA_PROBE_VERIFIED": token}, 0)
    results = [json.loads(line.removeprefix("SAVE_QA_RESULT ")) for line in output.splitlines()
               if line.startswith("SAVE_QA_RESULT ")]
    if len(results) != 1 or results[0]["failures"] != 0 or not results[0]["completed"] or results[0]["checks"] <= 0:
        raise RuntimeError("Missing or failed identity test result")
    for relative, sha in copied.items():
        if hashlib.sha256((source / relative).read_bytes()).hexdigest() != sha:
            raise RuntimeError("Source changed during isolated test: " + relative)
    report = {"ok": True, "sandbox": str(sandbox), "result": results[0], "runs": records,
              "source_sha256": copied, "engine": shutil.which(args.godot) or args.godot}
    (sandbox / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Linux save identity test: %d checks, 0 failures" % results[0]["checks"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
