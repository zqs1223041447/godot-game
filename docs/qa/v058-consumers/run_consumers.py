#!/usr/bin/env python3
"""Bounded actual-main suite and independent complete-v57 no-node oracle.

Does not import, modify production, or write the old source snapshot. Keep every
attempt, input fingerprint, raw log, result and exact comparison. The same test
script is loaded by absolute path with each project's own res:// dependencies.
"""
import argparse
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--godot', default='/usr/local/bin/godot')
parser.add_argument('--suite', choices=['gameplay', 'equipment', 'legacy', 'all'], default='all')
parser.add_argument('--baseline', type=Path, default=Path('/workspace/scratch/a51485f153de/v057-final-source-snapshot'))
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
out = Path(__file__).resolve().parent
script = root / 'tests/mana_guard_gameplay_test.gd'
baseline = args.baseline.resolve()
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
published = '3718d746'
names = ['legacy-old', 'legacy-new', 'gameplay'] if args.suite == 'all' else ['legacy-old', 'legacy-new'] if args.suite == 'legacy' else [args.suite]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def hashes(project):
    files = [project / 'project.godot']
    for folder, suffixes in [('scripts', {'.gd'}), ('scenes', {'.tscn'}), ('data', {'.json'}), ('assets/fonts', {'.otf', '.ttf'})]:
        files += [p for p in (project / folder).rglob('*') if p.is_file() and p.suffix in suffixes]
    return {str(p.relative_to(project)): sha(p.read_bytes()) for p in sorted(files)}


results = []
for name in names:
    project = baseline if name == 'legacy-old' else root
    isolated = Path(tempfile.mkdtemp(prefix=f'godot-m1-v058-consumers-{name}-'))
    env = dict(os.environ, XDG_DATA_HOME=str(isolated / 'data'), XDG_CONFIG_HOME=str(isolated / 'config'), XDG_CACHE_HOME=str(isolated / 'cache'))
    if name.startswith('legacy'):
        env['MANA_GUARD_LEGACY_OUTPUT'] = str(out / f'{stamp}-{name}')
    if name == 'equipment':
        env['MANA_GUARD_GAMEPLAY_SECTION'] = 'equipment'
    command = [args.godot, '--headless', '--path', str(project), '--script', str(script)]
    before = hashes(project)
    test_before = sha(script.read_bytes())
    started = time.monotonic()
    timed_out = False
    try:
        proc = subprocess.run(command, cwd=project, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
        log, code = proc.stdout, proc.returncode
    except subprocess.TimeoutExpired as error:
        log, code, timed_out = error.stdout or b'', 124, True
    logfile = out / f'{stamp}-{name}.log.txt'
    logfile.write_bytes(log)
    row = {'suite': name, 'command': command, 'exit_code': code, 'timed_out': timed_out,
           'script_errors': log.count(b'SCRIPT ERROR'),
           'elapsed_seconds': round(time.monotonic() - started, 3), 'log': logfile.name,
           'isolated_user_dir': str(isolated), 'project_root': str(project),
           'sources_before': before, 'sources_after': hashes(project),
           'test_sha256_before': test_before, 'test_sha256_after': sha(script.read_bytes())}
    row['sources_stable'] = row['sources_before'] == row['sources_after'] and row['test_sha256_before'] == row['test_sha256_after']
    results.append(row)
    print(log.decode(errors='replace'), end='', flush=True)
    print(json.dumps({k: row[k] for k in ['suite', 'exit_code', 'elapsed_seconds', 'sources_stable', 'log']}), flush=True)
    (out / f'{stamp}-results.json').write_text(json.dumps({'published_v057_commit': published, 'runs': results}, indent=2) + '\n')
    if code or row['script_errors'] or not row['sources_stable']:
        break

legacy_done = all(any(r['suite'] == n and r['exit_code'] == 0 for r in results) for n in ['legacy-old', 'legacy-new'])
comparison_ok = True
if legacy_done:
    comparisons = {}
    for suffix in ['bin', 'projected-save.json', 'save']:
        old = (out / f'{stamp}-legacy-old.{suffix}').read_bytes()
        new = (out / f'{stamp}-legacy-new.{suffix}').read_bytes()
        comparisons[suffix] = {'equal': old == new, 'old_bytes': len(old), 'new_bytes': len(new),
                               'old_sha256': sha(old), 'new_sha256': sha(new)}
    old_save = json.loads((out / f'{stamp}-legacy-old.save').read_text())
    new_save = json.loads((out / f'{stamp}-legacy-new.save').read_text())
    raw_versions = {'old': old_save.pop('version'), 'new': new_save.pop('version')}
    comparison_ok = (comparisons['bin']['equal'] and comparisons['projected-save.json']['equal']
                     and old_save == new_save and raw_versions == {'old': 34, 'new': 35})
    archives = []
    for name in ['legacy-old', 'legacy-new']:
        path = out / f'{stamp}-{name}.bin'
        raw = path.read_bytes()
        compressed = gzip.compress(raw, mtime=0)
        archived = path.with_suffix('.bin.gz')
        archived.write_bytes(compressed)
        if gzip.decompress(archived.read_bytes()) != raw:
            raise RuntimeError('Observation archive did not round-trip exactly')
        archives.append({'path': archived.name, 'raw_bytes': len(raw), 'raw_sha256': sha(raw),
                         'archive_bytes': len(compressed), 'archive_sha256': sha(compressed), 'round_trip_exact': True})
        path.unlink()
    report = {'published_v057_commit': published, 'independent_project': str(baseline), 'passed': comparison_ok,
              'projections': ['model/saved JSON top-level version: require 34 versus 35, then omit',
                              'derived stats damage_taken_from_mana_before_life: require float zero, then omit'],
              'raw_save_versions': raw_versions, 'raw_saves_claimed_equal': False,
              'save_contents_equal_after_version_only': old_save == new_save,
              'comparisons': comparisons, 'observation_archives': archives}
    (out / f'{stamp}-legacy-comparison.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'independent_legacy_projected_exact': comparison_ok, 'raw_save_versions': raw_versions, 'comparisons': comparisons}), flush=True)
raise SystemExit(0 if comparison_ok and len(results) == len(names) and all(r['exit_code'] == 0 and not r['script_errors'] and r['sources_stable'] for r in results) else 1)
