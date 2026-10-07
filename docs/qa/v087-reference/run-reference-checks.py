#!/usr/bin/env python3
"""Bounded v87 frost-guard chill export/checks after shared import and accepted Main run."""
import argparse
import hashlib
import json
import os
import selectors
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
ERRORS = ('SCRIPT ERROR', 'ERROR:', 'Assertion', 'Traceback', 'Parse Error')

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def save(name, value):
    with (QA / name).open('x') as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write('\n')

def run(label, command, env=None):
    inputs = [ROOT/'project.godot', ROOT/'tools/build_reference.py']
    inputs += list((ROOT/'scripts').rglob('*.gd')) + list((ROOT/'data').rglob('*.json'))
    inputs += list((ROOT/'docs/qa/v087-gameplay').rglob('*.json'))
    inputs += list((ROOT/'docs/qa/v087-integration').glob('main-attempt01-*.json'))
    inputs += list((ROOT/'tests').glob('*chill*.gd'))
    inputs += list(QA.glob('*.gd')) + list(QA.glob('*.py'))
    inputs = sorted(set(inputs))
    before = {str(path.relative_to(ROOT)): sha(path) for path in inputs}
    save(label+'-input-sha256.json', before)
    protected = list((ROOT/'docs/reference').rglob('*.png')) + [ROOT/'docs/reference/source-tree-coverage.json']
    untouched = {str(path): (sha(path), path.stat().st_mtime_ns) for path in protected}
    started = time.monotonic()
    output = {'stdout': [], 'stderr': []}
    stopped = None
    process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    selector = selectors.DefaultSelector()
    for name in output: selector.register(getattr(process, name), selectors.EVENT_READ, name)
    while selector.get_map():
        if time.monotonic()-started > 60 and process.poll() is None:
            stopped = 'timeout'
            process.kill()
        for key, _ in selector.select(.1):
            line = key.fileobj.readline()
            if not line:
                selector.unregister(key.fileobj)
                continue
            output[key.data].append(line)
            if any(error in line for error in ERRORS) and process.poll() is None and command[0].endswith('godot'):
                stopped = 'first_error'
                process.terminate()
    code = process.wait()
    selector.close()
    for name, lines in output.items():
        with (QA/(label+'.'+name+'.log.txt')).open('x') as handle: handle.writelines(lines)
    changed = [str(path.relative_to(ROOT)) for path in inputs if before[str(path.relative_to(ROOT))] != sha(path)]
    touched = [str(path.relative_to(ROOT)) for path in protected if untouched[str(path)] != (sha(path), path.stat().st_mtime_ns)]
    result = {'command': command, 'exit_code': code, 'seconds': round(time.monotonic()-started, 3),
              'stopped_on': stopped, 'error_lines': [line.strip() for lines in output.values() for line in lines if any(error in line for error in ERRORS)],
              'source_changed_during_run': changed, 'reference_images_and_coverage_unchanged_bytes_and_mtime': not touched,
              'unexpected_preserved_file_writes': touched}
    save(label+'-result.json', result)
    print(json.dumps(result, ensure_ascii=False), flush=True)
    if code or stopped or result['error_lines'] or changed or touched: raise SystemExit(1)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['export', 'merge', 'build', 'verify'])
    parser.add_argument('--prefix', default='')
    parser.add_argument('--main-report', default='docs/qa/v087-gameplay/main-result.json')
    parser.add_argument('--main-run', default='docs/qa/v087-integration/main-attempt01-result.json')
    parser.add_argument('--main-inputs', default='docs/qa/v087-integration/main-attempt01-inputs.json')
    args = parser.parse_args()
    if args.stage == 'export':
        directory = tempfile.mkdtemp(prefix='godot-v087-reference-')
        env = dict(os.environ, XDG_DATA_HOME=directory+'/data', XDG_CONFIG_HOME=directory+'/config',
                   XDG_CACHE_HOME=directory+'/cache', GODOT_SILENCE_ROOT_WARNING='1',
                   CHILL_REFERENCE_MAIN_REPORT=args.main_report,
                   CHILL_REFERENCE_MAIN_RUN=args.main_run, CHILL_REFERENCE_MAIN_INPUTS=args.main_inputs)
        run(args.prefix+'frost-chill-fragment', ['/usr/local/bin/godot', '--headless', '--path', str(ROOT),
            '--script', 'res://docs/qa/v087-reference/export-fragment.gd'], env)
    elif args.stage == 'merge': run(args.prefix+'merge', ['python3', 'docs/qa/v087-reference/merge-fragment.py'])
    elif args.stage == 'build':
        run(args.prefix+'build', ['python3', 'tools/build_reference.py'])
    else: run(args.prefix+'focused-reference', ['python3', 'docs/qa/v087-reference/check-reference.py'])

if __name__ == '__main__': main()
