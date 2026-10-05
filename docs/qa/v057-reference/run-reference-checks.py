#!/usr/bin/env python3
"""Bounded v57 offline reference export and focused checks, preserving every run."""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
QA = ROOT/'docs/qa/v057-reference'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    paths = [ROOT/'project.godot', ROOT/'tools/export_reference.gd', ROOT/'tools/export_source_execution_coverage.gd',
             ROOT/'docs/qa/v054-source/source-coverage.json', ROOT/'docs/qa/v053-source/source-coverage.json']
    paths += [ROOT/'docs/qa/v056-reference/v055-basic-snapshots.json']
    paths += sorted((ROOT/'scripts').rglob('*.gd')) + sorted((ROOT/'data').rglob('*.json'))
    return {p.relative_to(ROOT).as_posix(): sha(p) for p in paths}


def save(name, value):
    target = QA/name
    assert not target.exists(), 'Evidence already exists: '+str(target)
    target.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')


def run(label, command, env=None):
    assert not (QA/(label+'.stdout.log')).exists(), 'Never overwrite an earlier check'
    started = time.monotonic()
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
    (QA/(label+'.stdout.log')).write_text(result.stdout)
    (QA/(label+'.stderr.log')).write_text(result.stderr)
    record = {'command':command,'exit_code':result.returncode,'seconds':round(time.monotonic()-started,3),
              'error_lines':[line for line in (result.stdout+'\n'+result.stderr).splitlines()
                             if any(marker in line for marker in ('SCRIPT ERROR','ERROR:','Assertion','Traceback','Parse Error'))]}
    print(label, json.dumps(record, ensure_ascii=False), flush=True)
    return record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--export', action='store_true')
    parser.add_argument('--check-prefix', default='')
    args = parser.parse_args()
    for name in ('tools/build_reference.py', 'tests/passive_localization_reference_test.py', 'docs/qa/v057-reference/capture-v056-baseline.py'):
        ast.parse((ROOT/name).read_text(), filename=name)
    if args.export:
        before = sources()
        save('export-source-sha256.json', before)
        prefix = tempfile.mkdtemp(prefix='godot-m1-v057-reference-')
        env = dict(os.environ, XDG_DATA_HOME=prefix+'/data', XDG_CONFIG_HOME=prefix+'/config',
                   XDG_CACHE_HOME=prefix+'/cache', GODOT_SILENCE_ROOT_WARNING='1')
        result = run('godot-export', ['godot','--headless','--path',str(ROOT),'--script','res://tools/export_reference.gd'],env)
        after = sources()
        result['source_changed_during_export'] = [name for name,value in before.items() if after.get(name)!=value]
        result['isolated_xdg_root'] = prefix
        save('godot-export-result.json', result)
        if result['exit_code'] or result['error_lines'] or result['source_changed_during_export']:
            raise SystemExit(1)
    if args.export: return
    checks = {}
    for label, command in [('python-build',['python3','tools/build_reference.py']),
                           ('python-check',['python3','tools/build_reference.py','--check']),
                           ('focused-reference',['python3','tests/passive_localization_reference_test.py']),
                           ('javascript-syntax',['node','--check','docs/reference/reference.js'])]:
        checks[label] = run(args.check_prefix+label,command)
    save(args.check_prefix+'python-validation-results.json', checks)
    if any(result['exit_code'] or result['error_lines'] for result in checks.values()):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
