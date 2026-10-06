#!/usr/bin/env python3
"""Bounded v78 new-fragment export and focused checks. Uses the shared import."""
import argparse,hashlib,json,os,selectors,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]; QA=Path(__file__).resolve().parent
ERRORS=('SCRIPT ERROR','ERROR:','Assertion','Traceback','Parse Error')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(name,value):
 with (QA/name).open('x') as f:json.dump(value,f,ensure_ascii=False,indent=2);f.write('\n')
def run(label,command,env=None):
 inputs=[ROOT/'project.godot',ROOT/'tools/export_reference.gd',ROOT/'tools/build_reference.py']+list((ROOT/'scripts').rglob('*.gd'))+list((ROOT/'data').rglob('*.json'))+list((ROOT/'docs/qa/v078-gameplay/fixtures').glob('*.json'))
 before={str(p.relative_to(ROOT)):sha(p) for p in sorted(inputs)};save(label+'-input-sha256.json',before)
 retained=list((ROOT/'docs/reference').rglob('*.png'));old={str(p):(sha(p),p.stat().st_mtime_ns) for p in retained}
 started=time.monotonic();output={'stdout':[],'stderr':[]};stopped=None
 process=subprocess.Popen(command,cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
 selector=selectors.DefaultSelector()
 for name in output:selector.register(getattr(process,name),selectors.EVENT_READ,name)
 while selector.get_map():
  if time.monotonic()-started>120 and process.poll() is None:stopped='timeout';process.kill()
  for key,_ in selector.select(.1):
   line=key.fileobj.readline()
   if not line:selector.unregister(key.fileobj);continue
   output[key.data].append(line)
   if any(e in line for e in ERRORS) and process.poll() is None and command[0].endswith('godot'):stopped='first_error';process.terminate()
 code=process.wait();selector.close()
 for name,lines in output.items():
  with (QA/(label+'.'+name+'.log.txt')).open('x') as f:f.writelines(lines)
 changed=[str(p.relative_to(ROOT)) for p in inputs if before[str(p.relative_to(ROOT))]!=sha(p)]
 touched=[str(p.relative_to(ROOT)) for p in retained if old[str(p)]!=(sha(p),p.stat().st_mtime_ns)]
 result={'command':command,'exit_code':code,'seconds':round(time.monotonic()-started,3),'stopped_on':stopped,'error_lines':[x.strip() for lines in output.values() for x in lines if any(e in x for e in ERRORS)],'source_changed_during_run':changed,'reference_pngs_unchanged_in_bytes_and_mtime':not touched,'unexpected_preserved_file_writes':touched}
 save(label+'-result.json',result);print(json.dumps(result,ensure_ascii=False),flush=True)
 if code or stopped or result['error_lines'] or changed or touched:raise SystemExit(1)
def main():
 p=argparse.ArgumentParser();p.add_argument('stage',choices=['export','merge','build','verify']);p.add_argument('--prefix',default='');a=p.parse_args()
 if a.stage=='export':
  d=tempfile.mkdtemp(prefix='godot-v078-reference-');env=dict(os.environ,XDG_DATA_HOME=d+'/data',XDG_CONFIG_HOME=d+'/config',XDG_CACHE_HOME=d+'/cache',GODOT_SILENCE_ROOT_WARNING='1')
  run(a.prefix+'elemental-fragment',['/usr/local/bin/godot','--headless','--path',str(ROOT),'--script','res://tools/export_reference.gd','--','res://docs/qa/v078-reference/elemental-fragment.json','--elemental-conversion-fragment'],env)
 elif a.stage=='merge':run(a.prefix+'merge',['python3','docs/qa/v078-reference/merge-fragment.py'])
 elif a.stage=='build':
  run(a.prefix+'build',['python3','tools/build_reference.py']);run(a.prefix+'build-check',['python3','tools/build_reference.py','--check'])
 else:run(a.prefix+'focused-reference',['python3','docs/qa/v078-reference/check-reference.py'])
if __name__=='__main__':main()
