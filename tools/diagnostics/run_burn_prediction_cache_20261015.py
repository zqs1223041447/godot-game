#!/usr/bin/env python3
"""Run one clean isolated 20-tick case; never overwrite existing evidence."""
import os,sys,json,subprocess,tempfile,time,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[2]
label,mode=sys.argv[1:]
qa=root/'docs/qa/burn-prediction-cache-20261015'; out=qa/(label+'.json'); log=qa/(label+'.log')
assert not out.exists() and not log.exists()
env=os.environ.copy(); tmp=Path(tempfile.mkdtemp(prefix='godot-cache-20261015-'))
env.update(XDG_DATA_HOME=str(tmp/'data'),XDG_CACHE_HOME=str(tmp/'cache'),XDG_CONFIG_HOME=str(tmp/'config'),CACHE20261015_PROFILE_OUT=str(out),CACHE20261015_MODE=mode)
cmd=['godot','--headless','--path',str(root),'--script','res://tools/diagnostics/burn_prediction_cache_20261015.gd']
start=time.time()
try:
 p=subprocess.run(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
 log.write_bytes(p.stdout)
 record={'command':cmd,'environment':{k:v for k,v in env.items() if k.startswith(('XDG_','CACHE20261015'))},'exit_code':p.returncode,'elapsed_seconds':time.time()-start,'main_sha256':hashlib.sha256((root/'scripts/main.gd').read_bytes()).hexdigest(),'harness_sha256':hashlib.sha256((root/'tools/diagnostics/burn_prediction_cache_20261015.gd').read_bytes()).hexdigest()}
 (qa/(label+'-run.json')).write_text(json.dumps(record,indent=2)+'\n')
 print(p.stdout.decode()[-5000:]); assert p.returncode==0 and b'ERROR' not in p.stdout and b'BURN_PROFILE_AUDIT_COMPLETE' in p.stdout
except subprocess.TimeoutExpired as e:
 log.write_bytes(e.stdout or b'');raise
