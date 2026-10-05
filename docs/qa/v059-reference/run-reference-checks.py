#!/usr/bin/env python3
"""Bounded v59 reference/font checks, immutable per-run evidence; no gameplay replay."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
QA = ROOT/'docs/qa/v059-reference'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    paths = [ROOT/'project.godot', ROOT/'tools/export_reference.gd', ROOT/'tools/build_reference.py',
             ROOT/'tools/export_source_execution_coverage.gd', ROOT/'tools/check_font_coverage.py',
             ROOT/'docs/qa/v053-source/source-coverage.json', ROOT/'docs/qa/v054-source/source-coverage.json',
             ROOT/'docs/qa/v056-reference/v055-basic-snapshots.json', ROOT/'docs/qa/v059-source/allocation-witness.json',
             ROOT/'assets/fonts/arena_sans.otf', ROOT/'assets/fonts/coverage_manifest.json']
    paths += sorted((ROOT/'scripts').rglob('*.gd')) + sorted((ROOT/'data').rglob('*.json'))
    return {p.relative_to(ROOT).as_posix():sha(p) for p in paths}


def save(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def run(label, command, env=None):
    actual_paths = [ROOT/arg for arg in command if (ROOT/arg).is_file()]
    if any('check-reference.py' in arg for arg in command):
        actual_paths += [ROOT/'docs/reference/catalog.json', ROOT/'docs/reference/index.html', ROOT/'docs/reference/source-tree-coverage.json', QA/'v058-art-baseline.json']
    before = sources()
    before.update({p.relative_to(ROOT).as_posix():sha(p) for p in actual_paths})
    save(QA/(label+'-input-sha256.json'), before)
    started = time.monotonic()
    timed_out = False
    try:
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
        stdout, stderr, code = result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        stdout = exc.stdout.decode() if isinstance(exc.stdout, bytes) else (exc.stdout or '')
        stderr = exc.stderr.decode() if isinstance(exc.stderr, bytes) else (exc.stderr or '')
        code = None
    for kind, text in [('stdout',stdout),('stderr',stderr)]:
        with (QA/(label+'.'+kind+'.log.txt')).open('x') as stream: stream.write(text)
    after = sources()
    after.update({p.relative_to(ROOT).as_posix():sha(p) for p in actual_paths})
    record={'command':command,'exit_code':code,'timed_out':timed_out,'seconds':round(time.monotonic()-started,3),
            'error_lines':[line for line in (stdout+'\n'+stderr).splitlines() if any(x in line for x in ['SCRIPT ERROR','ERROR:','Assertion','Traceback','Parse Error'])],
            'source_changed_during_run':[name for name,value in before.items() if after.get(name)!=value]}
    save(QA/(label+'-result.json'), record)
    print(label, json.dumps(record, ensure_ascii=False), flush=True)
    if code != 0 or record['error_lines'] or record['source_changed_during_run']: raise SystemExit(1)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('stage',choices=['export','font','build']);parser.add_argument('--prefix',default='')
    args=parser.parse_args()
    if args.stage=='export':
        directory=tempfile.mkdtemp(prefix='godot-v059-reference-')
        env=dict(os.environ,XDG_DATA_HOME=directory+'/data',XDG_CONFIG_HOME=directory+'/config',XDG_CACHE_HOME=directory+'/cache',GODOT_SILENCE_ROOT_WARNING='1')
        run(args.prefix+'godot-export',['godot','--headless','--path',str(ROOT),'--script','res://tools/export_reference.gd'],env)
    elif args.stage=='font':
        run(args.prefix+'font-coverage',['python3','tools/check_font_coverage.py','--json'])
    else:
        for name,command in [('build',['python3','tools/build_reference.py']),('build-check',['python3','tools/build_reference.py','--check']),('javascript-syntax',['node','--check','docs/reference/reference.js'])]:
            run(args.prefix+name,command)


if __name__=='__main__':main()
