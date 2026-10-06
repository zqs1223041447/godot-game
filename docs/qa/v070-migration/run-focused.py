#!/usr/bin/env python3
"""One native44 capture from verified v69 sources, then isolated focused tests. Never imports."""
import datetime, hashlib, json, os, pathlib, subprocess, sys, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent
OLD = pathlib.Path('/workspace/scratch/a51485f153de/v069-physical-fire-conversion')
COMMIT = 'd25717c4485bf36688df36460f2c85ebb11b7623'
GODOT = os.environ.get('GODOT_BIN', '/usr/local/bin/godot')
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
isolated = pathlib.Path(tempfile.mkdtemp(prefix='godot-m1-v070-migration-'))

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def invoke(name, project, script, extra=None):
    home = isolated/name
    env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING='1', **(extra or {}))
    for key, directory in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
        target = home/directory; target.mkdir(parents=True); env[key] = str(target)
    inputs = sorted((project/'scripts').rglob('*.gd')) + [project/'project.godot', pathlib.Path(script) if pathlib.Path(script).is_absolute() else project/script]
    inputs += [project/p for p in ['data/passive_source/data.json','data/passives/official_tree_runtime.json','data/passive_source/localization_zh_CN.json']]
    if name != 'capture44': inputs += sorted((OUT/'fixtures').glob('*.json'))
    before = {str(p):sha(p) for p in inputs}
    command = [GODOT,'--headless','--path',str(project),'--script',str(script)]
    start = time.monotonic()
    try:
        result = subprocess.run(command,cwd=project,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=55)
        log, code = result.stdout,result.returncode
    except subprocess.TimeoutExpired as exc: log,code = exc.stdout or b'',124
    log_path = OUT/f'{stamp}-{name}.log.txt'; log_path.write_bytes(log)
    after = {str(p):sha(p) for p in inputs}
    summary = dict(command=command,exit_code=code,elapsed_seconds=round(time.monotonic()-start,3),isolated_user_dir=str(home),log=log_path.name,
                   script_errors=log.count(b'SCRIPT ERROR'),engine_errors=log.count(b'ERROR:'),inputs_before=before,inputs_after=after,inputs_unchanged=before==after)
    (OUT/f'{stamp}-{name}-attempt.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(log.decode(errors='replace'),flush=True)
    print(json.dumps({k:summary[k] for k in ['exit_code','elapsed_seconds','script_errors','engine_errors','inputs_unchanged','log']}),flush=True)
    if code or summary['script_errors'] or summary['engine_errors'] or before!=after: raise SystemExit(code or 1)

if '--capture-only' in sys.argv:
    fixture = OUT/'fixtures/v44-ir-native-v069.json'
    if fixture.exists(): raise SystemExit('Native44 fixture already exists; reuse it instead of recapturing')
    paths = subprocess.check_output(['git','ls-files','scripts','data','project.godot'],cwd=OLD,text=True).splitlines()
    evidence = {}
    for path in paths:
        raw = subprocess.check_output(['git','show',f'{COMMIT}:{path}'],cwd=OLD)
        evidence[path] = {'checkout_sha256':sha(OLD/path),'commit_sha256':hashlib.sha256(raw).hexdigest()}
    exact = all(x['checkout_sha256']==x['commit_sha256'] for x in evidence.values())
    (OUT/'native-source-evidence.json').write_text(json.dumps({'source_project':str(OLD),'source_commit':COMMIT,'all_tracked_inputs_identical':exact,'files':evidence},indent=2)+'\n')
    if not exact: raise SystemExit('Native source checkout differs from verified commit inputs')
    capture = isolated/'native'; capture.mkdir()
    invoke('capture44',OLD,OUT/'capture-native44.gd',{'V070_NATIVE44_DIRECTORY':str(capture)})
    files={}
    for path in sorted(capture.glob('*.json')):
        target=OUT/'fixtures'/path.name;target.write_bytes(path.read_bytes());files[path.name]={'bytes':target.stat().st_size,'sha256':sha(target)}
    manifest=dict(description='Serialized once by genuine unchanged v0.69 production Store/schema44 from commitd25717c, not relabeled45 or a frozen archive.',source_project=str(OLD),source_commit=COMMIT,capture_script_sha256=sha(OUT/'capture-native44.gd'),capture_log=f'{stamp}-capture44.log.txt',files=files)
    (OUT/'fixtures/manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
else:
    name='source' if '--source-only' in sys.argv else 'migration'
    invoke(name,ROOT,f'tests/precise_technique_{name}_test.gd',{'V070_PRECISE_REPORT':str(OUT/f'{stamp}-{name}-checks.json')})
