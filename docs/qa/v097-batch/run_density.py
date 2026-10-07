from pathlib import Path
import gzip, hashlib, json, os, selectors, signal, subprocess, tempfile, time
ROOT=Path(__file__).resolve().parents[3]
QA=Path(__file__).resolve().parent
BASE=ROOT/'docs/qa/v095-profile'
HARNESS=QA/'density-candidate.gd'
RUNS=[]
changed=subprocess.check_output(['git','diff','d2d188a','--name-only','--','scripts','assets','scenes','data','project.godot'],cwd=ROOT,text=True).splitlines()
assert changed==[],changed
paths=['tools/diagnostics/lazy_burn_batch_main.gd','tools/diagnostics/burn_batch_guard.gd','tools/diagnostics/burn_deadline_shadow.gd','tools/diagnostics/burn_read_dependency_shadow.gd','tools/diagnostics/compare_lazy_burn_observations.gd','docs/qa/v097-batch/density-candidate.gd']
source_hashes={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}
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
for mode,label,before_label in [('ember_deaths','lazy_ember','clean'),('no_burn','lazy_no_burn','clean_no_burn')]:
    current=run_one(label,False,mode)
    previous=json.loads((BASE/(before_label+'.json')).read_text())
    before=next(r for r in previous['rows'] if r['mode']==mode);after=current['rows'][0]
    assert not current['instrumented'] and current['production_without_counter_wrappers'] and current['diagnostic_subclass']
    assert len(before['samples'])==len(after['samples'])=={'ember_deaths':20,'no_burn':4}[mode]
    reports=[]
    for suffix in ['.bin','-final.bin']:
        old_path=BASE/(before_label+'-'+mode+suffix)
        if not old_path.exists():
            raw=gzip.decompress(Path(str(old_path)+'.gz').read_bytes());old_path=QA/('reused-'+before_label+'-'+mode+suffix);old_path.write_bytes(raw)
        new_path=QA/(label+'-'+mode+suffix)
        compare_path=QA/(label+suffix+'.comparison.json');log_path=QA/(label+suffix+'.comparison.log')
        isolated=Path(tempfile.mkdtemp(prefix='godot-m1-v097-compare-'));env=os.environ.copy()
        env.update(XDG_DATA_HOME=str(isolated/'data'),XDG_CACHE_HOME=str(isolated/'cache'),XDG_CONFIG_HOME=str(isolated/'config'),V097_BEFORE=str(old_path),V097_AFTER=str(new_path),V097_COMPARE_OUT=str(compare_path))
        result=subprocess.run(['/usr/local/bin/godot','--headless','--path',str(ROOT),'--script','res://tools/diagnostics/compare_lazy_burn_observations.gd'],env=env,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
        log_path.write_bytes(result.stdout)
        report=json.loads(compare_path.read_text())
        reports.append({'path':compare_path.name,'exit_code':result.returncode,'ok':report['ok'],'exact_input_bytes_equal':report['exact_input_bytes_equal'],'numeric':report['numeric'],'discrete_differences':report['exact_discrete_difference_count']})
        print('COMPARE',mode,suffix,json.dumps(reports[-1]),flush=True)
        if result.returncode!=0 or b'ERROR' in result.stdout or not report['ok']:raise RuntimeError('Candidate behavior comparison failed: '+str(compare_path))
        if mode=='no_burn':assert report['exact_input_bytes_equal'],'No-burn control must be exact'
        raw=new_path.read_bytes();packed=gzip.compress(raw,mtime=0);Path(str(new_path)+'.gz').write_bytes(packed);assert gzip.decompress(packed)==raw
    old_save=BASE/(before_label+'-'+mode+'.save');old=old_save.read_bytes() if old_save.exists() else gzip.decompress(Path(str(old_save)+'.gz').read_bytes())
    new_save=QA/(label+'-'+mode+'.save');assert new_save.read_bytes()==old,'Actual persisted bytes differ'
    Path(str(new_save)+'.gz').write_bytes(gzip.compress(old,mtime=0))
    metrics={key:{'before':before['tick'][key],'after':after['tick'][key],'change_fraction':after['tick'][key]/before['tick'][key]-1.0} for key in ['mean_us','p50_us','p95_us','max_us']}
    comparisons[mode]={'frames':before['frames'],'metrics':metrics,'comparisons':reports,'save_exact':True,'shadow_batches':after.get('shadow_batches',[]),'before_samples':before['samples'],'after_samples':after['samples']}
    (QA/'density-comparison.json').write_text(json.dumps(comparisons,indent=2)+'\n')
    print('DENSITY_COMPARE',mode,json.dumps(metrics),flush=True)
assert source_hashes=={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}
(QA/'density-source-proof.json').write_text(json.dumps({'base':'d2d188ab3aa284a1abbb7d9e382eaf976678aab2','diagnostic_subclass_only':True,'production_changed':changed,'source_hashes':source_hashes,'prior_clean20_4_reused':True,'runs':2,'new_frames':24,'instrumented':False,'scope':'One bounded diagnostic subclass trial, not a production optimization or general FPS claim'},indent=2)+'\n')
