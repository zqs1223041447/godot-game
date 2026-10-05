#!/usr/bin/env python3
"""Only the two v053 consumer suites; retain all attempts and their exact inputs."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--godot', default='/usr/local/bin/godot')
parser.add_argument('--suite', choices=['consumer', 'gameplay', 'legacy', 'all'], default='all')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
out = Path(__file__).resolve().parent
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
names = ['consumer', 'gameplay', 'legacy-old', 'legacy-new'] if args.suite == 'all' else ['legacy-old', 'legacy-new'] if args.suite == 'legacy' else [args.suite]
sources = sorted(root.glob('scripts/**/*.gd')) + sorted(root.glob('tests/fire_dot_*test.gd')) + sorted(out.glob('v052_*.gd'))
def hashes():
    return {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
results = []
for name in names:
    test = 'tests/fire_dot_gameplay_test.gd' if name.startswith('legacy') else f'tests/fire_dot_{name}_test.gd'
    isolated = Path(tempfile.mkdtemp(prefix=f'godot-m1-v053-consumers-{name}-'))
    env = dict(os.environ, XDG_DATA_HOME=str(isolated / 'data'), XDG_CONFIG_HOME=str(isolated / 'config'), XDG_CACHE_HOME=str(isolated / 'cache'))
    if name.startswith('legacy'):
        env['FIRE_DOT_LEGACY_OUTPUT'] = str(out / f'{stamp}-{name}')
        env['FIRE_DOT_LEGACY_OLD'] = '1' if name == 'legacy-old' else '0'
    command = [args.godot, '--headless', '--path', str(root), '--script', test]
    before = hashes()
    started = time.monotonic()
    timed_out = False
    try:
        process = subprocess.run(command, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
        output, code = process.stdout, process.returncode
    except subprocess.TimeoutExpired as error:
        output, code, timed_out = error.stdout or b'', 124, True
    logfile = out / f'{stamp}-{name}.log.txt'
    logfile.write_bytes(output)
    row = {'suite': name, 'command': command, 'exit_code': code, 'timed_out': timed_out,
           'elapsed_seconds': round(time.monotonic() - started, 3), 'log': logfile.name,
           'isolated_user_dir': str(isolated), 'sources_before': before, 'sources_after': hashes()}
    row['sources_stable'] = row['sources_before'] == row['sources_after']
    results.append(row)
    print(output.decode(errors='replace'), end='', flush=True)
    print(json.dumps({key: row[key] for key in ['suite', 'exit_code', 'elapsed_seconds', 'sources_stable', 'log']}), flush=True)
    (out / f'{stamp}-results.json').write_text(json.dumps({'published_v052_commit': '0abadf05c94545fb7585f5a7565cd7a8930c26cd', 'runs': results}, indent=2) + '\n')
    if code != 0:
        break
if len(results) >= 2 and results[-1]['suite'] == 'legacy-new' and all(row['exit_code'] == 0 for row in results):
    comparisons = {}
    for suffix in ['bin', 'save']:
        old, new = (out / f'{stamp}-legacy-old.{suffix}').read_bytes(), (out / f'{stamp}-legacy-new.{suffix}').read_bytes()
        comparisons[suffix] = {'equal': old == new, 'old_bytes': len(old), 'new_bytes': len(new),
                               'old_sha256': hashlib.sha256(old).hexdigest(), 'new_sha256': hashlib.sha256(new).hexdigest()}
    passed = all(row['equal'] for row in comparisons.values())
    (out / f'{stamp}-legacy-comparison.json').write_text(json.dumps({'published_v052_commit': '0abadf05c94545fb7585f5a7565cd7a8930c26cd', 'equal': passed, 'comparisons': comparisons}, indent=2) + '\n')
    print(json.dumps({'legacy_exact_state_and_save': passed, 'comparisons': comparisons}), flush=True)
    if not passed:
        raise SystemExit(1)
raise SystemExit(1 if any(row['exit_code'] != 0 for row in results) else 0)
