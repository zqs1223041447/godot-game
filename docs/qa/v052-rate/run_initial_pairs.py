from pathlib import Path
import os,subprocess,tempfile,time,json,hashlib,gzip
R=Path('/workspace/scratch/a51485f153de/v052-burn-rate-experiment');B=R.parent/'v051-reward-inventory-cost';O=R/'docs/qa/v052-rate';results=[]
work=[(mode,tree,label) for mode in ['ember_proliferation','ember_deaths'] for tree,label in [(B,'before'),(R,'after')]]+[(mode,R,'control') for mode in ['no_burn','ignite']]
for mode,tree,stage in work:
 label=stage+'-'+mode;tmp=Path(tempfile.mkdtemp(prefix='godot-m1-v052-'+label+'-'));env=os.environ.copy();env.update({f'XDG_{k}_HOME':str(tmp/k.lower()) for k in ['DATA','CONFIG','CACHE']});env.update(DENSITY_INSTRUMENTED='0',DENSITY_MODE=mode,DENSITY_PROFILE_OUT=str(O/(label+'.json')))
 cmd=['/usr/local/bin/godot','--headless','--path',str(tree),'--script',str(R/'tools/diagnostics/burn_rate_profile.gd')];t=time.monotonic();p=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=90);log=p.stdout+p.stderr;(O/(label+'.log')).write_text(log);row={'label':label,'source':'d6684d27517e4661abd832d586fcdbb72185929e' if stage=='before' else '46dc4507328ed971d5e4fca668de400feba3fb05','exit_code':p.returncode,'seconds':time.monotonic()-t,'errors':[x for x in log.splitlines() if 'ERROR' in x]};results.append(row);(O/'runner.json').write_text(json.dumps(results,indent=2)+'\n');print(row,flush=True)
 if p.returncode or row['errors'] or 'LATEST_DENSITY_PROFILE_COMPLETE' not in log:print(log);raise SystemExit(1)
 d=json.loads((O/(label+'.json')).read_text())['rows'][0];print(d['tick'],flush=True)
 save=tmp/'data/godot-game-preview-v021/build_save.json';b=save.read_bytes();(O/(label+'.save')).write_bytes(b);row['save_bytes']=len(b);row['save_sha256']=hashlib.sha256(b).hexdigest()
 observation=O/(label+'-'+mode+'.bin');raw=observation.read_bytes();row['observation_bytes']=len(raw);row['observation_sha256']=hashlib.sha256(raw).hexdigest()
 if stage=='before':
  with gzip.GzipFile(filename=str(observation)+'.gz',mode='wb',mtime=0) as f:f.write(raw)
 if stage=='after':
  original=(O/('before-'+mode+'-'+mode+'.bin')).read_bytes();row['exact_observation_equal']=raw==original;row['exact_save_equal']=b==(O/('before-'+mode+'.save')).read_bytes();assert row['exact_observation_equal'] and row['exact_save_equal'],row
 if stage=='control':
  baseline=gzip.decompress((R/'docs/qa/v050-density'/('clock-fixed-'+mode+'.bin.gz')).read_bytes());row['exact_observation_equal']=raw==baseline;assert row['exact_observation_equal'],row
 (O/'runner.json').write_text(json.dumps(results,indent=2)+'\n')
