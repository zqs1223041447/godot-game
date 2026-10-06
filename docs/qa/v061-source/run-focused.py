#!/usr/bin/env python3
"""Run independent frozen37 capture and focused source38 tests; never import."""
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
OLD = pathlib.Path(os.environ.get('V061_FROZEN37_PROJECT', '/workspace/scratch/a51485f153de/v060-final-source-snapshot'))
GODOT = os.environ.get('GODOT_BIN', '/usr/local/bin/godot')
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
isolated = pathlib.Path(tempfile.mkdtemp(prefix='godot-m1-v061-source-'))
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


fixture = OUT / 'fixtures/v37-frozen-v060.json'
oracle = OUT / 'fixtures/v37-vocabulary-oracle.json'
if not fixture.exists():
    captured = isolated / 'native-v37.json'
    captured_oracle = isolated / 'native-oracle.json'
    invoke('capture37', OLD, OUT / 'capture-frozen37.gd', {'V061_FROZEN37_OUTPUT': str(captured), 'V061_FROZEN37_ORACLE': str(captured_oracle)})
    fixture.write_bytes(captured.read_bytes())
    oracle.write_bytes(captured_oracle.read_bytes())
    manifest = dict(description='Generated test fixture serialized by unchanged frozen v060 schema37 production Store; not an existing user save and not a relabeled schema38 serialization.',
                    source_project=str(OLD), source_release='v0.60.0', source_commit='b389993',
                    source_store_sha256=sha(OLD / 'scripts/save/canonical_build_store.gd'), source_rules_sha256=sha(OLD / 'scripts/save/canonical_build_rules.gd'),
                    capture_script_sha256=sha(OUT / 'capture-frozen37.gd'), capture_log=f'{stamp}-capture37.log.txt',
                    bytes=fixture.stat().st_size, sha256=sha(fixture), vocabulary_oracle_sha256=sha(oracle))
    (OUT / 'fixtures/manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')

for name in ['rules', 'migration']:
    invoke(name, ROOT, f'tests/source_resolute_technique_{name}_test.gd', {f'V061_SOURCE_{name.upper()}_REPORT': str(OUT / f'{stamp}-{name}-checks.json')})
