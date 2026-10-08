#!/usr/bin/env python3
"""One bounded canonical-panel search fixture in isolated userdata; no full suite."""
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / 'docs/qa/passive-description-search'
QA.mkdir(parents=True, exist_ok=True)
inputs = ['scripts/ui/canonical_passive_panel.gd', 'tests/passive_description_search_test.gd',
          'scripts/ui/source_passive_tree_view.gd', 'scripts/canonical_game_state.gd',
          'scripts/passives/source_tree_runtime.gd', 'scripts/save/canonical_build_rules.gd',
          'data/passives/official_tree_runtime.json', 'data/passive_source/localization_zh_CN.json']
hashes = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in inputs}
with tempfile.TemporaryDirectory(prefix='godot-passive-search-', dir='/tmp') as tmp:
    env = dict(os.environ)
    for key, folder in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
        path = Path(tmp) / folder
        path.mkdir()
        env[key] = str(path)
    env['PASSIVE_SEARCH_REPORT'] = str(QA / 'results.json')
    command = ['godot', '--headless', '--path', str(ROOT), '--script', 'res://tests/passive_description_search_test.gd']
    started = time.monotonic()
    try:
        run = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=40)
    except subprocess.TimeoutExpired as error:
        (QA / 'stdout.log.txt').write_bytes(error.stdout or b'')
        (QA / 'verification.json').write_text(json.dumps({'ok': False, 'error': '40-second timeout', 'sha256': hashes}, indent=2) + '\n')
        raise
    elapsed = round(time.monotonic() - started, 3)
    (QA / 'stdout.log.txt').write_text(run.stdout)
    match = re.search(r'checks=(\d+) failures=(\d+) submissions=(\d+)', run.stdout)
    ok = run.returncode == 0 and match is not None and int(match[2]) == 0 and 'ERROR:' not in run.stdout
    counts = dict(zip(['checks', 'failures', 'submissions'], map(int, match.groups()))) if match else None
    meta = {'baseline': '3c479ab6113546d455d38ee0ab95930d399921de', 'command': command,
            'isolated_xdg': tmp, 'timeout_seconds': 40, 'elapsed_seconds': elapsed,
            'exit_code': run.returncode, 'ok': ok, 'counts': counts, 'sha256': hashes}
    (QA / 'verification.json').write_text(json.dumps(meta, indent=2) + '\n')
    print(json.dumps({'ok': ok, 'exit_code': run.returncode, 'elapsed': elapsed, 'counts': counts}), flush=True)
    if not ok:
        print(run.stdout[-5000:])
        raise SystemExit(1)
