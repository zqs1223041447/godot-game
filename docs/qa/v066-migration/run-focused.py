#!/usr/bin/env python3
"""Run native frozen41 capture and focused schema42 checks; never import."""
import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent
OLD = pathlib.Path(os.environ.get('V066_FROZEN41_PROJECT', '/workspace/scratch/a51485f153de/v065-final-source-snapshot'))
GODOT = os.environ.get('GODOT_BIN', '/usr/local/bin/godot')
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
isolated = pathlib.Path(tempfile.mkdtemp(prefix='godot-m1-v066-migration-'))
base_env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING='1')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke(name, project, script, extra=None):
    home = isolated / name
    env = dict(base_env, XDG_DATA_HOME=str(home / 'data'), XDG_CONFIG_HOME=str(home / 'config'), XDG_CACHE_HOME=str(home / 'cache'), **(extra or {}))
    for directory in ['data', 'config', 'cache']:
        (home / directory).mkdir(parents=True)
    inputs = sorted((project / 'scripts').rglob('*.gd'))
    inputs += [project / 'project.godot', pathlib.Path(script) if pathlib.Path(script).is_absolute() else project / script]
    inputs += [project / p for p in ['data/passive_source/data.json', 'data/passives/official_tree_runtime.json', 'data/passive_source/localization_zh_CN.json']]
    if name == 'migration':
        inputs += sorted((OUT / 'fixtures').glob('*.json'))
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
    if code or summary['script_errors'] or summary['engine_errors'] or not summary['inputs_unchanged']:
        raise SystemExit(code or 1)


# Prove the independent snapshot has the released production bytes before using it.
production_paths = [p.relative_to(OLD) for p in sorted((OLD / 'scripts').rglob('*.gd'))]
production_paths += [pathlib.Path('project.godot')]
release_files = {}
for path in production_paths:
    committed = subprocess.run(['git', 'show', f'b2bd4a1:{path}'], cwd=ROOT, check=True, stdout=subprocess.PIPE).stdout
    release_files[str(path)] = {'frozen_sha256': sha(OLD/path), 'release_sha256': hashlib.sha256(committed).hexdigest()}
release_exact = all(v['frozen_sha256'] == v['release_sha256'] for v in release_files.values())
(OUT / 'frozen-release-evidence.json').write_text(json.dumps({'all_production_scripts_identical':release_exact, 'release_commit':'b2bd4a1', 'files':release_files}, indent=2)+'\n')
if not release_exact:
    raise SystemExit('Frozen v65 snapshot differs from released production code')

fixture = OUT / 'fixtures/v41-ir-frozen-v065.json'
if not fixture.exists() or '--refresh-capture' in sys.argv:
    captured = isolated / 'native'
    captured.mkdir()
    invoke('capture41', OLD, OUT / 'capture-frozen41.gd', {'V066_FROZEN41_DIRECTORY':str(captured)})
    files = {}
    for source in sorted(captured.glob('*.json')):
        target = OUT / 'fixtures' / source.name
        target.write_bytes(source.read_bytes())
        files[source.name] = {'bytes':target.stat().st_size, 'sha256':sha(target)}
    manifest = dict(description='Small fixtures serialized by unchanged frozen v065 schema41 production Store; not user saves or relabeled current schemas.',
                    source_project=str(OLD), source_release='v0.65.0', source_commit='b2bd4a1',
                    source_store_sha256=sha(OLD / 'scripts/save/canonical_build_store.gd'), source_rules_sha256=sha(OLD / 'scripts/save/canonical_build_rules.gd'),
                    capture_script_sha256=sha(OUT / 'capture-frozen41.gd'), capture_log=f'{stamp}-capture41.log.txt', files=files)
    (OUT / 'fixtures/manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')

# New gem catalog metadata is expected; the equipment vocabulary and reward module stay exact.
contracts = ['scripts/world/normal_journey_state.gd', 'scripts/items/equipment_catalog.gd', 'scripts/items/gem_trade_rules.gd', 'scripts/passives/source_tree_runtime.gd']
unchanged = {name:{'frozen_v65_sha256':sha(OLD/name), 'v66_sha256':sha(ROOT/name)} for name in contracts}
exact = all(v['frozen_v65_sha256'] == v['v66_sha256'] for v in unchanged.values())
(OUT/'unchanged-contract-evidence.json').write_text(json.dumps({'all_identical':exact, 'files':unchanged},indent=2)+'\n')
if not exact:
    raise SystemExit('Equipment, reward, trade, or source policy contract changed from frozen v65')

if '--capture-only' not in sys.argv:
    invoke('migration', ROOT, 'tests/ambush_gem_migration_test.gd', {'V066_MIGRATION_REPORT':str(OUT/f'{stamp}-migration-checks.json')})
