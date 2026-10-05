#!/usr/bin/env python3
"""One bounded focused source/schema36 run; preserve every attempt and raw log."""
import datetime, hashlib, json, os, pathlib, subprocess, tempfile, time
root = pathlib.Path(__file__).resolve().parents[3]
out = pathlib.Path(__file__).resolve().parent
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
isolated = pathlib.Path(tempfile.mkdtemp(prefix='godot-m1-v059-source-'))
env = dict(os.environ, XDG_DATA_HOME=str(isolated / 'data'), XDG_CONFIG_HOME=str(isolated / 'config'), XDG_CACHE_HOME=str(isolated / 'cache'), GODOT_SILENCE_ROOT_WARNING='1', V059_SOURCE_REPORT=str(out / f'{stamp}-checks.json'))
for name in ['data', 'config', 'cache']:
    (isolated / name).mkdir()
script = 'tests/source_resistance_cap_migration_test.gd'
inputs = [script, 'scripts/passives/source_stat_patterns.gd', 'scripts/passives/source_tree_runtime.gd', 'scripts/passives/source_tree_localization.gd', 'scripts/save/canonical_build_rules.gd', 'scripts/save/canonical_build_store.gd', 'scripts/save/elemental_resistance_cap_migration.gd', 'scripts/save/mana_guard_migration.gd', 'scripts/canonical_game_state.gd', 'scripts/mechanics/defense_rules.gd', 'data/passive_source/data.json', 'data/passives/official_tree_runtime.json', 'data/passive_source/localization_zh_CN.json']
def hashes():
    return {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in inputs}
before = hashes()
command = ['/usr/local/bin/godot', '--headless', '--path', str(root), '--script', script]
started = time.monotonic()
try:
    result = subprocess.run(command, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
    log, code = result.stdout, result.returncode
except subprocess.TimeoutExpired as exc:
    log, code = exc.stdout or b'', 124
(out / f'{stamp}.log.txt').write_bytes(log)
after = hashes()
summary = dict(command=command, isolated_user_dir=str(isolated), exit_code=code, elapsed_seconds=round(time.monotonic()-started, 3), log=f'{stamp}.log.txt', report=f'{stamp}-checks.json', script_errors=log.count(b'SCRIPT ERROR'), engine_errors=log.count(b'ERROR:'), inputs_before=before, inputs_after=after, inputs_unchanged=before==after)
(out / f'{stamp}-attempt.json').write_text(json.dumps(summary, indent=2)+'\n')
print(log.decode(errors='replace'))
print(json.dumps({k:summary[k] for k in ['exit_code','elapsed_seconds','script_errors','engine_errors','inputs_unchanged','log','report']}))
raise SystemExit(code or int(summary['script_errors'] > 0) or int(summary['engine_errors'] > 0))
