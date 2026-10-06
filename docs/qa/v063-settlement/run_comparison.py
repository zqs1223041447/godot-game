from pathlib import Path
import hashlib,json,os,subprocess,tempfile,time,gzip
R=Path(__file__).resolve().parents[3];Q=Path(__file__).resolve().parent;B=R.parent/'v062-final-source-snapshot';H=R/'tools/diagnostics/burn_settlement_profile.gd'
def sha(b):return hashlib.sha256(b).hexdigest()
base=json.loads((B/'docs/qa/v062/final-production-files.json').read_text())['files']
assert all(sha((B/n).read_bytes())==v['sha256'] for n,v in base.items())
changed=[n for n,v in base.items() if sha((R/n).read_bytes())!=v['sha256']];assert changed==['scripts/mechanics/defense_rules.gd'],changed
(Q/'production-inputs.json').write_text(json.dumps({'base_commit':'b93018005413444ad6f988974f4ef3ea09902c5e','base_files':base,'candidate_changed':{n:{'bytes':(R/n).stat().st_size,'sha256':sha((R/n).read_bytes())} for n in changed},'harness_sha256':sha(H.read_bytes()),'source_projection':'none'},indent=2)+'\n')
records=[];data={}
for mode in ['no_burn','ember_deaths']:
 for side,project in [('before',B),('after',R)]:
  label=side+'-'+mode;e=os.environ.copy();x=Path(tempfile.mkdtemp(prefix='godot-m1-v063-'+label+'-',dir='/tmp'))
  for k in ['DATA','CACHE','CONFIG']:
   d=x/k.lower();d.mkdir();e['XDG_'+k+'_HOME']=str(d)
  e.update(DENSITY_PROFILE_OUT=str(Q/(label+'.json')),DENSITY_MODE=mode,DENSITY_INSTRUMENTED='0');e.pop('DENSITY_CAPTURE_INVERSION',None)
  log=Q/(label+'.log.txt');t=time.monotonic();cause=None
  with log.open('w') as f:
   p=subprocess.Popen(['/usr/local/bin/godot','--headless','--path',str(project),'--script',str(H)],cwd=project,env=e,stdout=f,stderr=subprocess.STDOUT)
   while p.poll() is None:
    output=log.read_text()
    if 'ERROR:' in output or time.monotonic()-t>45:
     cause='error log' if 'ERROR:' in output else '45s execution safety limit';p.terminate();break
    time.sleep(.1)
   try:code=p.wait(timeout=2)
   except subprocess.TimeoutExpired:p.kill();code=p.wait()
  output=log.read_text();rec={'label':label,'exit_code':code,'seconds':time.monotonic()-t,'stop_reason':cause,'complete':'LATEST_DENSITY_PROFILE_COMPLETE' in output,'errors':[l for l in output.splitlines() if 'ERROR:' in l],'log_sha256':sha(log.read_bytes())};records.append(rec);(Q/'run-results.json').write_text(json.dumps(records,indent=2)+'\n');print(rec,flush=True)
  if code!=0 or cause or rec['errors'] or not rec['complete']:raise SystemExit(1)
  data[label]=json.loads((Q/(label+'.json')).read_text())['rows'][0]
 comparisons={}
 for m in ['no_burn','ember_deaths']:
  if 'after-'+m not in data:continue
  before=data['before-'+m];after=data['after-'+m];same={}
  for suffix in ['.bin','.save']:
   a=Q/('before-'+m+'-'+m+suffix);b=Q/('after-'+m+'-'+m+suffix);old=a.read_bytes();new=b.read_bytes();assert old==new,(m,suffix)
   same[suffix]={'bytes':len(old),'sha256':sha(old),'exact_equal':True}
  comparisons[m]={'before':before['tick'],'after':after['tick'],'mean_change_fraction':after['tick']['mean_us']/before['tick']['mean_us']-1,'median_change_fraction':after['tick']['p50_us']/before['tick']['p50_us']-1,'p95_change_fraction':after['tick']['p95_us']/before['tick']['p95_us']-1,'peak_change_fraction':after['tick']['max_us']/before['tick']['max_us']-1,'equal':same,'reward_kills':after['reward_kills'],'initial_enemies':after['initial_enemies'],'frames':after['frames']}
 (Q/'comparison.json').write_text(json.dumps(comparisons,indent=2)+'\n');print(json.dumps(comparisons,indent=2),flush=True)
assert all(sha((B/n).read_bytes())==v['sha256'] for n,v in base.items())
proof=json.loads((Q/'production-inputs.json').read_text());assert all(sha((R/n).read_bytes())==v['sha256'] for n,v in proof['candidate_changed'].items()) and sha(H.read_bytes())==proof['harness_sha256']
archives={}
for p in Q.glob('*.bin'):
 b=p.read_bytes();z=p.with_suffix('.bin.gz');z.write_bytes(gzip.compress(b,mtime=0));assert gzip.decompress(z.read_bytes())==b
 archives[p.name]={'bytes':len(b),'sha256':sha(b),'archive':z.name,'archive_sha256':sha(z.read_bytes())}
(Q/'observation-archives.json').write_text(json.dumps(archives,indent=2)+'\n')
