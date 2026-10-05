#!/usr/bin/env python3
"""No import; every attempt retains source hashes, command, exit and complete log."""
import datetime, hashlib, json, os, pathlib, subprocess, sys, tempfile, time
root = pathlib.Path(__file__).resolve().parents[3]
evidence = root / 'docs/qa/v056-consumers'
mode = sys.argv[1]
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
project = root.parent / 'v055-final-source-snapshot' if mode == 'baseline' else root
stem = evidence / (stamp + '-' + mode)
env = os.environ.copy()
env['XDG_DATA_HOME'] = tempfile.mkdtemp(prefix='/tmp/godot-m1-v056-consumers-')
env['XDG_CACHE_HOME'] = tempfile.mkdtemp(prefix='/tmp/godot-m1-v056-consumers-cache-')
env['FORGEBLADE_GAMEPLAY_REPORT'] = str(stem) + '.report.json'
if mode == 'baseline': env['FORGEBLADE_BASELINE_CAPTURE'] = str(stem) + '.bin'
elif len(sys.argv) > 2: env['FORGEBLADE_BASELINE_EXPECTED'] = str(pathlib.Path(sys.argv[2]).resolve())
command = ['/usr/local/bin/godot', '--headless', '--path', str(project), '--script', str(root / 'tests/forgeblade_basic_gameplay_test.gd')]
files = [project / p for p in ['scripts/main.gd', 'scripts/canonical_game_state.gd', 'scripts/combat/skill_compiler.gd', 'scripts/combat/combat_data.gd', 'scripts/items/weapon_local_rules.gd']]
files.append(root / 'tests/forgeblade_basic_gameplay_test.gd')
record = {'mode': mode, 'project': str(project), 'command': command, 'isolated_userdata': env['XDG_DATA_HOME'], 'source_sha256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
start = time.monotonic()
try:
    with open(str(stem) + '.log.txt', 'wb') as log:
        result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=150)
    record['exit'] = result.returncode
except subprocess.TimeoutExpired:
    record['exit'] = 124
    record['timeout'] = True
record['elapsed_seconds'] = time.monotonic() - start
record['log_sha256'] = hashlib.sha256(pathlib.Path(str(stem) + '.log.txt').read_bytes()).hexdigest()
record['source_unchanged_during_run'] = all(hashlib.sha256(p.read_bytes()).hexdigest() == record['source_sha256'][str(p)] for p in files)
for suffix in ['.bin', '.report.json']:
    artifact = pathlib.Path(str(stem) + suffix)
    if artifact.exists(): record[suffix + '_sha256'] = hashlib.sha256(artifact.read_bytes()).hexdigest()
pathlib.Path(str(stem) + '.attempt.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps({'stem': str(stem), 'exit': record['exit'], 'seconds': record['elapsed_seconds'], 'source_unchanged': record['source_unchanged_during_run']}), flush=True)
print(pathlib.Path(str(stem) + '.log.txt').read_text(), end='')
sys.exit(record['exit'])
