#!/usr/bin/env python3
"""Finite related-only checks, each using its own temporary Linux XDG save."""
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / 'docs/qa/one-with-nature'
SUITES = ['one_with_nature_passive_test', 'one_with_nature_migration_test',
          'attack_elemental_passive_test', 'attack_elemental_passive_migration_test']
results = []
for suite in SUITES:
    with tempfile.TemporaryDirectory(prefix='godot-one-with-nature-', dir='/tmp') as folder:
        env = dict(os.environ)
        for key, child in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
            target = Path(folder) / child
            target.mkdir()
            env[key] = str(target)
        # Prior related tests use a distinct existing isolation guard.
        if suite.startswith('attack_elemental_'):
            with tempfile.TemporaryDirectory(prefix='godot-attack-elemental-', dir='/tmp') as prior:
                for key, child in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
                    target = Path(prior) / child
                    target.mkdir()
                    env[key] = str(target)
                result = subprocess.run([os.environ.get('GODOT_BIN', 'godot'), '--headless', '--path', str(ROOT), '--script', f'res://tests/{suite}.gd'],
                                        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=45)
        else:
            env['ONE_WITH_NATURE_REPORT'] = str(QA / (suite + '.json'))
            result = subprocess.run([os.environ.get('GODOT_BIN', 'godot'), '--headless', '--path', str(ROOT), '--script', f'res://tests/{suite}.gd'],
                                    env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=45)
        (QA / (suite + '.log')).write_text(result.stdout)
        match = re.search(r'checks=(\d+) failures=(\d+)', result.stdout)
        entry = {'suite': suite, 'exit_code': result.returncode, 'checks': int(match[1]) if match else 0,
                 'failures': int(match[2]) if match else None}
        results.append(entry)
        print(json.dumps(entry), flush=True)
        if result.returncode or not match or int(match[2]) or 'ERROR:' in result.stdout:
            print(result.stdout[-5000:], flush=True)
            (QA / 'verification.json').write_text(json.dumps({'results': results}, indent=2) + '\n')
            raise SystemExit(1)
hashes = {}
for path in ['scripts/passives/source_stat_patterns.gd', 'scripts/passives/source_tree_runtime.gd',
             'scripts/save/canonical_build_rules.gd', 'scripts/save/canonical_build_store.gd',
             'scripts/save/attack_elemental_passive_migration.gd', 'scripts/save/one_with_nature_migration.gd',
             'scripts/canonical_game_state.gd', 'data/passive_source/localization_zh_CN.json',
             'scripts/combat/combat_data.gd', 'scripts/combat/damage_resolver.gd',
             'tests/one_with_nature_passive_test.gd', 'tests/one_with_nature_migration_test.gd',
             'tests/attack_elemental_passive_test.gd', 'tests/attack_elemental_passive_migration_test.gd',
             'docs/qa/one-with-nature/schema55-town.json', 'docs/qa/one-with-nature/schema55-active.json',
             'docs/qa/v115-native-map-entry/earned-v114-save.json']:
    hashes[path] = hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
output = {'baseline': 'ded595477a73f91c1b1e60bf0d93919c88941103', 'schema': 56, 'results': results,
          'source_sha256': hashes, 'scope': 'Only exact notable15842 +56 preservation boundary and two directly related prior suites; each process ≤45 seconds'}
(QA / 'verification.json').write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
