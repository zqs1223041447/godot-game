from pathlib import Path
import hashlib,json,os,subprocess,time,tempfile
R=Path(__file__).resolve().parents[3];Q=Path(__file__).resolve().parent
records=[]
for mode in ['no_burn','ember_deaths']:
 e=os.environ.copy();xdg=Path(tempfile.mkdtemp(prefix='godot-m1-v063-'+mode+'-',dir='/tmp'))
 for k in ['DATA','CACHE','CONFIG']:
  p=xdg/k.lower();p.mkdir();e['XDG_'+k+'_HOME']=str(p)
 e.update(DENSITY_PROFILE_OUT=str(Q/(mode+'.json')),DENSITY_MODE=mode,DENSITY_INSTRUMENTED='1');e.pop('DENSITY_CAPTURE_INVERSION',None)
 log=Q/(mode+'.log.txt');start=time.monotonic();cause=None
 with log.open('w') as f:
  p=subprocess.Popen(['/usr/local/bin/godot','--headless','--path',str(R),'--script','tools/diagnostics/feedback_cost_profile.gd'],cwd=R,env=e,stdout=f,stderr=subprocess.STDOUT)
  while p.poll() is None:
   text=log.read_text()
   if 'ERROR:' in text or 'SCRIPT ERROR:' in text or time.monotonic()-start>45:
    cause='error log' if 'ERROR:' in text else '45s execution safety limit';p.terminate();break
   time.sleep(.1)
  try:code=p.wait(timeout=2)
  except subprocess.TimeoutExpired:p.kill();code=p.wait()
 text=log.read_text();record={'mode':mode,'exit_code':code,'seconds':time.monotonic()-start,'stop_reason':cause,'complete':'LATEST_DENSITY_PROFILE_COMPLETE' in text,'errors':[l for l in text.splitlines() if 'ERROR:' in l],'log_sha256':hashlib.sha256(log.read_bytes()).hexdigest(),'harness_sha256':hashlib.sha256((R/'tools/diagnostics/feedback_cost_profile.gd').read_bytes()).hexdigest()};records.append(record);(Q/'profile-results.json').write_text(json.dumps(records,indent=2)+'\n');print(record,flush=True)
 if code!=0 or cause or record['errors'] or not record['complete']:raise SystemExit(1)
