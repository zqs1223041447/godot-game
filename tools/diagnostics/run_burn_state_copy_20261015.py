#!/usr/bin/env python3
"""Run predeclared counterbalanced cases sequentially, preserving all observations."""
import os,sys,json,subprocess,tempfile,time,hashlib,io,tarfile
from pathlib import Path
root=Path(__file__).resolve().parents[2];frozen=root/'docs/qa/burn-state-copy-20261015/frozen'
qa=Path(os.environ.get('STATE20261015_EVIDENCE_DIR',str(root/'docs/qa/burn-state-copy-20261015')));qa.mkdir(parents=True,exist_ok=True)
BASELINE='461824776e500ea868f72aea58a4f54db40b4423'
manifest=json.loads((frozen.parent/'baseline-source-manifest.json').read_text())
archive=tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['git','archive',BASELINE,'scripts'],cwd=root)))
for path,expected in manifest.items():
 source=archive.extractfile(path).read()
 assert hashlib.sha256(source).hexdigest()==expected, f'Published dependency mismatch: {path}'
 candidate=source
 if path=='scripts/combat/burn_runtime.gd':
  candidate=source.replace(b'var next: Dictionary = state.duplicate(true)',b'# Private provenance is scalar-only and never mutated here. Keep public copies detached.\n\t# Sharing is safe only while no private planner consumer mutates provenance.\n\tvar next: Dictionary = state.duplicate(false)')
 assert (root/path).read_bytes()==candidate, f'Unexpected production change: {path}'
for name in ['burn_runtime.gd','burn_rules.gd']:
 source=archive.extractfile('scripts/combat/'+name).read().decode()
 source=source.replace('class_name BurnRuntime\n','').replace('class_name BurnRules\n','').replace('res://scripts/combat/burn_rules.gd','res://docs/qa/burn-state-copy-20261015/frozen/burn_rules.gd')
 assert (frozen/name).read_text()==source, f'Frozen source mismatch: {name}'
archive.close()
def hashes():
 paths=list((root/'scripts').rglob('*.gd'))+list(frozen.glob('*.gd'))+[root/'tools/diagnostics/burn_state_copy_20261015.gd']
 return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}
for mode in ['ember_deaths','no_burn','ignite']:
 for pair,variant in [(1,'baseline'),(1,'candidate'),(2,'candidate'),(2,'baseline')]:
  label=f'{mode}-pair{pair}-{variant}';out=qa/(label+'.json');log=qa/(label+'.log');record_path=qa/(label+'-run.json')
  assert not any(p.exists() for p in [out,log,record_path]),'Never overwrite evidence'
  tmp=Path(tempfile.mkdtemp(prefix='godot-state-20261015-'));env=os.environ.copy()
  env.update(XDG_DATA_HOME=str(tmp/'data'),XDG_CACHE_HOME=str(tmp/'cache'),XDG_CONFIG_HOME=str(tmp/'config'),STATE20261015_PROFILE_OUT=str(out),STATE20261015_MODE=mode,STATE20261015_VARIANT=variant)
  cmd=['godot','--headless','--path',str(root),'--script','res://tools/diagnostics/burn_state_copy_20261015.gd']
  record={'command':cmd,'environment':{k:v for k,v in env.items() if k.startswith(('XDG_','STATE20261015'))},'hashes_before':hashes()};record_path.write_text(json.dumps(record,indent=2)+'\n');start=time.time()
  try:
   p=subprocess.run(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90);log.write_bytes(p.stdout)
   record.update(exit_code=p.returncode,elapsed_seconds=time.time()-start,hashes_after=hashes());record_path.write_text(json.dumps(record,indent=2)+'\n')
   assert record['hashes_before']==record['hashes_after'],'Sources changed during run'
   assert p.returncode==0 and b'ERROR' not in p.stdout and b'BURN_PROFILE_AUDIT_COMPLETE' in p.stdout,p.stdout.decode()[-3000:]
   print(label,json.loads(out.read_text())['rows'][0]['tick'],flush=True)
  except subprocess.TimeoutExpired as e:
   log.write_bytes(e.stdout or b'');record.update(timeout=True,elapsed_seconds=time.time()-start,hashes_after=hashes());record_path.write_text(json.dumps(record,indent=2)+'\n');raise
