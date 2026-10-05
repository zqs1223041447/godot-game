#!/usr/bin/env python3
"""Run only schema36→37 migration checks after the shared import; retain every attempt."""
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
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
isolated = pathlib.Path(tempfile.mkdtemp(prefix='godot-m1-v060-migration-'))
env = dict(os.environ, XDG_DATA_HOME=str(isolated / 'data'), XDG_CONFIG_HOME=str(isolated / 'config'), XDG_CACHE_HOME=str(isolated / 'cache'), GODOT_SILENCE_ROOT_WARNING='1', V060_MIGRATION_REPORT=str(OUT / f'{stamp}-checks.json'))
for name in ['data', 'config', 'cache']:
    (isolated / name).mkdir()
script = 'tests/elemental_defense_affix_migration_test.gd'
inputs = sorted({str(path.relative_to(ROOT)) for path in (ROOT / 'scripts').rglob('*.gd')} | {
    script, 'docs/qa/v060-migration/run-focused.py', 'project.godot',
    'data/passive_source/data.json', 'data/passives/official_tree_runtime.json',
    'data/passive_source/localization_zh_CN.json',
    'docs/qa/v060-migration/fixtures/v36-released.json',
    'docs/qa/v060-migration/fixtures/manifest.json',
    'docs/qa/v059-source/fixtures/v35-released.json',
    'docs/qa/v059-source/allocation-witness.json',
    'docs/qa/v056/fixtures/v34-default.json',
})


def hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in inputs}


before = hashes()
command = [os.environ.get('GODOT_BIN', '/usr/local/bin/godot'), '--headless', '--path', str(ROOT), '--script', script]
started = time.monotonic()
try:
    result = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
    log, code = result.stdout, result.returncode
except subprocess.TimeoutExpired as exc:
    log, code = exc.stdout or b'', 124
(OUT / f'{stamp}.log.txt').write_bytes(log)
after = hashes()
summary = dict(scope='Focused released36→37 equipment vocabulary migration; no historical full suite', command=command,
               isolated_user_dir=str(isolated), exit_code=code, elapsed_seconds=round(time.monotonic() - started, 3),
               log=f'{stamp}.log.txt', report=f'{stamp}-checks.json', script_errors=log.count(b'SCRIPT ERROR'),
               engine_errors=log.count(b'ERROR:'), inputs_before=before, inputs_after=after, inputs_unchanged=before == after)
(OUT / f'{stamp}-attempt.json').write_text(json.dumps(summary, indent=2) + '\n')
print(log.decode(errors='replace'))
print(json.dumps({k: summary[k] for k in ['exit_code', 'elapsed_seconds', 'script_errors', 'engine_errors', 'inputs_unchanged', 'log', 'report']}))
raise SystemExit(code or int(summary['script_errors'] > 0) or int(summary['engine_errors'] > 0))
