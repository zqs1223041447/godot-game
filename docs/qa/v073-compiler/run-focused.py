#!/usr/bin/env python3
"""Run only Frost Lock compiler and schema/economy tests after shared import."""
import datetime, hashlib, json, os, pathlib, re, subprocess, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent

def dependencies(path, seen=None):
    seen = set() if seen is None else seen
    if path in seen or not path.is_file(): return seen
    seen.add(path)
    if path.suffix == '.gd':
        for relative in re.findall(r'"res://([^"\n]+\.(?:gd|json|tscn|png))"', path.read_text()):
            dependencies(ROOT / relative, seen)
    return seen

def run(script, kind):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    base = pathlib.Path(tempfile.mkdtemp(prefix='godot-m1-v073-' + kind + '-'))
    env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING='1')
    report = OUT / (stamp + '-' + kind + '-checks.json')
    env['V073_' + kind.upper() + '_REPORT'] = str(report)
    for key, directory in [('XDG_DATA_HOME','data'), ('XDG_CONFIG_HOME','config'), ('XDG_CACHE_HOME','cache')]:
        target = base / directory
        target.mkdir()
        env[key] = str(target)
    inputs = dependencies(ROOT / script)
    inputs.add(ROOT / 'project.godot')
    if kind == 'migration':
        inputs.update((ROOT / 'docs/qa/v072-gameplay/fixtures').glob('*.json'))
        inputs.update((ROOT / 'assets/ui/grimoire').glob('*.png'))
        inputs.update(ROOT / p for p in ['data/passive_source/data.json', 'data/passives/official_tree_runtime.json', 'data/passive_source/localization_zh_CN.json'])
    def hashes(): return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(inputs)}
    before = hashes()
    command = [os.environ.get('GODOT_BIN', '/usr/local/bin/godot'), '--headless', '--path', str(ROOT), '--script', script]
    start = time.monotonic()
    try:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=55)
        log, code = result.stdout, result.returncode
    except subprocess.TimeoutExpired as exc:
        log, code = exc.stdout or b'', 124
    log_name = stamp + '-' + kind + '.log.txt'
    (OUT / log_name).write_bytes(log)
    after = hashes()
    receipt = dict(command=command, exit_code=code, elapsed_seconds=round(time.monotonic()-start, 3), isolated_user_dir=str(base),
                   log=log_name, report=report.name, script_errors=log.count(b'SCRIPT ERROR'), engine_errors=log.count(b'ERROR:'),
                   inputs_before=before, inputs_after=after, inputs_unchanged=before == after)
    (OUT / (stamp + '-' + kind + '-receipt.json')).write_text(json.dumps(receipt, indent=2) + '\n')
    print(log.decode(errors='replace'), flush=True)
    print(json.dumps({key:receipt[key] for key in ['exit_code', 'elapsed_seconds', 'script_errors', 'engine_errors', 'inputs_unchanged', 'log']}), flush=True)
    return code or int(bool(receipt['script_errors'] or receipt['engine_errors'] or before != after))

if __name__ == '__main__':
    import sys
    selection = sys.argv[1:] or ['compiler', 'migration']
    code = 0
    for kind in selection:
        script = 'tests/frost_lock_support_compiler_test.gd' if kind == 'compiler' else 'tests/frost_lock_gem_migration_test.gd'
        code |= run(script, kind)
    raise SystemExit(code)
