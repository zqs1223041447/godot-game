#!/usr/bin/env python3
"""Run only the Long Stride migration/economy checks after coordinator import."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
section = sys.argv[1] if len(sys.argv) > 1 else 'all'
label = sys.argv[2] if len(sys.argv) > 2 else 'attempt01'
if section not in ['all', 'economy', 'gates']:
    raise SystemExit('Unsupported focused section')
log_path = OUT / f'{label}-test.log.txt'
if log_path.exists():
    raise SystemExit('Retain previous evidence; use a new attempt label')
isolated = Path(tempfile.mkdtemp(prefix='godot-m1-v098-migration-'))
env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING='1', V098_MIGRATION_SECTION=section,
           V098_MIGRATION_REPORT=str(OUT / f'{label}-report.json'))
for key, subdir in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
    destination = isolated / subdir
    destination.mkdir()
    env[key] = str(destination)
inputs = [
    'scripts/save/long_stride_gem_migration.gd',
    'scripts/save/canonical_build_rules.gd', 'scripts/save/canonical_build_store.gd',
    'scripts/save/encircling_cleave_gem_migration.gd', 'scripts/items/gem_catalog.gd',
    'scripts/combat/support_registry.gd', 'scripts/combat/long_stride_support_rules.gd',
    'scripts/combat/skill_compiler.gd', 'scripts/canonical_game_state.gd',
    'scripts/items/gem_trade_rules.gd', 'scripts/town/town_catalog.gd',
    'scripts/items/equipment_catalog.gd', 'scripts/world/normal_journey_state.gd',
    'scripts/passives/source_tree_runtime.gd', 'assets/ui/grimoire/long_stride.png',
    'tests/long_stride_migration_test.gd',
    'docs/qa/v098-migration/canonical_build_rules.v097.gd.txt',
    'docs/qa/v094-integration/owned-fixture.json',
    'docs/qa/v083-save/fixtures/v49-old_garden-pending.json',
    'docs/qa/v083-save/fixtures/v49-sunwell_terrace-active.json',
    'docs/qa/v091-root-ui/main-after-reforge.json',
    'docs/qa/v067-migration/fixtures/v42-oracle.json',
    'tests/fixtures/v022_currency/v14-original-bytes.json',
]
def hashes():
    return {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in inputs}
before = hashes()
command = [os.environ.get('GODOT_BIN', '/usr/local/bin/godot'), '--headless', '--path', str(ROOT),
           '--script', 'res://tests/long_stride_migration_test.gd']
start = time.monotonic()
try:
    process = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, timeout=55)
    log, code = process.stdout, process.returncode
except subprocess.TimeoutExpired as error:
    log, code = error.stdout or b'', 124
log_path.write_bytes(log)
after = hashes()
result = dict(section=section, command=command, exit_code=code,
              seconds=round(time.monotonic() - start, 3), isolation=str(isolated),
              script_errors=log.count(b'SCRIPT ERROR:'), engine_errors=log.count(b'ERROR:'),
              inputs_unchanged=before == after)
(OUT / f'{label}-result.json').write_text(json.dumps(result, indent=2) + '\n')
(OUT / f'{label}-tested-inputs.json').write_text(json.dumps({'before':before, 'after':after}, indent=2) + '\n')
print(log.decode(errors='replace'), end='')
print(json.dumps(result, indent=2))
raise SystemExit(code or int(bool(result['engine_errors'] or not result['inputs_unchanged'])))
