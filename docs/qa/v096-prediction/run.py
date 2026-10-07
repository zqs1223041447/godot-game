from pathlib import Path
import gzip, hashlib, json, os, selectors, signal, subprocess, tempfile, time
ROOT=Path(__file__).resolve().parents[3]
QA=Path(__file__).resolve().parent
BASE=ROOT/'docs/qa/v095-profile'
BASE_TREE=ROOT.parent/'v095-burn-profile-audit'
HARNESS=ROOT/'tools/diagnostics/burn_profile_allocation_audit.gd'
IGNITE=QA/'ignite-control.gd'
RUNS=[]
COMMAND=['/usr/local/bin/godot','--headless','--path',str(ROOT),'--script','res://tools/diagnostics/burn_profile_allocation_audit.gd']
changed=subprocess.check_output(['git','diff','031ff92','--name-only','--','scripts','assets','scenes','data','project.godot'],cwd=ROOT,text=True).splitlines()
assert changed==['scripts/main.gd','scripts/mechanics/defense_rules.gd'],changed
candidate_hashes={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in changed}
assert subprocess.check_output(['git','diff','eaf298a','--name-only','--','scripts','assets','scenes','data','project.godot'],cwd=BASE_TREE,text=True).strip()==''
assert (BASE_TREE/'tools/diagnostics/burn_profile_allocation_audit.gd').read_bytes()==HARNESS.read_bytes()
assert IGNITE.read_text().replace('for mode:String in ["ignite"]:','for mode:String in ["ember_deaths","no_burn"]:')==HARNESS.read_text()
def run_one(label, instrumented, mode, path=ROOT, script=HARNESS):
    command=["/usr/local/bin/godot","--headless","--path",str(path),"--script",str(script)]
    output = QA / (label + ".json")
    log = QA / (label + ".txt")
    if output.exists() or log.exists():
        raise RuntimeError("Refusing an implicit rerun: " + label)
    isolated = Path(tempfile.mkdtemp(prefix="godot-m1-v095-" + label + "-"))
    env = os.environ.copy()
    env.update({"XDG_DATA_HOME": str(isolated / "data"), "XDG_CACHE_HOME": str(isolated / "cache"), "XDG_CONFIG_HOME": str(isolated / "config"), "V095_INSTRUMENTED": str(int(instrumented)), "V095_PROFILE_OUT": str(output), "V095_MODE": mode})
    record = {"label": label, "command": command, "environment": {k: env[k] for k in ["XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "V095_INSTRUMENTED", "V095_PROFILE_OUT", "V095_MODE"]}, "frames": {mode: {"ember_deaths": 20, "no_burn": 4, "ignite": 4}[mode]}, "started_at_unix": time.time()}
    RUNS.append(record)
    (QA / "run_manifest.json").write_text(json.dumps(RUNS, indent=2) + "\n")
    print("START " + label + " " + json.dumps(record), flush=True)
    process = subprocess.Popen(command, cwd=path, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    start = time.monotonic()
    buffer = b""
    failed = ""
    complete = False
    with log.open("wb") as handle:
        while selector.get_map():
            if time.monotonic() - start > 90:
                failed = "External 90-second watchdog"
                os.killpg(process.pid, signal.SIGKILL)
                break
            for key, _ in selector.select(timeout=0.1):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                handle.write(chunk)
                handle.flush()
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    text = line.decode("utf-8", errors="replace")
                    print(text, flush=True)
                    if "ERROR" in text or "Assertion failed" in text:
                        failed = text
                        os.killpg(process.pid, signal.SIGKILL)
                        break
                    complete = complete or "V095_BURN_PROFILE_AUDIT_COMPLETE" in text
                if failed:
                    break
            if failed:
                break
    exit_code = process.wait(timeout=10)
    record.update({"exit_code": exit_code, "elapsed_seconds": time.monotonic() - start, "first_error": failed, "completion_marker": complete})
    (QA / "run_manifest.json").write_text(json.dumps(RUNS, indent=2) + "\n")
    if failed or exit_code != 0 or not complete:
        raise RuntimeError("Stopped diagnostic; no further process will run: " + (failed or str(exit_code)))
    return json.loads(output.read_text())


def digest(data):return hashlib.sha256(data).hexdigest()
comparisons={}
for mode,label,before_label in [('ember_deaths','candidate_ember','clean'),('no_burn','candidate_no_burn','clean_no_burn'),('ignite','candidate_ignite','baseline_ignite')]:
    before_dir=BASE
    if mode=='ignite':
        run_one(before_label,False,mode,BASE_TREE,IGNITE)
        before_dir=QA
    current=run_one(label,False,mode,ROOT,IGNITE if mode=='ignite' else HARNESS)
    previous=json.loads((before_dir/(before_label+'.json')).read_text())
    a=next(r for r in previous['rows'] if r['mode']==mode);b=current['rows'][0]
    assert not current['instrumented'] and current['production_without_wrappers']
    assert len(a['samples'])==len(b['samples'])=={'ember_deaths':20,'no_burn':4,'ignite':4}[mode]
    for old,new in zip(a['samples'],b['samples'],strict=True):
        assert old['frame']==new['frame'] and old['observation_sha256']==new['observation_sha256'],(mode,old['frame'],'observation differs')
    exact=[]
    for suffix in ['.bin','-final.bin','.save']:
        old_path=before_dir/(before_label+'-'+mode+suffix);new_path=QA/(label+'-'+mode+suffix)
        old=old_path.read_bytes() if old_path.exists() else gzip.decompress(Path(str(old_path)+'.gz').read_bytes())
        new=new_path.read_bytes();assert old==new,(mode,suffix,digest(old),digest(new))
        packed=gzip.compress(new,mtime=0);Path(str(new_path)+'.gz').write_bytes(packed);assert gzip.decompress(packed)==new
        exact.append({'suffix':suffix,'bytes':len(new),'sha256':digest(new),'exact':True,'archive':new_path.name+'.gz','compressed_bytes':len(packed),'archive_sha256':digest(packed)})
    metrics={}
    for key in ['mean_us','p50_us','p95_us','max_us']:
        metrics[key]={'before':a['tick'][key],'after':b['tick'][key],'change_fraction':b['tick'][key]/a['tick'][key]-1.0}
    comparisons[mode]={'frames':a['frames'],'before_file':before_label+'.json','after_file':label+'.json','metrics':metrics,'exact_observations':exact,'per_frame_equal':True,'before_samples':a['samples'],'after_samples':b['samples']}
    (QA/'comparison.json').write_text(json.dumps(comparisons,indent=2)+'\n')
    print('CANDIDATE_COMPARE',mode,json.dumps(metrics),flush=True)
assert candidate_hashes=={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in changed}
(QA/'source-proof.json').write_text(json.dumps({'base':'031ff92fab6383461a2688e3be85331655f05351','candidate_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'production_changed':changed,'candidate_hashes':candidate_hashes,'prior_valid_clean_20_4_reused':True,'candidate_clean_processes':3,'new_baseline_ignite_processes':1,'new_candidate_frames':28,'instrumented':False,'harness_sha256':digest(HARNESS.read_bytes()),'ignite_harness_sha256':digest(IGNITE.read_bytes()),'scope':'Single candidate; new ordinary-ignite control has same harness except mode selection. No counter wrappers inside timed tick. No repeat of existing clean 20/4 baseline.'},indent=2)+'\n')
