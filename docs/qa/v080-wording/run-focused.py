#!/usr/bin/env python3
"""One focused v080 run; caller must complete the shared resource import first."""
import datetime
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
INPUTS = [
    'project.godot',
    'tests/passive_resource_wording_test.gd',
    'scripts/canonical_game_state.gd',
    'scripts/ui/canonical_passive_panel.gd',
    'scripts/ui/source_passive_tree_view.gd',
    'scripts/passives/source_tree_data.gd',
    'scripts/passives/source_tree_runtime.gd',
    'scripts/passives/source_stat_patterns.gd',
    'scripts/passives/source_tree_localization.gd',
    'data/passives/official_tree_runtime.json',
    'data/passive_source/localization_zh_CN.json',
    'tools/passive_import/build_source_tree_zh.py',
]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def hashes():
    return {name: sha(ROOT / name) for name in INPUTS}

started = datetime.datetime.now(datetime.timezone.utc)
run_id = started.strftime('%Y%m%dT%H%M%S.%fZ')
run_dir = OUT / run_id
run_dir.mkdir()
isolation_root = Path('/tmp/godot-m1-v080-wording')
isolation_root.mkdir(exist_ok=True)
isolation = Path(tempfile.mkdtemp(prefix=run_id + '-', dir=isolation_root))
env = os.environ.copy()
for key, name in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
    path = isolation / name
    path.mkdir()
    env[key] = str(path)
for key in ['PIERCE_QA_ROOT', 'GODOT_CRAFTING_TEST_ROOT']:
    env.pop(key, None)
binary = shutil.which('godot')
assert binary, 'Godot is not installed'
command = [binary, '--headless', '--path', str(ROOT), '--script', 'res://tests/passive_resource_wording_test.gd']
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
version = subprocess.check_output([binary, '--version'], text=True).strip()
before = hashes()
clock = time.monotonic()
timed_out = False
with (run_dir / 'wording.stdout.log').open('wb') as log:
    try:
        proc = subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=45)
        exit_code = proc.returncode
    except subprocess.TimeoutExpired:
        timed_out = True
        exit_code = 124
elapsed = time.monotonic() - clock
after = hashes()
output = (run_dir / 'wording.stdout.log').read_text(errors='replace')
errors = re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:).*$', output, re.MULTILINE)
summary = re.search(r'Passive resource wording: (\d+) checks, (\d+) failures; 9 exact wording keys, 7 complete nodes, 21 real-panel search submissions', output)
pass_status = (exit_code == 0 and not timed_out and not errors and summary is not None
               and summary[2] == '0' and before == after)
receipt = {
    'started_utc': started.isoformat(), 'elapsed_seconds': round(elapsed, 3),
    'baseline_commit': '33ed04b73edf3545b98339291df81b4c49f891cf', 'worktree_head': head,
    'godot_version': version, 'command': command,
    'isolation': {key: env[key] for key in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']},
    'uses_existing_shared_import': True, 'exit_code': exit_code, 'timed_out': timed_out,
    'checks': int(summary[1]) if summary else None, 'failures': int(summary[2]) if summary else None,
    'engine_errors': errors, 'input_sha256_before': before, 'input_sha256_after': after,
    'inputs_unchanged': before == after, 'stdout_sha256': sha(run_dir / 'wording.stdout.log'),
    'passed': pass_status,
}
(run_dir / 'wording.exit.txt').write_text(str(exit_code) + '\n')
(run_dir / 'wording-result.json').write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + '\n')
print(json.dumps({'run': str(run_dir.relative_to(ROOT)), 'passed': pass_status,
                  'checks': receipt['checks'], 'failures': receipt['failures'],
                  'elapsed_seconds': receipt['elapsed_seconds'], 'exit_code': exit_code,
                  'engine_errors': errors, 'inputs_unchanged': before == after}, ensure_ascii=False))
raise SystemExit(0 if pass_status else 1)
