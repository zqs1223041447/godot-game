from pathlib import Path
import os,subprocess,tempfile,time,json,hashlib
R=Path('/workspace/scratch/a51485f153de/v052-burn-rate-experiment');O=R/'docs/qa/v052-rate';results=[]
for mode in ['ignite','ember_deaths','ember_proliferation']:
 label='final-'+mode;tmp=Path(tempfile.mkdtemp(prefix='godot-m1-v052-'+label+'-'));env=os.environ.copy();env.update({f'XDG_{k}_HOME':str(tmp/k.lower()) for k in ['DATA','CONFIG','CACHE']});env.update(DENSITY_INSTRUMENTED='0',DENSITY_MODE=mode,DENSITY_PROFILE_OUT=str(O/(label+'.json')))
 cmd=['/usr/local/bin/godot','--headless','--path',str(R),'--script',str(R/'tools/diagnostics/burn_rate_profile.gd')];t=time.monotonic();p=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=90);log=p.stdout+p.stderr;(O/(label+'.log')).write_text(log);row={'label':label,'source':'6f937332997ca968cbdd7468177c6074aa7856c2','exit_code':p.returncode,'seconds':time.monotonic()-t,'errors':[x for x in log.splitlines() if 'ERROR' in x]};results.append(row);(O/'final-runner.json').write_text(json.dumps(results,indent=2)+'\n');print(row,flush=True)
 if p.returncode or row['errors'] or 'LATEST_DENSITY_PROFILE_COMPLETE' not in log:print(log);raise SystemExit(1)
 d=json.loads((O/(label+'.json')).read_text())['rows'][0];print(d['tick'],flush=True)
 b=(tmp/'data/godot-game-preview-v021/build_save.json').read_bytes();(O/(label+'.save')).write_bytes(b);row['save_bytes']=len(b);row['save_sha256']=hashlib.sha256(b).hexdigest();raw=(O/(label+'-'+mode+'.bin')).read_bytes();row['observation_bytes']=len(raw);row['observation_sha256']=hashlib.sha256(raw).hexdigest();row['exact_observation_equal']=raw==(O/('before-'+mode+'-'+mode+'.bin')).read_bytes();row['exact_save_equal']=b==(O/('before-'+mode+'.save')).read_bytes();assert row['exact_observation_equal'] and row['exact_save_equal'],row
 (O/'final-runner.json').write_text(json.dumps(results,indent=2)+'\n')
