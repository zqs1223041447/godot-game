#!/usr/bin/env python3
"""Run only the camp roster/state script in a small temporary Godot project."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
OUTPUT = Path(__file__).resolve().parent
TEST = "tests/map_camp_state_test.gd"


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="v043-roster-") as scratch:
        project = Path(scratch)
        pending = [TEST]
        copied: dict[str, dict[str, str | int]] = {}
        while pending:
            relative = pending.pop(0)
            if relative in copied:
                continue
            source = ROOT / relative
            target = project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            content = target.read_bytes()
            copied[relative] = {"bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()}
            if source.suffix in {".gd", ".json"}:
                for dependency in re.findall(r'res://([^"\s]+)', content.decode()):
                    if (ROOT / dependency).is_file():
                        pending.append(dependency)
            if source.suffix == ".gd" and Path(str(source) + ".uid").is_file():
                pending.append(relative + ".uid")
        (project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="Isolated v043 roster state"\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        )
        env = os.environ.copy()
        for suffix, variable in (("data", "XDG_DATA_HOME"), ("config", "XDG_CONFIG_HOME"), ("cache", "XDG_CACHE_HOME")):
            directory = project / "xdg" / suffix
            directory.mkdir(parents=True)
            env[variable] = str(directory)
        (project / "xdg/cache/fontconfig").mkdir()
        command = [env.get("GODOT_BIN", "godot"), "--headless", "--path", str(project), "--script", "res://" + TEST]
        run = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=45)
        (OUTPUT / "roster-test.log.txt").write_text(run.stdout)
        failed = run.returncode != 0 or bool(re.search(r"(^|\s)(SCRIPT ERROR:|ERROR:)", run.stdout))
        evidence = {
            "scope": "Pure roster/state helper plus actual layout output compatibility; no scene/UI/factory run",
            "command": [*command[:3], "<isolated temporary project>", *command[4:]],
            "exit_code": run.returncode,
            "passed": not failed,
            "source_files": copied,
        }
        (OUTPUT / "roster-tested-files.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
        print(run.stdout, end="")
        return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
