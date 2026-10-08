#!/usr/bin/env python3
"""Only the Iron Will path/mechanism and preservation boundary, isolated ≤45s each."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / 'docs/qa/iron-will'
SUITES = ['iron_will_test', 'iron_will_migration_test', 'iron_grip_migration_test']
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--suite', choices=SUITES, action='append', help='Run only a changed related path; retain successful prior results.')
args = parser.parse_args()
prior = json.loads((QA/'verification.json').read_text()) if (QA/'verification.json').exists() else {}
results = prior.get('results', []) if args.suite else []
for suite in args.suite or SUITES:
    prefix = 'godot-iron-grip-' if suite == 'iron_grip_migration_test' else 'godot-iron-will-'
    with tempfile.TemporaryDirectory(prefix=prefix, dir='/tmp') as tmp:
        env = dict(os.environ)
        for key, folder in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
            path = Path(tmp) / folder
            path.mkdir()
            env[key] = str(path)
        env['IRON_WILL_REPORT'] = str(QA / (suite + '.json'))
        env['IRON_GRIP_REPORT'] = str(QA / (suite + '.json'))
        run = subprocess.run([os.environ.get('GODOT_BIN', 'godot'), '--headless', '--path', str(ROOT), '--script', f'res://tests/{suite}.gd'],
                             env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=45)
        (QA / (suite + '.log.txt')).write_text(run.stdout)
        match = re.search(r'checks=(\d+) failures=(\d+)', run.stdout)
        entry = {'suite': suite, 'exit_code': run.returncode, 'checks': int(match[1]) if match else 0,
                 'failures': int(match[2]) if match else None}
        results = [r for r in results if r["suite"] != suite]
        results.append(entry)
        print(json.dumps(entry), flush=True)
        if run.returncode or not match or int(match[2]) or 'ERROR:' in run.stdout:
            print(run.stdout[-6000:])
            (QA / 'verification.json').write_text(json.dumps({'results': results}, indent=2) + '\n')
            raise SystemExit(1)
hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in sorted((QA.glob('schema57-*.json')))}
hashes.update({str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
               for p in [ROOT / path for path in [
                   'scripts/combat/iron_will_rules.gd','scripts/combat/iron_grip_rules.gd','scripts/combat/combat_data.gd','scripts/combat/skill_compiler.gd',
                   'scripts/combat/damage_resolver.gd','scripts/passives/source_tree_runtime.gd',
                   'scripts/passives/source_stat_patterns.gd','scripts/passives/source_tree_localization.gd',
                   'data/passive_source/localization_zh_CN.json','scripts/save/iron_grip_migration.gd','scripts/save/iron_will_migration.gd',
                   'scripts/save/one_with_nature_migration.gd','scripts/save/canonical_build_rules.gd',
                   'scripts/save/canonical_build_store.gd','scripts/canonical_game_state.gd',
                   'tests/iron_will_test.gd','tests/iron_will_migration_test.gd','tests/iron_grip_migration_test.gd']]})
(QA / 'verification.json').write_text(json.dumps({'baseline': '47f31d0aeab2651f19a3590dbe6031ffb4a60830', 'schema': 58,
    'results': results, 'sha256': hashes, 'scope': 'Iron Will and immediate frozen56→57 chain only; no skill matrix, long run or export'}, ensure_ascii=False, indent=2) + '\n')
