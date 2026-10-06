#!/usr/bin/env python3
"""Focused v45→46 migration proof; shared parent import must finish first."""
import datetime, hashlib, json, os, pathlib, subprocess, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent
STAMP = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
HOME = pathlib.Path(tempfile.mkdtemp(prefix='godot-m1-v072-migration-'))
env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING='1', V072_MIGRATION_REPORT=str(OUT / f'{STAMP}-checks.json'))
for key, directory in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
    target = HOME / directory
    target.mkdir()
    env[key] = str(target)
inputs = sorted((ROOT/'scripts').rglob('*.gd')) + [ROOT/'project.godot', ROOT/'tests/glove_ring_affix_migration_test.gd']
inputs += sorted((ROOT/'docs/qa/v070-gameplay/fixtures').glob('*.json'))
inputs += sorted((ROOT/'docs/qa/v070-migration/fixtures').glob('*.json'))
inputs += [ROOT/'docs/qa/v071-build-comparison/routes.json']
inputs += [ROOT/p for p in ['data/passive_source/data.json','data/passives/official_tree_runtime.json','data/passive_source/localization_zh_CN.json']]
def hashes(): return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
before = hashes()
command = [os.environ.get('GODOT_BIN','/usr/local/bin/godot'),'--headless','--path',str(ROOT),'--script','tests/glove_ring_affix_migration_test.gd']
start = time.monotonic()
try:
    result = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=55)
    log, code = result.stdout, result.returncode
except subprocess.TimeoutExpired as exc:
    log, code = exc.stdout or b'', 124
(OUT/f'{STAMP}-run.log.txt').write_bytes(log)
after = hashes()
receipt = dict(command=command,exit_code=code,elapsed_seconds=round(time.monotonic()-start,3),isolated_user_dir=str(HOME),log=f'{STAMP}-run.log.txt',script_errors=log.count(b'SCRIPT ERROR'),engine_errors=log.count(b'ERROR:'),inputs_before=before,inputs_after=after,inputs_unchanged=before==after)
(OUT/f'{STAMP}-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(log.decode(errors='replace'),flush=True)
print(json.dumps({k:receipt[k] for k in ['exit_code','elapsed_seconds','script_errors','engine_errors','inputs_unchanged','log']}),flush=True)
raise SystemExit(code or int(bool(receipt['script_errors'] or receipt['engine_errors'] or before != after)))
