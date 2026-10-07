#!/usr/bin/env python3
"""Run the read-only resistance authority projection once; retain every attempt."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def main():
    assert not (QA / 'export-run.json').exists(), 'Retain the first attempt; do not overwrite it'
    assert not (QA / 'authority-fragment.json').exists()
    pending = ['tools/resistance_targeted_reforge_reference.gd']
    inputs = set()
    while pending:
        path = pending.pop()
        if path in inputs or not (ROOT / path).is_file():
            continue
        inputs.add(path)
        if Path(path).suffix not in ['.gd', '.tscn', '.tres']:
            continue
        for entry in re.findall(r'res://([^"\n]+)', (ROOT / path).read_text()):
            if (ROOT / entry).is_file():
                pending.append(entry)
    inputs.update(['project.godot', 'docs/qa/v103-reference/run-export.py',
        'docs/qa/v103-rules/results.json', 'docs/qa/v103-rules/results-run-03-current-and-historical.json',
        'docs/qa/v103-rules/run-03-current-and-historical.log.txt',
        'docs/qa/v103-transactions/first/execution.json', 'docs/qa/v103-transactions/first/run.log',
        'docs/qa/v103-transactions/first/source-hashes.sha256',
        'docs/qa/v103-transactions/first/artifact-hashes.sha256'])
    inputs.update(str(p.relative_to(ROOT)) for p in (ROOT / 'docs/qa/v103-transactions/first').glob('*.save'))
    fingerprints = {p: sha(p) for p in sorted(inputs)}
    (QA / 'export-input-sha256.json').write_text(json.dumps(fingerprints, indent=2) + '\n')
    isolated = Path(tempfile.mkdtemp(prefix='godot-v103-reference-'))
    env = dict(os.environ)
    for key, child in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
        folder = isolated / child
        folder.mkdir()
        env[key] = str(folder)
    command = ['godot', '--headless', '--path', str(ROOT), '--script', 'res://tools/resistance_targeted_reforge_reference.gd']
    start = time.monotonic()
    try:
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=50)
        stdout, stderr, code = result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired as error:
        stdout, stderr, code = error.stdout or b'', error.stderr or b'', 124
        stdout = stdout.decode(errors='replace') if isinstance(stdout, bytes) else stdout
        stderr = stderr.decode(errors='replace') if isinstance(stderr, bytes) else stderr
    (QA / 'export.stdout.log.txt').write_text(stdout)
    (QA / 'export.stderr.log.txt').write_text(stderr)
    record = {'command': command, 'exit_code': code, 'elapsed_seconds': time.monotonic() - start,
        'isolated_user_data': env['XDG_DATA_HOME'], 'export_count': int((QA / 'authority-fragment.json').exists()),
        'input_count': len(inputs), 'inputs_unchanged': all(sha(p) == v for p, v in fingerprints.items()),
        'scope': 'Read-only authority, catalog definitions and exporter-witness checks. Reuses actual model transactions and saves; no model, full exporter, editor import, scene, combat, art or writes to user saves.'}
    (QA / 'export-run.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(record, indent=2))
    print(stdout)
    print(stderr)
    assert code == 0 and record['export_count'] == 1 and record['inputs_unchanged']
    assert 'ERROR' not in stdout + stderr and 'SCRIPT ERROR' not in stdout + stderr


if __name__ == '__main__':
    main()
