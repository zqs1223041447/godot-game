#!/usr/bin/env python3
"""Exactly one pure v096 typed-byte validation. Never import or benchmark."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
ORACLE = ROOT / 'docs/qa/v095-rules'
BASE = 'eaf298a8cbd22c8387da28da118a15afdcd2afb5'
RELEASE_BASE = '031ff92'
TEST = 'tests/burn_prediction_equivalence_test.gd'
OLD_TEST = 'tests/burn_profile_shortcut_equivalence_test.gd'
DEFENSE = 'scripts/mechanics/defense_rules.gd'
MAIN = 'scripts/main.gd'
REFERENCE_PATTERN = re.compile(r'''(?:preload|load)\s*\(\s*["']res://([^"']+)["']\s*\)''')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def write_json(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2) + '\n')


def function_bodies(source):
    result = {}
    for match in re.finditer(r'(?ms)^(?:static )?func (\w+)\(.*?(?=^(?:static )?func |\Z)', source):
        lines = match.group().splitlines()
        while lines and (not lines[-1].strip() or lines[-1].startswith('#')):
            lines.pop()
        result[match.group(1)] = '\n'.join(lines)
    return result


def verify_sources():
    manifest = json.loads((ORACLE / 'manifest.json').read_text())
    assert manifest['source_commit'] == BASE
    assert len(manifest['entries']) == 1
    entry = manifest['entries'][0]
    assert entry['path'] == DEFENSE
    source = git('show', f'{BASE}:{DEFENSE}')
    assert git('rev-parse', f'{BASE}:{DEFENSE}').decode().strip() == entry['git_blob']
    assert digest(source) == entry['source_sha256']
    assert (ORACLE / 'source' / (DEFENSE + '.txt')).read_bytes() == source
    frozen = re.sub(rb'^class_name [^\n]+\n', b'', source, flags=re.M)
    assert (ORACLE / 'frozen' / DEFENSE).read_bytes() == frozen
    assert digest(frozen) == entry['frozen_sha256']
    assert git('show', f'{RELEASE_BASE}:{DEFENSE}') == source, 'Prior released production must equal pinned oracle bytes'
    dependencies = {item['path']: item for item in manifest['shared_dependency_closure']}
    visited, pending = set(), REFERENCE_PATTERN.findall(source.decode())
    while pending:
        path = pending.pop()
        if path in visited:
            continue
        visited.add(path)
        dependency = dependencies[path]
        baseline = git('show', f'{BASE}:{path}')
        assert git('rev-parse', f'{BASE}:{path}').decode().strip() == dependency['git_blob']
        assert digest(baseline) == dependency['source_sha256']
        assert (ROOT / path).read_bytes() == baseline, path
        assert git('show', f'{RELEASE_BASE}:{path}') == baseline, path
        pending.extend(REFERENCE_PATTERN.findall(baseline.decode()))
    assert visited == set(dependencies), 'Manifest must cover complete literal preload/load closure'
    old = function_bodies(source.decode())
    current = function_bodies((ROOT / DEFENSE).read_text())
    assert set(current) - set(old) == {'monster_burn_prediction', '_burn_after_resistance'}
    assert not set(old) - set(current)
    changed = [name for name in old if old[name] != current[name]]
    assert changed == ['incoming_burn'], changed
    assert old['incoming_burn'].replace('raw*(1.0-resistance)', '_burn_after_resistance(raw,resistance)') == current['incoming_burn']
    assert current['_burn_after_resistance'] == 'static func _burn_after_resistance(raw:float,resistance:float)->float:\n\treturn raw*(1.0-resistance)'
    original_main = git('show', f'{RELEASE_BASE}:{MAIN}')
    old_call = b'Defense.incoming_burn(float(status.raw_dps),target.get("resistances",{}).get("fire",0.0),0.0,1.0,"monster")'
    new_call = b'Defense.monster_burn_prediction(float(status.raw_dps),target.get("resistances",{}).get("fire",0.0))'
    assert original_main.count(old_call) == 1
    assert original_main.replace(old_call, new_call) == (ROOT / MAIN).read_bytes(), 'Main is identical except the single prediction call; death_at formula and ULP guard are unchanged'
    old_vectors = function_bodies((ROOT / OLD_TEST).read_text())
    new_vectors = function_bodies((ROOT / TEST).read_text())
    reused = [name for name in old_vectors if name != '_initialize']
    for name in reused:
        assert old_vectors[name] == new_vectors[name], 'All prior typed vectors/helpers must be preserved: ' + name
    return {
        'oracle_git_blob': entry['git_blob'],
        'oracle_source_sha256': entry['source_sha256'],
        'oracle_frozen_sha256': entry['frozen_sha256'],
        'release_baseline_commit': git('rev-parse', RELEASE_BASE).decode().strip(),
        'release_defense_equals_oracle_source': True,
        'shared_dependency_paths': sorted(visited),
        'shared_dependency_hashes': {path: dependencies[path]['source_sha256'] for path in sorted(visited)},
        'shared_dependency_closure_matches_both_baselines': True,
        'independently_frozen_full_closure': False,
        'existing_changed_production_functions': changed,
        'new_production_functions': sorted(set(current) - set(old)),
        'actual_burn_only_extracts_original_multiplication': True,
        'main_only_replaces_single_prediction_call': True,
        'unchanged_v095_vector_and_helper_functions': reused,
    }


def main():
    assert (ROOT / '.godot/global_script_class_cache.cfg').is_file(), 'Copied cache must exist; never import'
    assert not (OUT / 'run-start.json').exists(), 'Preserve first attempt; never overwrite run evidence'
    initial = verify_sources()
    paths = sorted({DEFENSE, MAIN, TEST, OLD_TEST, 'project.godot', 'docs/qa/v096-rules/run.py',
                    'docs/qa/v095-rules/manifest.json', 'docs/qa/v095-rules/source/' + DEFENSE + '.txt',
                    'docs/qa/v095-rules/frozen/' + DEFENSE, *initial['shared_dependency_paths']})
    before = {path: digest((ROOT / path).read_bytes()) for path in paths}
    write_json('input-sha256-before.json', before)
    (OUT / 'test-as-executed.gd.txt').write_bytes((ROOT / TEST).read_bytes())
    command = ['/usr/local/bin/godot', '--headless', '--path', str(ROOT), '--script', 'res://' + TEST]
    isolation = Path(tempfile.mkdtemp(prefix='godot-m1-v096-rules-', dir='/tmp'))
    env = os.environ.copy()
    for key, name in {'XDG_DATA_HOME': 'data', 'XDG_CONFIG_HOME': 'config', 'XDG_CACHE_HOME': 'cache',
                      'XDG_STATE_HOME': 'state', 'XDG_RUNTIME_DIR': 'runtime'}.items():
        location = isolation / name
        location.mkdir(mode=0o700)
        env[key] = str(location)
    env['GODOT_SILENCE_ROOT_WARNING'] = '1'
    record = {'baseline_commit': BASE, 'validated_head': git('rev-parse', 'HEAD').decode().strip(),
              'command': command, 'isolation': str(isolation),
              'xdg': {key: value for key, value in env.items() if key.startswith('XDG_')},
              'verification_start': initial, 'engine_import_invoked': False, 'microbenchmark_run': False,
              'historical_suite_run': False, 'started_at_unix': time.time()}
    write_json('run-start.json', record)
    started = time.monotonic()
    code, stdout, stderr = None, b'', b''
    try:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        code, stdout, stderr = result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired as error:
        stdout, stderr = error.stdout or b'', error.stderr or b''
        record['timeout_seconds'] = 60
    except Exception as error:
        record['runner_error'] = repr(error)
    finally:
        (OUT / 'stdout.log.txt').write_bytes(stdout)
        (OUT / 'stderr.log.txt').write_bytes(stderr)
        after = {path: digest((ROOT / path).read_bytes()) for path in paths}
        write_json('input-sha256-after.json', after)
        record.update(exit_code=code, elapsed_seconds=round(time.monotonic() - started, 6), input_hashes_unchanged=before == after)
        try:
            record['verification_finish'] = verify_sources()
        except Exception as error:
            record['verification_finish_error'] = repr(error)
        merged = (stdout + stderr).decode(errors='replace')
        record['engine_errors'] = bool(re.search(r'(^|\s)(SCRIPT ERROR:|ERROR:)', merged))
        for line in stdout.decode(errors='replace').splitlines():
            if line.startswith('BURN_PREDICTION_EQUIVALENCE '):
                report = json.loads(line.removeprefix('BURN_PREDICTION_EQUIVALENCE '))
                write_json('results.json', report)
                record['result_failures'] = report['failures']
                record['result_checks'] = report['checks']
        record['passed'] = (code == 0 and not record['engine_errors'] and before == after
                            and 'verification_finish_error' not in record
                            and record.get('result_failures') == 0)
        write_json('run-record.json', record)
    print(stdout.decode(errors='replace'), end='')
    print(stderr.decode(errors='replace'), end='')
    print(json.dumps({key: record[key] for key in ['passed', 'exit_code', 'elapsed_seconds', 'engine_errors', 'input_hashes_unchanged']}))
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
