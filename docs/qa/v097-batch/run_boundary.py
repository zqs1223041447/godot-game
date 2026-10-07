from pathlib import Path
import os,json,subprocess,tempfile,selectors,signal,time,hashlib
ROOT=Path(__file__).resolve().parents[3];QA=Path(__file__).parent
records=[]
pairs=[('boundary_after_fixed',True)] if os.environ.get('V097_ONLY_CANDIDATE')=='1' else [('boundary_before',False),('boundary_after',True)]
manifest=QA/('boundary-correction.json' if os.environ.get('V097_ONLY_CANDIDATE')=='1' else 'boundary-runs.json')
for label, candidate in pairs:
 out=QA/label;log=Path(str(out)+'.log');assert not log.exists()
 tmp=Path(tempfile.mkdtemp(prefix='godot-m1-v097-boundary-'));env=os.environ.copy()
 env.update(XDG_DATA_HOME=str(tmp/'data'),XDG_CACHE_HOME=str(tmp/'cache'),XDG_CONFIG_HOME=str(tmp/'config'),V097_BOUNDARY_OUT=str(out),V097_CANDIDATE=str(int(candidate)))
 cmd=['/usr/local/bin/godot','--headless','--path',str(ROOT),'--script','res://tools/diagnostics/lazy_burn_batch_boundary.gd']
 hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'tools/diagnostics/burn_batch_guard.gd',ROOT/'tools/diagnostics/lazy_burn_batch_main.gd',ROOT/'tools/diagnostics/lazy_burn_batch_boundary.gd']}
 r={'input_hashes':hashes,'label':label,'command':cmd,'candidate':candidate,'start_unix':time.time()};records.append(r)
 manifest.write_text(json.dumps(records,indent=2)+'\n')
 p=subprocess.Popen(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,start_new_session=True);sel=selectors.DefaultSelector();sel.register(p.stdout,selectors.EVENT_READ);start=time.monotonic();buffer=b'';error='';complete=False
 with log.open('wb') as f:
  while sel.get_map():
   if time.monotonic()-start>60:error='60-second watchdog';os.killpg(p.pid,signal.SIGKILL);break
   for key,_ in sel.select(0.1):
    chunk=os.read(key.fileobj.fileno(),65536)
    if not chunk:sel.unregister(key.fileobj);continue
    f.write(chunk);f.flush();buffer+=chunk
    while b'\n' in buffer:
     line,buffer=buffer.split(b'\n',1);text=line.decode(errors='replace');print(text,flush=True)
     if 'ERROR' in text:error=text;os.killpg(p.pid,signal.SIGKILL);break
     complete|='V097_BOUNDARY_COMPLETE' in text
    if error:break
   if error:break
 r.update(exit_code=p.wait(timeout=10),seconds=time.monotonic()-start,error=error,complete=complete)
 manifest.write_text(json.dumps(records,indent=2)+'\n')
 if error or r['exit_code']!=0 or not complete:raise SystemExit(1)
print('BOUNDARY_BOTH_COMPLETE')
