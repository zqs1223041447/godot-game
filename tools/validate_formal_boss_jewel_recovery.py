#!/usr/bin/env python3
"""Bounded boss-jewel integration and the existing allocation-rule check only."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / 'docs/qa/formal-boss-jewel-recovery'
SUITES = ['formal_boss_jewel_recovery_test', 'source_tree_allocation_rules_test']
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--suite', choices=SUITES, action='append')
args = parser.parse_args()
QA.mkdir(parents=True, exist_ok=True)
for suite in args.suite or SUITES:
    paths = ['scripts/main.gd', 'scripts/canonical_game_state.gd', 'scripts/jewel_data.gd',
             'scripts/save/canonical_build_rules.gd', 'scripts/save/canonical_build_migration.gd',
             'scripts/save/canonical_build_store.gd', 'scripts/items/item_location_rules.gd',
             'scripts/items/item_transfer_plan.gd', 'scripts/ui/canonical_inventory_panel.gd',
             'scripts/passives/source_tree_runtime.gd', 'scripts/passives/source_tree_allocation_rules.gd',
             'tests/formal_boss_equipment_recovery_test.gd', f'tests/{suite}.gd']
    hashes = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}
    with tempfile.TemporaryDirectory(prefix='godot-boss-jewel-', dir='/tmp') as tmp:
        env = dict(os.environ)
        for key, folder in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
            path = Path(tmp) / folder
            path.mkdir()
            env[key] = str(path)
        env['BOSS_JEWEL_REPORT'] = str(QA / (suite + '.json'))
        command = ['godot', '--headless', '--path', str(ROOT), '--script', f'res://tests/{suite}.gd']
        start = time.monotonic()
        try:
            run = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=45)
        except subprocess.TimeoutExpired as error:
            (QA / (suite + '.log.txt')).write_bytes(error.stdout or b'')
            (QA / (suite + '-run.json')).write_text(json.dumps({'ok': False, 'error': '45-second timeout', 'sha256': hashes}, indent=2) + '\n')
            raise
        (QA / (suite + '.log.txt')).write_text(run.stdout)
        match = re.search(r'checks=(\d+) failures=(\d+)', run.stdout) or re.search(r': (\d+) checks, (\d+) failures', run.stdout)
        ok = run.returncode == 0 and match is not None and int(match[2]) == 0 and 'ERROR:' not in run.stdout
        record = {'baseline': 'a0a8734b95f1f0f2c4d2af307db8590555067651', 'suite': suite,
                  'ok': ok, 'exit_code': run.returncode, 'command': command, 'isolated_xdg': tmp,
                  'timeout_seconds': 45, 'elapsed_seconds': round(time.monotonic() - start, 3),
                  'checks': int(match[1]) if match else None, 'failures': int(match[2]) if match else None, 'sha256': hashes}
        (QA / (suite + '-run.json')).write_text(json.dumps(record, indent=2) + '\n')
        print(json.dumps({k: v for k, v in record.items() if k not in ['command', 'sha256', 'isolated_xdg']}), flush=True)
        if not ok:
            print(run.stdout[-6000:])
            raise SystemExit(1)
