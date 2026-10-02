#!/usr/bin/env python3
"""Runner integration tests use real fake-engine processes, never game saves."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
RUNNER_PATH = ROOT / "tools/validate_parallel.py"
SPEC = importlib.util.spec_from_file_location("validation_runner", RUNNER_PATH)
runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)

# Frozen actual sources: v0.13.0/a4a306a and v0.14 integration/0db7a1b.
# Independent, offline fixtures preserve the old suite even when the checkout is v0.14.
V013_SHELL = r'''#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"

VALIDATION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/godot-game-validation.XXXXXX")"
trap 'rm -rf -- "$VALIDATION_DIR"' EXIT

# Isolate test settings and saves, including in restricted cloud workspaces.
if [[ "$(uname -s)" == "Linux" ]]; then
	export XDG_DATA_HOME="$VALIDATION_DIR/data"
	export XDG_CONFIG_HOME="$VALIDATION_DIR/config"
	export XDG_CACHE_HOME="$VALIDATION_DIR/cache"
	mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME/fontconfig"
fi

CHECK_INDEX=0
run_check() {
	CHECK_INDEX=$((CHECK_INDEX + 1))
	if [[ "$(uname -s)" == "Linux" ]]; then
		export XDG_DATA_HOME="$VALIDATION_DIR/data/check-$CHECK_INDEX"
		mkdir -p "$XDG_DATA_HOME"
	fi
	local log_file="$VALIDATION_DIR/check.log"
	"$GODOT_BIN" --headless --path "$PROJECT_DIR" "$@" 2>&1 | tee "$log_file"
	# Godot may log a script/import error without a failing process exit code.
	if grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$log_file"; then
		echo "Validation failed: Godot reported an error." >&2
		return 1
	fi
}

echo "Godot version: $("$GODOT_BIN" --version)"
run_check --editor --import
run_check --script res://tests/build_test.gd
run_check --script res://tests/equipment_catalog_test.gd
run_check --script res://tests/typed_affix_catalog_test.gd
run_check --script res://tests/defense_rules_test.gd
run_check --script res://tests/defense_equipment_catalog_test.gd
run_check --script res://tests/defense_equipment_state_test.gd
run_check --script res://tests/local_weapon_compiler_test.gd
run_check --script res://tests/local_weapon_catalog_test.gd
run_check --script res://tests/local_weapon_state_test.gd
run_check --script res://tests/local_weapon_integration_test.gd
run_check --script res://tests/local_weapon_budget_test.gd
run_check --script res://tests/fire_defense_integration_test.gd
run_check --script res://tests/damage_base_test.gd
run_check --script res://tests/damage_preview_test.gd
run_check --script res://tests/typed_damage_state_test.gd
run_check --script res://tests/typed_damage_integration_test.gd
run_check --script res://tests/save_guard_integration_test.gd
run_check --script res://tests/progress_batch_test.gd
run_check --script res://tests/equipment_state_test.gd
run_check --script res://tests/equipment_integration_test.gd
run_check --script res://tests/skill_compiler_test.gd
run_check --script res://tests/skill_support_state_test.gd
run_check --script res://tests/skill_support_integration_test.gd
run_check --script res://tests/skill_support_ui_test.gd
run_check --script res://tests/equipment_soak_test.gd
run_check --script res://tests/passive_jewel_test.gd
run_check --script res://tests/special_jewel_test.gd
run_check --script res://tests/special_jewel_integration_test.gd
run_check --script res://tests/special_jewel_ui_test.gd
run_check --script res://tests/reference_export_test.gd
run_check --script res://tests/reference_launch_test.gd
run_check --script res://tests/mechanic_registry_test.gd
run_check --script res://tests/passive_balance_test.gd
run_check --script res://tests/monster_system_test.gd
run_check --script res://tests/monster_integration_test.gd
run_check --script res://tests/combat_pipeline_test.gd
run_check --script res://tests/spatial_collision_test.gd
run_check --script res://tests/projectile_schedule_test.gd
run_check --script res://tests/density_integration_test.gd
run_check --script res://tests/world_view_test.gd
run_check --script res://tests/fire_visual_test.gd
run_check --script res://tests/combat_integration_test.gd
run_check --script res://tests/smoke_test.gd
run_check --script res://tests/visual_settings_test.gd
run_check --script res://tests/combat_cues_test.gd
run_check --script res://tests/combat_cues_integration_test.gd
run_check --script res://tests/fantasy_actor_test.gd
run_check --script res://tests/equipment_art_test.gd
run_check --script res://tests/material_frame_test.gd
run_check --script res://tests/grimoire_ui_test.gd
run_check --script res://tests/equipment_painterly_art_test.gd
python3 "$PROJECT_DIR/tests/reference_catalog_test.py"
run_check --quit-after 300
echo "Validation passed: import, immutable equipment pools/RNG, scoped local weapon damage and independent balance replay, shared fire defense and natural encounter, transaction-bounded progress flush/exact saved-byte equivalence, schema9 compatibility/byte-exact backups/protected saves/special passive grants/offline reference data and launch wiring, typed hit bases and previews, compiled supports/cast/UI, wide native camera/100 real enemies/spatial-reference equivalence, fantasy artwork/materials and bounded visual cues, build/save model, passive/jewel/balance invariants, shared mechanisms, monster lifecycle/scene, projectile/damage pipeline, combat/UI integration, and 300-frame startup."
'''

V013_PROJECT = r'''; Engine configuration file. Prefer editing through the Godot editor.
config_version=5

[application]

config/name="godot游戏仓"
config/description="裂隙试炼：以装备、天赋和技能组合为核心的平面竞技场原型。"
config/version="0.13.0"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.6", "GL Compatibility")

[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/size/min_width=960
window/size/min_height=540

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
environment/defaults/default_clear_color=Color(0.055, 0.067, 0.09, 1)
'''

V014_SHELL = r'''#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"

# These write tests use Linux XDG isolation. Other platforms need their dedicated
# temporary-project/userdata runner before any default user:// can be touched.
if [[ "$(uname -s)" != "Linux" ]]; then
	echo "Validation requires Linux XDG isolation; use the platform-specific isolated runner." >&2
	exit 2
fi

VALIDATION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/godot-game-validation.XXXXXX")"
PIERCE_VALIDATION_DIR="$(mktemp -d /tmp/godot-pierce-acceptance-XXXXXX)"
trap 'rm -rf -- "$VALIDATION_DIR" "$PIERCE_VALIDATION_DIR"' EXIT

# Isolate test settings and saves, including in restricted cloud workspaces.
if [[ "$(uname -s)" == "Linux" ]]; then
	export XDG_DATA_HOME="$VALIDATION_DIR/data"
	export XDG_CONFIG_HOME="$VALIDATION_DIR/config"
	export XDG_CACHE_HOME="$VALIDATION_DIR/cache"
	mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME/fontconfig"
fi

CHECK_INDEX=0
run_check() {
	CHECK_INDEX=$((CHECK_INDEX + 1))
	if [[ "$(uname -s)" == "Linux" ]]; then
		export XDG_DATA_HOME="$VALIDATION_DIR/data/check-$CHECK_INDEX"
		case "${2:-}" in
			res://tests/pierce_integration_test.gd|res://tests/pierce_ui_test.gd)
				export XDG_DATA_HOME="$PIERCE_VALIDATION_DIR/check-$CHECK_INDEX"
				export PIERCE_QA_ROOT="$XDG_DATA_HOME"
				;;
			*) unset PIERCE_QA_ROOT ;;
		esac
		mkdir -p "$XDG_DATA_HOME"
	fi
	local log_file="$VALIDATION_DIR/check.log"
	"$GODOT_BIN" --headless --path "$PROJECT_DIR" "$@" 2>&1 | tee "$log_file"
	# Godot may log a script/import error without a failing process exit code.
	if grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$log_file"; then
		echo "Validation failed: Godot reported an error." >&2
		return 1
	fi
}

echo "Godot version: $("$GODOT_BIN" --version)"
python3 "$PROJECT_DIR/tools/check_font_coverage.py"
python3 "$PROJECT_DIR/tests/test_font_coverage.py"
python3 "$PROJECT_DIR/tools/validate_save_paths_linux.py" --godot "$GODOT_BIN"
run_check --editor --import
run_check --script res://tests/build_test.gd
run_check --script res://tests/equipment_catalog_test.gd
run_check --script res://tests/typed_affix_catalog_test.gd
run_check --script res://tests/defense_rules_test.gd
run_check --script res://tests/defense_equipment_catalog_test.gd
run_check --script res://tests/defense_equipment_state_test.gd
run_check --script res://tests/local_weapon_compiler_test.gd
run_check --script res://tests/local_weapon_catalog_test.gd
run_check --script res://tests/local_weapon_state_test.gd
run_check --script res://tests/local_weapon_integration_test.gd
run_check --script res://tests/local_weapon_budget_test.gd
run_check --script res://tests/fire_defense_integration_test.gd
run_check --script res://tests/damage_base_test.gd
run_check --script res://tests/damage_preview_test.gd
run_check --script res://tests/typed_damage_state_test.gd
run_check --script res://tests/typed_damage_integration_test.gd
run_check --script res://tests/save_guard_integration_test.gd
run_check --script res://tests/progress_batch_test.gd
run_check --script res://tests/equipment_state_test.gd
run_check --script res://tests/equipment_integration_test.gd
run_check --script res://tests/skill_compiler_test.gd
run_check --script res://tests/skill_support_state_test.gd
run_check --script res://tests/skill_support_integration_test.gd
run_check --script res://tests/skill_support_ui_test.gd
run_check --script res://tests/projectile_support_rules_test.gd
run_check --script res://tests/pierce_integration_test.gd
run_check --script res://tests/pierce_ui_test.gd
run_check --script res://tests/equipment_soak_test.gd
run_check --script res://tests/passive_jewel_test.gd
run_check --script res://tests/special_jewel_test.gd
run_check --script res://tests/special_jewel_integration_test.gd
run_check --script res://tests/special_jewel_ui_test.gd
run_check --script res://tests/reference_export_test.gd
run_check --script res://tests/reference_launch_test.gd
run_check --script res://tests/mechanic_registry_test.gd
run_check --script res://tests/passive_balance_test.gd
run_check --script res://tests/monster_system_test.gd
run_check --script res://tests/monster_integration_test.gd
run_check --script res://tests/combat_pipeline_test.gd
run_check --script res://tests/spatial_collision_test.gd
run_check --script res://tests/projectile_schedule_test.gd
run_check --script res://tests/density_integration_test.gd
run_check --script res://tests/world_view_test.gd
run_check --script res://tests/fire_visual_test.gd
run_check --script res://tests/combat_integration_test.gd
run_check --script res://tests/smoke_test.gd
run_check --script res://tests/visual_settings_test.gd
run_check --script res://tests/combat_cues_test.gd
run_check --script res://tests/combat_cues_integration_test.gd
run_check --script res://tests/fantasy_actor_test.gd
run_check --script res://tests/equipment_art_test.gd
run_check --script res://tests/material_frame_test.gd
run_check --script res://tests/grimoire_ui_test.gd
run_check --script res://tests/equipment_painterly_art_test.gd
python3 "$PROJECT_DIR/tests/reference_catalog_test.py"
run_check --quit-after 300
echo "Validation passed: import, immutable equipment pools/RNG, scoped local weapon damage and independent balance replay, shared fire defense and natural encounter, transaction-bounded progress flush/exact saved-byte equivalence, schema10 support vocabulary/schema9 equipment compatibility/byte-exact backups/protected saves/special passive grants/offline reference data and launch wiring, typed hit bases and previews, compiled supports/cast/UI, wide native camera/100 real enemies/spatial-reference equivalence, fantasy artwork/materials and bounded visual cues, build/save model, passive/jewel/balance invariants, shared mechanisms, monster lifecycle/scene, projectile/damage pipeline, combat/UI integration, and 300-frame startup."
'''

V014_PROJECT = r'''; Engine configuration file. Prefer editing through the Godot editor.
config_version=5

[application]

config/name="godot游戏仓"
config/description="裂隙试炼：以装备、天赋和技能组合为核心的平面竞技场原型。"
config/version="0.14.0"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.6", "GL Compatibility")

[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/size/min_width=960
window/size/min_height=540

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
environment/defaults/default_clear_color=Color(0.055, 0.067, 0.09, 1)
'''

SAVE_PATH_HELPER = (
    '#!/usr/bin/env python3\n'
    '"""Run save-identity regressions only after probing a disposable Linux project."""\n'
    'from __future__ import annotations\n'
    '\n'
    'import argparse\n'
    'import hashlib\n'
    'import json\n'
    'import os\n'
    'from pathlib import Path\n'
    'import platform\n'
    'import re\n'
    'import shutil\n'
    'import subprocess\n'
    'import tempfile\n'
    'import uuid\n'
    '\n'
    '\n'
    'def main() -> int:\n'
    '    parser = argparse.ArgumentParser(description=__doc__)\n'
    '    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))\n'
    '    args = parser.parse_args()\n'
    '    if platform.system() != "Linux":\n'
    '        parser.error("This runner requires native Linux; use the Windows isolated runner there.")\n'
    '    source = Path(__file__).resolve().parents[1]\n'
    '    sandbox = Path(tempfile.mkdtemp(prefix="godot-save-linux-"))\n'
    '    token = uuid.uuid4().hex\n'
    '    project = sandbox / "中文 工程"\n'
    '    project.mkdir()\n'
    '    userdata = sandbox / "data" / ("存档 沙箱 " + token)\n'
    "    settings = {'config/name': 'Linux Save QA ' + token,\n"
    "                'config/use_custom_user_dir': True,\n"
    "                'config/custom_user_dir_name': '存档 沙箱 ' + token}\n"
    '    (project / "project.godot").write_text(\'config_version=5\\n[application]\\n\' +\n'
    '        \'\\n\'.join(key + \'=\' + json.dumps(value, ensure_ascii=False) for key, value in settings.items()) + \'\\n\', encoding="utf-8")\n'
    '    pending = ["scripts/build_state.gd", "tests/windows/save_linux_identity_test.gd"]\n'
    '    copied: dict[str, str] = {}\n'
    '    while pending:\n'
    '        relative = pending.pop()\n'
    '        if relative in copied:\n'
    '            continue\n'
    '        path = source / relative\n'
    '        if not path.resolve().is_relative_to(source):\n'
    '            raise RuntimeError("Dependency escapes repository: " + relative)\n'
    '        if path.is_dir():\n'
    '            pending.extend(str(item.relative_to(source)) for item in path.rglob("*") if item.is_file())\n'
    '            continue\n'
    '        if not path.is_file():\n'
    '            raise RuntimeError("Missing literal dependency: " + relative)\n'
    '        data = path.read_bytes()\n'
    '        target = project / relative\n'
    '        target.parent.mkdir(parents=True, exist_ok=True)\n'
    '        target.write_bytes(data)\n'
    '        copied[relative] = hashlib.sha256(data).hexdigest()\n'
    '        if path.suffix == ".gd":\n'
    '            pending.extend(re.findall(r\'\'\'res://([^"\'\\r\\n]+)\'\'\', data.decode("utf-8")))\n'
    '    env = os.environ.copy()\n'
    '    env.update(XDG_DATA_HOME=str(sandbox / "data"), XDG_CONFIG_HOME=str(sandbox / "config"),\n'
    '        XDG_CACHE_HOME=str(sandbox / "cache"), GODOT_SAVE_QA_ROOT=str(sandbox),\n'
    '        GODOT_SAVE_QA_PROJECT=str(project), GODOT_SAVE_QA_USERDATA=str(userdata),\n'
    '        GODOT_SAVE_QA_TOKEN=token)\n'
    '    env.pop("GODOT_SAVE_QA_PROBE_VERIFIED", None)\n'
    '    command = [args.godot, "--headless", "--path", str(project), "--script",\n'
    '               "res://tests/windows/save_linux_identity_test.gd"]\n'
    '    records = []\n'
    '\n'
    '    def run(name: str, extra: list[str], overrides: dict[str, str], expected: int) -> str:\n'
    '        process = subprocess.run(command + extra, env=env | overrides, text=True,\n'
    '            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)\n'
    '        output = process.stdout\n'
    '        (sandbox / (name + ".log")).write_text(output, encoding="utf-8")\n'
    '        gates = [json.loads(line.removeprefix("SAVE_QA_GATE ")) for line in output.splitlines()\n'
    '                 if line.startswith("SAVE_QA_GATE ")]\n'
    '        if process.returncode != expected or len(gates) != 1 or re.search(r"(?:SCRIPT ERROR:|ERROR:)", output):\n'
    '            raise RuntimeError(name + " failed; inspect " + str(sandbox))\n'
    '        gate = gates[0]\n'
    '        if gate["user_data_dir"] != str(userdata) or gate["project"] != str(project) or gate["token"] != token:\n'
    '            raise RuntimeError("Actual paths or token differ from isolated contract")\n'
    '        if gate["ok"] != (expected == 0):\n'
    '            raise RuntimeError("Unexpected isolation gate state")\n'
    '        records.append({"name": name, "exit_code": process.returncode, "gate": gate})\n'
    '        return output\n'
    '\n'
    '    print("Linux save isolation sandbox: " + str(sandbox), flush=True)\n'
    '    run("probe", ["--", "probe"], {}, 0)\n'
    '    run("negative-probe", ["--", "probe"], {"GODOT_SAVE_QA_USERDATA": str(userdata / "mismatch")}, 78)\n'
    '    output = run("save-identity", [], {"GODOT_SAVE_QA_PROBE_VERIFIED": token}, 0)\n'
    '    results = [json.loads(line.removeprefix("SAVE_QA_RESULT ")) for line in output.splitlines()\n'
    '               if line.startswith("SAVE_QA_RESULT ")]\n'
    '    if len(results) != 1 or results[0]["failures"] != 0 or not results[0]["completed"] or results[0]["checks"] <= 0:\n'
    '        raise RuntimeError("Missing or failed identity test result")\n'
    '    for relative, sha in copied.items():\n'
    '        if hashlib.sha256((source / relative).read_bytes()).hexdigest() != sha:\n'
    '            raise RuntimeError("Source changed during isolated test: " + relative)\n'
    '    report = {"ok": True, "sandbox": str(sandbox), "result": results[0], "runs": records,\n'
    '              "source_sha256": copied, "engine": shutil.which(args.godot) or args.godot}\n'
    '    (sandbox / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")\n'
    '    print("Linux save identity test: %d checks, 0 failures" % results[0]["checks"])\n'
    '    return 0\n'
    '\n'
    '\n'
    'if __name__ == "__main__":\n'
    '    raise SystemExit(main())\n'
)

FAKE_ENGINE = r'''#!/usr/bin/env python3
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

args = sys.argv[1:]
if "--version" in args:
    name = "version"
elif "--editor" in args:
    name = "import"
elif "--script" in args:
    name = args[args.index("--script") + 1].removeprefix("res://")
    if name == "tests/windows/save_linux_identity_test.gd":
        actual_userdata = str(Path(os.environ["XDG_DATA_HOME"]) / ("存档 沙箱 " + os.environ["GODOT_SAVE_QA_TOKEN"]))
        qa_ok = actual_userdata == os.environ["GODOT_SAVE_QA_USERDATA"]
        name = "save-path-negative-probe" if not qa_ok else "save-path-probe" if "probe" in args else "save-path-identity"
elif "--quit-after" in args:
    name = "startup-300-frames"
else:
    filename = Path(sys.argv[0]).name
    name = ("tools/" if filename == "check_font_coverage.py" else "tests/") + filename

def record(event, **extra):
    row = {"event": event, "name": name, "pid": os.getpid(), "time": time.monotonic(),
           "args": args, "cwd": os.getcwd(), "affinity": sorted(os.sched_getaffinity(0)),
           "home": os.environ.get("HOME"), "appdata": os.environ.get("APPDATA"),
           "pierce_qa_root": os.environ.get("PIERCE_QA_ROOT"),
           "save_qa_root": os.environ.get("GODOT_SAVE_QA_ROOT"),
           "xdg": {k: os.environ[k] for k in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")}, **extra}
    with open(os.environ["FAKE_TRACE"], "a") as out:
        fcntl.flock(out, fcntl.LOCK_EX)
        out.write(json.dumps(row) + "\n")
        out.flush()
        fcntl.flock(out, fcntl.LOCK_UN)

def selected(variable):
    return name in os.environ.get(variable, "").split(",")

record("start")
for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
    Path(os.environ[key]).mkdir(parents=True, exist_ok=True)
    Path(os.environ[key], "same-name-save").write_text(name)
if name != "version":
    print("stdout: " + name, flush=True)
    print("stderr: " + name, file=sys.stderr, flush=True)
if selected("FAKE_CHILD"):
    child = subprocess.Popen([sys.executable, "-c",
        "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)"])
    record("child", child_pid=child.pid)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
if selected("FAKE_HANG"):
    while True:
        time.sleep(0.1)
time.sleep(0 if name == "version" else float(os.environ.get("FAKE_DELAY", "0.015")))
if name == "version":
    print(os.environ.get("FAKE_VERSION", "4.6.3.fake"), flush=True)
if name.startswith("save-path-"):
    print("SAVE_QA_GATE " + json.dumps({"ok": qa_ok, "token": os.environ["GODOT_SAVE_QA_TOKEN"],
        "project": args[args.index("--path")+1], "user_data_dir": actual_userdata}), flush=True)
    if name == "save-path-identity":
        print("SAVE_QA_RESULT " + json.dumps({"failures": 0, "completed": True, "checks": 9}), flush=True)
if name in ("tests/pierce_integration_test.gd", "tests/pierce_ui_test.gd"):
    qa = os.environ.get("PIERCE_QA_ROOT", "")
    if qa != os.environ["XDG_DATA_HOME"] or not qa.startswith("/tmp/godot-pierce-acceptance-"):
        record("end")
        sys.exit(2)
if selected("FAKE_SCRIPT_ERROR"):
    print("SCRIPT ERROR: synthetic exception with successful exit", flush=True)
if selected("FAKE_ERROR"):
    print("\tERROR: synthetic import/runtime failure", file=sys.stderr, flush=True)
if selected("FAKE_NON_ERROR"):
    print("FILE_ERROR: an identifier, not the engine error prefix", flush=True)
if selected("FAKE_SIGNAL"):
    os.kill(os.getpid(), signal.SIGTERM)
record("end")
sys.exit(7 if selected("FAKE_FAIL") else 78 if name == "save-path-negative-probe" else 0)
'''


@unittest.skipUnless(sys.platform == "linux" and hasattr(os, "sched_getaffinity"), "Linux process/XDG tests")
class ValidationRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="validation-runner-tests-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.project = self.base / "project"
        (self.project / "tools").mkdir(parents=True)
        (self.project / "tests").mkdir()
        (self.project / "tools/validate.sh").write_bytes(V013_SHELL.encode())
        (self.project / "project.godot").write_bytes(V013_PROJECT.encode())
        for name in runner.SCRIPT_NAMES:
            (self.project / f"tests/{name}_test.gd").write_text("# fake engine fixture\n")
        (self.project / "tests/reference_catalog_test.py").write_text(FAKE_ENGINE)
        self.engine = self.base / "bin/fake-godot"
        self.engine.parent.mkdir()
        self.engine.write_text(FAKE_ENGINE)
        self.engine.chmod(0o755)
        self.trace = self.base / "trace.jsonl"
        self.logs = self.base / "logs"
        self.cpus = sorted(os.sched_getaffinity(0))[:2]
        if len(self.cpus) < 2:
            self.skipTest("Two allowed CPUs are required for the concurrency tests")

    def command(self, jobs=2, extra=()):
        return [sys.executable, str(RUNNER_PATH), "--project-dir", str(self.project),
                "--godot", str(self.engine), "--jobs", str(jobs),
                "--cpu-set", ",".join(map(str, self.cpus[:jobs])), "--log-dir", str(self.logs), *extra]

    def environment(self, overrides=None):
        env = os.environ.copy()
        env.update(FAKE_TRACE=str(self.trace))
        env.update(overrides or {})
        return env

    def events(self):
        import fcntl
        if not self.trace.exists():
            return []
        with self.trace.open() as source:
            fcntl.flock(source, fcntl.LOCK_SH)
            return [json.loads(line) for line in source]

    def run_fake(self, overrides=None, jobs=2, extra=()):
        completed = subprocess.run(self.command(jobs, extra), env=self.environment(overrides),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
        reports = list(self.logs.glob("*/summary.json"))
        self.assertEqual(len(reports), 1, completed.stdout + completed.stderr)
        return completed, json.loads(reports[0].read_text()), reports[0].parent

    def assert_no_live_process(self, pid):
        status = Path(f"/proc/{pid}/stat")
        if status.exists():
            self.assertEqual(status.read_text().split(") ")[1].split()[0], "Z", f"Process {pid} still live")

    def test_parse_full_plan_order_and_absent_timeouts(self):
        plan = runner.parse_plan(self.project)
        source = (self.project / "tools/validate.sh").read_text().splitlines()
        self.assertEqual(len(plan.checks), 54)
        self.assertEqual(plan.checks[0].name, "import")
        self.assertEqual(plan.checks[-2].name, "tests/reference_catalog_test.py")
        self.assertEqual(plan.checks[-1].args, ("--quit-after", "300"))
        self.assertTrue(all(check.declared_timeout_seconds is None for check in plan.checks))
        self.assertEqual([check.source_line for check in plan.checks], list(range(35, 89)))
        self.assertTrue(all(source[check.source_line - 1].startswith(("run_check ", "python3 "))
                            for check in plan.checks))
        path = self.project / "tools/validate.sh"
        a, b = "run_check --script res://tests/build_test.gd", "run_check --script res://tests/equipment_catalog_test.gd"
        text = path.read_text().replace(a, "TEMP").replace(b, a).replace("TEMP", b)
        path.write_text(text)
        reordered = runner.parse_plan(self.project)
        self.assertEqual([check.name for check in reordered.checks[1:3]],
                         ["tests/equipment_catalog_test.gd", "tests/build_test.gd"])

    def test_reject_missing_duplicate_unknown_or_changed_shell_checks(self):
        path = self.project / "tools/validate.sh"
        original = path.read_text()
        command = "run_check --script res://tests/build_test.gd\n"
        variants = [original.replace(command, ""), original.replace(command, command * 2),
                    original.replace(command, "if true; then\n" + command + "fi\n"),
                    original.replace(command, command.rstrip() + " -- --samples=1\n"),
                    original.replace(command, "timeout 1 " + command),
                    original.replace('"$GODOT_BIN" --headless', 'timeout 1 "$GODOT_BIN" --headless'),
                    original.replace(command, "run_check --script res://tests/unknown_test.gd\n"),
                    original.replace('python3 "$PROJECT_DIR/tests/reference_catalog_test.py"\n', "")]
        for value in variants:
            with self.subTest(value=value[-180:]):
                path.write_text(value)
                with self.assertRaises(runner.PlanError):
                    runner.parse_plan(self.project)
        self.assertFalse(self.trace.exists())

    def test_missing_check_file_refuses_before_launch(self):
        (self.project / "tests/build_test.gd").unlink()
        completed = subprocess.run(self.command(), env=self.environment(), capture_output=True, text=True)
        self.assertEqual(completed.returncode, 2)
        self.assertIn("Missing check/resource", completed.stderr)
        self.assertFalse(self.trace.exists())
        self.assertFalse(self.logs.exists())

    def test_max_two_processes_serial_barriers_and_isolated_paths(self):
        completed, report, root = self.run_fake()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertTrue(report["complete"])
        self.assertEqual(report["failed_checks"], [])
        self.assertEqual(report["peak_check_processes"], 2)
        self.assertEqual(len(report["results"]), 54)
        self.assertTrue(all(row["status"] == "passed" for row in report["results"]))
        self.assertTrue(all(row["effective_timeout_seconds"] is None for row in report["results"]))
        self.assertEqual([row["started_seconds"] for row in report["results"]],
                         sorted(row["started_seconds"] for row in report["results"]))
        events = self.events()
        starts = {event["name"]: event for event in events if event["event"] == "start"}
        ends = {event["name"]: event for event in events if event["event"] == "end"}
        self.assertEqual(len(starts), 55)  # version preflight + all 54 checks
        live, peak = set(), 0
        serial = {row["name"] for row in report["results"] if row["serial_reason"]} | {"version"}
        for event in sorted(events, key=lambda item: item["time"]):
            if event["event"] == "start":
                if event["name"] in serial:
                    self.assertFalse(live)
                self.assertFalse(live & serial)
                live.add(event["name"])
                peak = max(peak, len(live))
            elif event["event"] == "end":
                live.remove(event["name"])
        self.assertEqual(peak, 2)
        self.assertFalse(live)
        self.assertLessEqual(ends["import"]["time"], min(event["time"] for name, event in starts.items()
                                                         if name not in ("import", "version")))
        seen = set()
        for event in starts.values():
            self.assertEqual(event["home"], os.environ.get("HOME"))
            self.assertEqual(event["appdata"], os.environ.get("APPDATA"))
            self.assertEqual(event["cwd"], str(self.project))
            self.assertEqual(len(event["affinity"]), 1)
            for path in event["xdg"].values():
                isolated = Path(path)
                self.assertTrue(isolated.is_absolute() and isolated.is_relative_to(root))
                self.assertNotIn(path, seen)
                seen.add(path)
                self.assertEqual((isolated / "same-name-save").read_text(), event["name"])
        for row in report["results"]:
            self.assertEqual(starts[row["name"]]["affinity"], [row["cpu"]])
            text = Path(row["log"]).read_text()
            self.assertIn("stdout: " + row["name"], text)
            self.assertIn("stderr: " + row["name"], text)
        self.assertGreater(report["wallclock_seconds"], 0)
        self.assertIn("cgroup_cpu_stat", report["cpu_after"])

    def test_one_worker_runs_complete_same_inventory(self):
        completed, report, _root = self.run_fake(jobs=1)
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(report["peak_check_processes"], 1)
        self.assertEqual(len(report["results"]), 54)

    def test_positive_exit_and_zero_exit_script_error_both_fail_without_omissions(self):
        completed, report, _root = self.run_fake({
            "FAKE_FAIL": "tests/build_test.gd", "FAKE_SCRIPT_ERROR": "tests/equipment_catalog_test.gd",
            "FAKE_ERROR": "tests/typed_affix_catalog_test.gd", "FAKE_NON_ERROR": "tests/defense_rules_test.gd"})
        self.assertEqual(completed.returncode, 7)
        self.assertTrue(report["complete"])
        self.assertEqual(len(report["results"]), 54)
        rows = {row["name"]: row for row in report["results"]}
        self.assertEqual(rows["tests/build_test.gd"]["raw_returncode"], 7)
        for name in ("tests/equipment_catalog_test.gd", "tests/typed_affix_catalog_test.gd"):
            self.assertEqual(rows[name]["raw_returncode"], 0)
            self.assertEqual(rows[name]["exit_code"], 1)
            self.assertTrue(rows[name]["error_log_match"])
        self.assertEqual(rows["tests/defense_rules_test.gd"]["status"], "passed")
        self.assertEqual(rows["startup-300-frames"]["status"], "passed")

    def test_python_exit_gate_does_not_invent_engine_log_errors(self):
        completed, report, _root = self.run_fake({"FAKE_SCRIPT_ERROR": "tests/reference_catalog_test.py"})
        self.assertEqual(completed.returncode, 0)
        self.assertFalse(report["results"][-2]["error_log_match"])

    def test_signal_exit_preserves_raw_returncode(self):
        completed, report, _root = self.run_fake({"FAKE_SIGNAL": "tests/build_test.gd"})
        self.assertEqual(completed.returncode, 143)
        self.assertEqual(report["results"][1]["raw_returncode"], -signal.SIGTERM)
        self.assertTrue(report["complete"])

    def test_success_also_cleans_up_surviving_helper(self):
        completed, report, _root = self.run_fake({"FAKE_CHILD": "tests/build_test.gd"})
        self.assertEqual(completed.returncode, 0)
        self.assertTrue(report["complete"])
        children = [e["child_pid"] for e in self.events() if e["event"] == "child"]
        self.assertEqual(len(children), 1)
        self.assert_no_live_process(children[0])

    def test_import_failure_blocks_every_dependent_check(self):
        completed, report, _root = self.run_fake({"FAKE_SCRIPT_ERROR": "import"})
        self.assertEqual(completed.returncode, 1)
        self.assertFalse(report["complete"])
        self.assertEqual(report["results"][0]["status"], "failed")
        self.assertTrue(all(row["status"] == "not_run" for row in report["results"][1:]))
        self.assertEqual([e["name"] for e in self.events() if e["event"] == "start"], ["version", "import"])

    def test_version_failure_blocks_import(self):
        completed, report, _root = self.run_fake({"FAKE_VERSION": "4.7.0.fake"})
        self.assertEqual(completed.returncode, 1)
        self.assertEqual(report["version_preflight"]["status"], "failed")
        self.assertTrue(all(row["status"] == "not_run" for row in report["results"]))
        self.assertEqual(len([e for e in self.events() if e["event"] == "start"]), 1)

    def test_timeout_kills_engine_and_descendants_but_continues_complete_plan(self):
        completed, report, _root = self.run_fake({"FAKE_HANG": "tests/build_test.gd",
            "FAKE_CHILD": "tests/build_test.gd"}, extra=("--timeout-seconds", "0.8"))
        self.assertEqual(completed.returncode, 124)
        row = report["results"][1]
        self.assertEqual(row["status"], "timed_out")
        self.assertEqual(row["raw_returncode"], -signal.SIGKILL)
        self.assertEqual(row["effective_timeout_seconds"], 0.8)
        self.assertTrue(all(r["declared_timeout_seconds"] is None for r in report["results"]))
        self.assertTrue(report["complete"])
        for event in self.events():
            self.assert_no_live_process(event["pid"])
            if event["event"] == "child":
                self.assert_no_live_process(event["child_pid"])

    def test_sigint_and_sigterm_cancel_no_more_dispatch_and_reap_groups(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signum=signum):
                self.trace.unlink(missing_ok=True)
                old_reports = set(self.logs.glob("*/summary.json"))
                env = self.environment({"FAKE_HANG": "tests/build_test.gd,tests/equipment_catalog_test.gd",
                                        "FAKE_CHILD": "tests/build_test.gd"})
                with (self.base / "cancel-output.log").open("w") as out:
                    process = subprocess.Popen(self.command(), env=env, stdout=out, stderr=out)
                    try:
                        deadline = time.monotonic() + 10
                        while time.monotonic() < deadline:
                            events = self.events()
                            if len([e for e in events if e["event"] == "start"]) == 4 and any(
                                    e["event"] == "child" for e in events):
                                break
                            if process.poll() is not None:
                                self.fail((self.base / "cancel-output.log").read_text())
                            time.sleep(0.02)
                        else:
                            self.fail("fake engines did not reach the cancellable state")
                        process.send_signal(signum)
                        self.assertEqual(process.wait(timeout=10), 128 + signum)
                    finally:
                        if process.poll() is None:
                            process.kill()
                            process.wait()
                reports = set(self.logs.glob("*/summary.json")) - old_reports
                self.assertEqual(len(reports), 1)
                report = json.loads(reports.pop().read_text())
                self.assertFalse(report["complete"])
                self.assertEqual([r["status"] for r in report["results"][:3]], ["passed", "cancelled", "cancelled"])
                self.assertTrue(all(r["status"] == "not_run" for r in report["results"][3:]))
                self.assertEqual(len([e for e in self.events() if e["event"] == "start"]), 4)
                for event in self.events():
                    self.assert_no_live_process(event["pid"])
                    if event["event"] == "child":
                        self.assert_no_live_process(event["child_pid"])

    def test_platform_project_override_and_portable_engine_guards(self):
        with patch.object(sys, "platform", "win32"):
            with self.assertRaisesRegex(runner.PlanError, "Windows userdata isolation"):
                runner.audit_platform(self.project, str(self.engine), 2, None)
        with patch.object(sys, "platform", "darwin"):
            with self.assertRaises(runner.PlanError):
                runner.audit_platform(self.project, str(self.engine), 2, None)
        is_file = Path.is_file
        with patch.object(Path, "is_file", autospec=True, side_effect=lambda path:
                          False if path.name == "thread_siblings_list" else is_file(path)):
            with self.assertRaisesRegex(runner.PlanError, "CPU topology is unknown"):
                runner.audit_platform(self.project, str(self.engine), 2, None)
        override = self.project / "override.cfg"
        override.write_text("[application]\nconfig/use_custom_user_dir=true\n")
        with self.assertRaisesRegex(runner.PlanError, "override.cfg"):
            runner.audit_platform(self.project, str(self.engine), 2, None)
        override.unlink()
        marker = self.engine.parent / "._sc_"
        marker.touch()
        with self.assertRaisesRegex(runner.PlanError, "self-contained"):
            runner.audit_platform(self.project, str(self.engine), 2, None)
        marker.unlink()
        (self.project / "project.godot").write_text("[application]\nconfig/use_custom_user_dir=true\n")
        with self.assertRaisesRegex(runner.PlanError, "userdata settings"):
            runner.audit_platform(self.project, str(self.engine), 2, None)
        self.assertFalse(self.trace.exists())

    def test_invalid_limits_refuse_before_engine(self):
        for extra in (("--jobs", "3"), ("--cpu-set", f"{self.cpus[0]},{self.cpus[0]}"),
                      ("--timeout-seconds", "nan"), ("--timeout-seconds", "inf"), ("--timeout-seconds", "0")):
            with self.subTest(extra=extra):
                completed = subprocess.run(self.command(extra=extra), env=self.environment(),
                                           capture_output=True, text=True, timeout=10)
                self.assertEqual(completed.returncode, 2)
                self.assertFalse(self.trace.exists())
        self.assertFalse(self.logs.exists())


@unittest.skipUnless(sys.platform == "linux" and hasattr(os, "sched_getaffinity"), "Linux process/XDG tests")
class ValidationRunnerV014Tests(unittest.TestCase):
    # Reuse process plumbing, but not the v0.13 assertions/inventory.
    command = ValidationRunnerTests.command
    environment = ValidationRunnerTests.environment
    events = ValidationRunnerTests.events
    run_fake = ValidationRunnerTests.run_fake
    assert_no_live_process = ValidationRunnerTests.assert_no_live_process

    def setUp(self):
        ValidationRunnerTests.setUp(self)
        self.v013_plan = runner.parse_plan(self.project)
        (self.project / "tools/validate.sh").write_text(V014_SHELL)
        (self.project / "project.godot").write_text(V014_PROJECT)
        for name in runner.V014_SCRIPTS:
            (self.project / f"tests/{name}_test.gd").write_text("# fake engine fixture\n")
        (self.project / "tools/check_font_coverage.py").write_text(FAKE_ENGINE)
        (self.project / "tests/test_font_coverage.py").write_text(FAKE_ENGINE)
        # Execute the actual audited composite tool, including its timeout=180,
        # dependency copy, custom project, negative probe and verified write run.
        (self.project / "tools/validate_save_paths_linux.py").write_text(SAVE_PATH_HELPER)
        (self.project / "scripts").mkdir()
        (self.project / "scripts/build_state.gd").write_text("# literal dependency fixture\n")
        (self.project / "tests/windows").mkdir()
        (self.project / "tests/windows/save_linux_identity_test.gd").write_text("# literal dependency fixture\n")
        self.addCleanup(self.cleanup_owned_roots)

    def cleanup_owned_roots(self):
        owned = set()
        for path in self.logs.glob("*/summary.json"):
            owned.update(json.loads(path.read_text()).get("retained_isolation_roots", []))
        for event in self.events():
            if event["name"].startswith("save-path-") and event.get("save_qa_root"):
                owned.add(event["save_qa_root"])
        for name in owned:
            path = Path(name)
            if (path.parent == Path("/tmp") and not path.is_symlink()
                    and path.name.startswith(("godot-pierce-acceptance-", "godot-save-linux-"))):
                shutil.rmtree(path, ignore_errors=True)

    def test_complete_plan_preserves_preflights_order_timeouts_and_environment_policies(self):
        plan = runner.parse_plan(self.project)
        self.assertEqual(plan.version, "v0.14")
        self.assertEqual(plan.source_sha256, "c1ceab3f5a8320e2ea580e311788e9146c2717b74d78c2aed828a9fef8598a86")
        self.assertEqual(len(plan.checks), 60)
        self.assertEqual([c.name for c in plan.checks[:4]], [*runner.V014_PREFIX, "import"])
        self.assertEqual([c.source_line for c in plan.checks], list(range(50, 110)))
        self.assertTrue(all(c.gates_following and c.serial_reason for c in plan.checks[:4]))
        self.assertEqual(plan.checks[2].args, ("--godot", "$GODOT_BIN"))
        self.assertEqual(plan.checks[2].nested_timeout_seconds, 180)
        self.assertTrue(all(c.declared_timeout_seconds is None for c in plan.checks))
        self.assertEqual([c.name for c in plan.checks if c.environment_policy == "pierce_qa"],
                         ["tests/pierce_integration_test.gd", "tests/pierce_ui_test.gd"])
        old_names = {c.name for c in self.v013_plan.checks}
        self.assertTrue(old_names.issubset({c.name for c in plan.checks}))

    def test_fake_full_v014_environment_fidelity_and_serial_composite_tool(self):
        ambient = "caller-value-must-not-reach-main-project-tests"
        completed, report, root = self.run_fake({"PIERCE_QA_ROOT": ambient})
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(report["audited_version"], "v0.14")
        self.assertTrue(report["complete"])
        self.assertEqual(report["full_plan_count"], 60)
        self.assertEqual(len(report["results"]), 60)
        self.assertEqual(report["peak_check_processes"], 2)
        rows = report["results"]
        self.assertEqual(rows[2]["command"][-2:], ["--godot", str(self.engine)])
        self.assertEqual(rows[2]["nested_timeout_seconds"], 180)
        self.assertEqual([row["started_seconds"] for row in rows], sorted(row["started_seconds"] for row in rows))
        for i, row in enumerate(rows):
            if row["serial_reason"]:
                self.assertTrue(all(r["ended_seconds"] <= row["started_seconds"] for r in rows[:i]))
                self.assertTrue(all(r["started_seconds"] >= row["ended_seconds"] for r in rows[i+1:]))
            if row["name"] in runner.PIERCE_CHECKS:
                data = row["xdg"]["XDG_DATA_HOME"]
                self.assertEqual(row["pierce_qa_root"], data)
                self.assertTrue(data.startswith(runner.PIERCE_PREFIX))
                self.assertFalse(Path(data).is_relative_to(root))
            elif row["index"] <= 3:
                self.assertEqual(row["pierce_qa_root"], ambient)
            else:
                self.assertIsNone(row["pierce_qa_root"])
        for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            self.assertEqual(len({r["xdg"][key] for r in rows} | {report["version_preflight"]["xdg"][key]}), 61)
        starts = [e for e in self.events() if e["event"] == "start"]
        child_probes = [e for e in starts if e["name"].startswith("save-path-")]
        self.assertEqual([e["name"] for e in child_probes],
                         ["save-path-probe", "save-path-negative-probe", "save-path-identity"])
        self.assertEqual(len({e["save_qa_root"] for e in child_probes}), 1)
        self.assertTrue(all(Path(e["xdg"]["XDG_DATA_HOME"]).is_relative_to(e["save_qa_root"]) for e in child_probes))
        intervals = {e["name"]: e for e in self.events() if e["event"] == "end"}
        for child in child_probes:
            for other in starts:
                if other["name"] != child["name"]:
                    self.assertFalse(child["time"] < intervals[other["name"]]["time"]
                                     and other["time"] < intervals[child["name"]]["time"])
        for event in starts:
            self.assertEqual(event["home"], os.environ.get("HOME"))
            self.assertEqual(event["appdata"], os.environ.get("APPDATA"))
            self.assertEqual(len(event["affinity"]), 1)
            if event["name"] in runner.PIERCE_CHECKS:
                self.assertEqual(event["pierce_qa_root"], event["xdg"]["XDG_DATA_HOME"])
            elif event["name"].startswith("tests/") and not event["name"].startswith("tests/test_font"):
                self.assertIsNone(event["pierce_qa_root"])

    def test_font_preflight_failure_blocks_all_following_steps(self):
        completed, report, _root = self.run_fake({"FAKE_FAIL": "tools/check_font_coverage.py"})
        self.assertEqual(completed.returncode, 7)
        self.assertFalse(report["complete"])
        self.assertTrue(all(row["status"] == "not_run" for row in report["results"][1:]))
        self.assertEqual([e["name"] for e in self.events() if e["event"] == "start"],
                         ["version", "tools/check_font_coverage.py"])

    def test_path_composite_timeout_kills_python_and_godot_before_import(self):
        completed, report, _root = self.run_fake({"FAKE_HANG": "save-path-probe"},
                                               extra=("--timeout-seconds", "0.8"))
        self.assertEqual(completed.returncode, 124)
        self.assertEqual(report["results"][2]["status"], "timed_out")
        self.assertEqual(report["results"][2]["nested_timeout_seconds"], 180)
        self.assertTrue(all(row["status"] == "not_run" for row in report["results"][3:]))
        for event in self.events():
            self.assert_no_live_process(event["pid"])

    def test_path_composite_cancel_reaps_inner_engine_and_stops_dispatch(self):
        env = self.environment({"FAKE_HANG": "save-path-probe"})
        with (self.base / "cancel-path.log").open("w") as log:
            process = subprocess.Popen(self.command(), env=env, stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if any(e["name"] == "save-path-probe" for e in self.events()):
                        break
                    if process.poll() is not None:
                        self.fail((self.base / "cancel-path.log").read_text())
                    time.sleep(0.02)
                else:
                    self.fail("composite path engine did not start")
                process.send_signal(signal.SIGINT)
                self.assertEqual(process.wait(timeout=10), 130)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
        report = json.loads(next(self.logs.glob("*/summary.json")).read_text())
        self.assertEqual(report["results"][2]["status"], "cancelled")
        self.assertTrue(all(row["status"] == "not_run" for row in report["results"][3:]))
        for event in self.events():
            self.assert_no_live_process(event["pid"])

    def test_reject_changed_v014_structure_missing_checks_and_nested_timeout(self):
        path = self.project / "tools/validate.sh"
        command = "run_check --script res://tests/pierce_ui_test.gd\n"
        font_a = 'python3 "$PROJECT_DIR/tools/check_font_coverage.py"\n'
        font_b = 'python3 "$PROJECT_DIR/tests/test_font_coverage.py"\n'
        variants = [V014_SHELL.replace(command, ""), V014_SHELL.replace(command, command * 2),
                    V014_SHELL.replace("/tmp/godot-pierce-acceptance-XXXXXX", "/tmp/unsafe-pierce-XXXXXX"),
                    V014_SHELL.replace('--godot "$GODOT_BIN"', '--godot godot'),
                    V014_SHELL.replace(font_a + font_b, font_b + font_a),
                    V014_SHELL.replace('python3 "$PROJECT_DIR/tools/check_font_coverage.py"\n', ""),
                    V014_SHELL.replace(command, "timeout 1 " + command)]
        for text in variants:
            with self.subTest(text=text[-80:]):
                path.write_text(text)
                with self.assertRaises(runner.PlanError):
                    runner.parse_plan(self.project)
        path.write_text(V014_SHELL)
        helper = self.project / "tools/validate_save_paths_linux.py"
        helper.write_text(SAVE_PATH_HELPER.replace("timeout=180", "timeout=60"))
        with self.assertRaisesRegex(runner.PlanError, "180-second timeout"):
            runner.parse_plan(self.project)
        self.assertFalse(self.trace.exists())

    def test_unsafe_dependency_root_tmp_symlink_and_mixed_version_refuse(self):
        helper = self.project / "tools/validate_save_paths_linux.py"
        outside = self.base / "outside.py"
        outside.write_text(SAVE_PATH_HELPER)
        helper.unlink()
        helper.symlink_to(outside)
        with self.assertRaisesRegex(runner.PlanError, "outside project"):
            runner.parse_plan(self.project)
        helper.unlink()
        helper.write_text(SAVE_PATH_HELPER)
        plan = runner.parse_plan(self.project)
        is_symlink = Path.is_symlink
        with patch.object(Path, "is_symlink", autospec=True, side_effect=lambda path:
                          True if path == Path("/tmp") else is_symlink(path)):
            with self.assertRaisesRegex(runner.PlanError, "unsafe path"):
                runner.audit_platform(self.project, str(self.engine), 2, None, plan)
        root = self.base / "manual-logs"
        root.mkdir()
        process_runner = runner.Runner(self.project, plan, str(self.engine), tuple(self.cpus), root)
        process_runner.pierce_root = self.base / "unsafe-data"
        pierce = next(c for c in plan.checks if c.name in runner.PIERCE_CHECKS)
        with self.assertRaisesRegex(runner.PlanError, "Unsafe pierce"):
            process_runner.launch(pierce, 0)
        (self.project / "project.godot").write_text(V013_PROJECT)
        completed = subprocess.run(self.command(), env=self.environment(), capture_output=True, text=True)
        self.assertEqual(completed.returncode, 2)
        self.assertFalse(self.trace.exists())


if __name__ == "__main__":
    unittest.main()
