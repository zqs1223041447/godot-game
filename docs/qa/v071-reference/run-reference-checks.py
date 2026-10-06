#!/usr/bin/env python3
"""One bounded v71 export/build/preservation pass, using the shared import."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
ERRORS = ('SCRIPT ERROR', 'ERROR:', 'Assertion', 'Traceback', 'Parse Error')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(name, value):
    with (QA / name).open('x') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def inputs(stage):
    if stage == 'export':
        paths = [ROOT / p for p in ['project.godot', 'tools/export_reference.gd', 'tools/export_source_execution_coverage.gd']]
        paths += list((ROOT / 'scripts').rglob('*.gd')) + list((ROOT / 'data').rglob('*.json'))
        paths += list((ROOT / 'docs/qa/v070-gameplay/fixtures').glob('*.json'))
        paths += [ROOT / 'docs/qa/v070-gameplay/acceptance.json']
    elif stage == 'build':
        paths = [ROOT / p for p in ['tools/build_reference.py', 'docs/reference/catalog.json', 'docs/reference/reference.css', 'docs/reference/reference.js', 'docs/reference/art/manifest.json']]
    else:
        paths = [QA / 'check-reference.py'] + [ROOT / ('docs/reference/' + name) for name in ['catalog.json', 'index.html', 'source-tree-coverage.json']]
    return {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(set(paths))}


def run(stage, label, command, env=None):
    before = inputs(stage)
    save(label + '-input-sha256.json', before)
    preserved = [ROOT / 'docs/reference/source-tree-coverage.json'] + sorted((ROOT / 'docs/reference').rglob('*.png'))
    file_state = {p.relative_to(ROOT).as_posix(): {'sha256': sha(p), 'mtime_ns': p.stat().st_mtime_ns} for p in preserved}
    started = time.monotonic()
    output = {'stdout': [], 'stderr': []}
    stopped = None
    process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    selector = selectors.DefaultSelector()
    for name in output:
        selector.register(getattr(process, name), selectors.EVENT_READ, name)
    while selector.get_map():
        if time.monotonic() - started > 120 and process.poll() is None:
            stopped = 'timeout'
            process.kill()
        for key, _ in selector.select(.1):
            line = key.fileobj.readline()
            if not line:
                selector.unregister(key.fileobj)
                continue
            output[key.data].append(line)
            if any(marker in line for marker in ERRORS) and process.poll() is None and command[0].endswith('godot'):
                stopped = 'first_error_line'
                process.terminate()
    code = process.wait()
    selector.close()
    for name, lines in output.items():
        with (QA / (label + '.' + name + '.log.txt')).open('x') as stream:
            stream.writelines(lines)
    after = inputs(stage)
    changed_preserved = [path for path, state in file_state.items() if state != {'sha256': sha(ROOT / path), 'mtime_ns': (ROOT / path).stat().st_mtime_ns}]
    result = {'command': command, 'exit_code': code, 'stopped_on': stopped, 'seconds': round(time.monotonic() - started, 3),
              'error_lines': [line.strip() for lines in output.values() for line in lines if any(marker in line for marker in ERRORS)],
              'source_changed_during_run': [path for path in before.keys() | after.keys() if before.get(path) != after.get(path)],
              'coverage_and_reference_pngs_unchanged_in_bytes_and_mtime': not changed_preserved,
              'unexpected_preserved_file_writes': changed_preserved, 'preserved_files_before': file_state}
    save(label + '-result.json', result)
    print(json.dumps({key: value for key, value in result.items() if key != 'preserved_files_before'}, ensure_ascii=False), flush=True)
    if code or result['error_lines'] or result['source_changed_during_run'] or changed_preserved:
        raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['export', 'build', 'verify'])
    args = parser.parse_args()
    if args.stage == 'export':
        directory = tempfile.mkdtemp(prefix='godot-v071-reference-')
        env = dict(os.environ, XDG_DATA_HOME=directory + '/data', XDG_CONFIG_HOME=directory + '/config', XDG_CACHE_HOME=directory + '/cache', GODOT_SILENCE_ROOT_WARNING='1')
        run('export', 'godot-export', ['/usr/local/bin/godot', '--headless', '--path', str(ROOT), '--script', 'res://tools/export_reference.gd'], env)
    elif args.stage == 'build':
        run('build', 'build', ['python3', 'tools/build_reference.py'])
        run('build', 'build-check', ['python3', 'tools/build_reference.py', '--check'])
    else:
        run('verify', 'focused-reference', ['python3', 'docs/qa/v071-reference/check-reference.py'])


if __name__ == '__main__':
    main()
