from pathlib import Path
import subprocess,os,json,time,tempfile,hashlib,math,statistics
root=Path.cwd();qa=root/'docs/qa/v089-empty-projectiles';results=[]
inputs={f:hashlib.sha256((root/f).read_bytes()).hexdigest() for f in ['scripts/main.gd','scripts/combat/projectile_runtime.gd','scripts/combat/spatial_target_index.gd','tests/empty_projectile_main_probe.gd','docs/qa/v089-empty-projectiles/main_before.gd','docs/qa/v089-empty-projectiles/runtime_before.gd']}
for label,mode in [('a0','before'),('b0','after'),('b1','after'),('a1','before')]:
 out=qa/label;out.mkdir(exist_ok=False);env=os.environ.copy();iso=tempfile.mkdtemp(prefix='godot-m1-v089-'+label+'-',dir='/tmp')
 for key in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:env[key]=iso+'/'+key;Path(env[key]).mkdir()
 env['PROBE_MODE']=mode;env['PROBE_OUT']=str(out);began=time.monotonic()
 with (out/'run.log').open('w') as f:
  try:r=subprocess.run(['/usr/local/bin/godot','--headless','--path',str(root),'--script','res://tests/empty_projectile_main_probe.gd'],env=env,stdout=f,stderr=subprocess.STDOUT,timeout=25);code=r.returncode;timed=False
  except subprocess.TimeoutExpired:code=-999;timed=True
 log=(out/'run.log').read_text();meta={'mode':mode,'exit_code':code,'seconds':round(time.monotonic()-began,3),'error_logged':'ERROR' in log,'timed_out':timed};(out/'run-result.json').write_text(json.dumps(meta,indent=2)+'\n');print(label,meta,flush=True)
 if code!=0 or meta['error_logged'] or not (out/'result.json').exists():
  print(log[-4000:],flush=True);raise SystemExit(1)
 data=json.loads((out/'result.json').read_text());assert data['failures']==0;results.append((label,mode,data))
summary={'method':'Clean production Main.tick, no inner timer wrappers, 60 ticks per case; independent isolated AB/BA executions. Entry is actual map; statuses/descendant producer/first shot are controlled boundary fixtures.','inputs':inputs,'cases':[],'all_snapshots_equal':True,'flow':[]}
for idx in range(3):
 cases=[x[2]['cases'][idx] for x in results];assert all(c['frame_sha256']==cases[0]['frame_sha256'] for c in cases)
 for label,mode,data in results[1:]:assert (qa/label/(cases[0]['label']+'.bin')).read_bytes()==(qa/'a0'/(cases[0]['label']+'.bin')).read_bytes()
 row={'case':cases[0]['label'],'actors':cases[0]['actors'],'frames_equal':60,'snapshots_exact':True}
 for mode in ['before','after']:
  values=sorted(v for _,m,d in results if m==mode for v in d['cases'][idx]['samples_us']);row[mode]={'samples':len(values),'mean_us':round(statistics.mean(values),2),'median_us':statistics.median(values),'p95_us':values[math.ceil(.95*len(values))-1],'max_us':max(values)}
 row['mean_change_pct']=round(100*(row['after']['mean_us']/row['before']['mean_us']-1),2);summary['cases'].append(row)
for point in results[0][2]['flow']:
 label=point['label'];original=(qa/'a0'/(label+'.bin')).read_bytes()
 assert all((qa/run/(label+'.bin')).read_bytes()==original for run,_,_ in results)
 summary['flow'].append({'label':label,'all_runs_exact':True,'sha256':hashlib.sha256(original).hexdigest()})
assert all(hashlib.sha256((root/f).read_bytes()).hexdigest()==h for f,h in inputs.items())
(qa/'comparison-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n');print(json.dumps(summary['cases'],indent=2),flush=True)
