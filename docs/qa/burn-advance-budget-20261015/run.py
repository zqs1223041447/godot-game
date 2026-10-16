import os,tempfile,subprocess,json,time
from pathlib import Path
d=Path('/tmp/burn-advance-budget-20261015')
for variant in ['clean','instrumented']:
 x=Path(tempfile.mkdtemp(prefix='godot-cache-20261015-'));env=os.environ.copy()
 for key,folder in [('DATA','data'),('CONFIG','config'),('CACHE','cache'),('STATE','state'),('RUNTIME','runtime')]:
  p=x/folder;p.mkdir(mode=0o700);env['XDG_'+key+'_HOME' if key!='RUNTIME' else 'XDG_RUNTIME_DIR']=str(p)
 env.update(CACHE20261015_MODE='ember_deaths',CACHE20261015_PROFILE_OUT=str(d/(variant+'.json')),CACHE20261015_DIAGNOSTIC='1' if variant=='instrumented' else '0',CACHE20261015_MAIN=str(d/'main.gd') if variant=='instrumented' else '')
 cmd=['timeout','90','godot','--headless','--path',str(d/'repo'),'--script',str(d/'harness.gd')]
 with open(d/(variant+'.log'),'w') as f:p=subprocess.run(cmd,env=env,stdout=f,stderr=subprocess.STDOUT)
 print(variant,p.returncode,flush=True)
 if p.returncode:break
