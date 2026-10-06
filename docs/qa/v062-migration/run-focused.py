#!/usr/bin/env python3
"""Run independent frozen38 capture and focused schema39 tests; never import."""
import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent
OLD = pathlib.Path(os.environ.get('V062_FROZEN38_PROJECT', '/workspace/scratch/a51485f153de/v061-final-source-snapshot'))
GODOT = os.environ.get('GODOT_BIN', '/usr/local/bin/godot')
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
isolated = pathlib.Path(tempfile.mkdtemp(prefix='godot-m1-v062-migration-'))
base_env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING='1')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke(name, project, script, extra=None):
    home = isolated / name
    env = dict(base_env, XDG_DATA_HOME=str(home / 'data'), XDG_CONFIG_HOME=str(home / 'config'), XDG_CACHE_HOME=str(home / 'cache'), **(extra or {}))
    for directory in ['data', 'config', 'cache']:
        (home / directory).mkdir(parents=True)
    inputs = sorted(p for p in (project / 'scripts').rglob('*.gd'))
    inputs += [project / 'project.godot', pathlib.Path(script) if pathlib.Path(script).is_absolute() else project / script]
    inputs += [project / p for p in ['data/passive_source/data.json', 'data/passives/official_tree_runtime.json', 'data/passive_source/localization_zh_CN.json']]
    before = {str(p): sha(p) for p in inputs}
    command = [GODOT, '--headless', '--path', str(project), '--script', str(script)]
    start = time.monotonic()
    try:
        result = subprocess.run(command, cwd=project, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=55)
        log, code = result.stdout, result.returncode
    except subprocess.TimeoutExpired as exc:
        log, code = exc.stdout or b'', 124
    log_path = OUT / f'{stamp}-{name}.log.txt'
    log_path.write_bytes(log)
    after = {str(p): sha(p) for p in inputs}
    summary = dict(command=command, exit_code=code, elapsed_seconds=round(time.monotonic()-start, 3), isolated_user_dir=str(home),
                   log=log_path.name, script_errors=log.count(b'SCRIPT ERROR'), engine_errors=log.count(b'ERROR:'),
                   inputs_before=before, inputs_after=after, inputs_unchanged=before == after)
    (OUT / f'{stamp}-{name}-attempt.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(log.decode(errors='replace'), flush=True)
    print(json.dumps({k: summary[k] for k in ['exit_code', 'elapsed_seconds', 'script_errors', 'engine_errors', 'inputs_unchanged', 'log']}), flush=True)
    if code or summary['script_errors'] or summary['engine_errors']:
        raise SystemExit(code or 1)


fixture = OUT / 'fixtures/v38-frozen-v061.json'
oracle = OUT / 'fixtures/v38-vocabulary-oracle.json'
if not fixture.exists() or '--refresh-capture' in __import__('sys').argv:
    captured = isolated / 'native-v38.json'
    captured_oracle = isolated / 'native-oracle.json'
    invoke('capture38', OLD, OUT / 'capture-frozen38.gd', {'V062_FROZEN38_OUTPUT': str(captured), 'V062_FROZEN38_ORACLE': str(captured_oracle)})
    fixture.write_bytes(captured.read_bytes())
    oracle.write_bytes(captured_oracle.read_bytes())
    manifest = dict(description='Generated test fixture serialized by unchanged frozen v061 schema38 production Store; not an existing user save and not a relabeled schema39 serialization.',
                    source_project=str(OLD), source_release='v0.61.0', source_commit='d884caea7a2260f4535ba4da2d7e005e6df006d4',
                    source_store_sha256=sha(OLD / 'scripts/save/canonical_build_store.gd'), source_rules_sha256=sha(OLD / 'scripts/save/canonical_build_rules.gd'),
                    capture_script_sha256=sha(OUT / 'capture-frozen38.gd'), capture_log=f'{stamp}-capture38.log.txt',
                    bytes=fixture.stat().st_size, sha256=sha(fixture), vocabulary_oracle_sha256=sha(oracle))
    (OUT / 'fixtures/manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')

source_contract = ['scripts/passives/source_tree_runtime.gd', 'scripts/passives/source_stat_patterns.gd',
                   'scripts/passives/source_tree_data.gd', 'scripts/passives/source_tree_allocation_rules.gd',
                   'data/passive_source/data.json', 'data/passives/official_tree_runtime.json',
                   'data/passive_source/localization_zh_CN.json']
unchanged = {name: {'frozen_v61_sha256': sha(OLD/name), 'v62_sha256': sha(ROOT/name)} for name in source_contract}
source_exact = all(value['frozen_v61_sha256'] == value['v62_sha256'] for value in unchanged.values())
(OUT / 'unchanged-source-evidence.json').write_text(json.dumps({'exact_frozen_v61_source_policy': source_exact, 'files': unchanged}, indent=2)+'\n')
if not source_exact:
    raise SystemExit('Source policy or data changed from frozen v61')

if '--capture-only' not in __import__('sys').argv:
    invoke('migration', ROOT, 'tests/defense_rating_affix_migration_test.gd', {'V062_MIGRATION_REPORT': str(OUT / f'{stamp}-migration-checks.json')})
