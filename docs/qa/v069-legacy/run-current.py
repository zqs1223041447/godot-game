from pathlib import Path
import subprocess,os,json,hashlib,time,gzip,tempfile
R=Path(__file__).resolve().parents[3];Q=Path(__file__).resolve().parent;B=R.parent/'v068-inventory-first-open/docs/qa/v067-legacy';H=Q/'harness.gd'
sha=lambda b:hashlib.sha256(b).hexdigest()
s=H.read_text().replace('version41/42 only','version42/43 only').replace('AMBUSH_LEGACY','PULL_LEGACY');H.write_text(s)
# Reuse the already captured v67 before-side bytes; do not run v67 again.
base=gzip.decompress((B/'current.bin.gz').read_bytes());assert sha(base)=='bc9d401e91c165aafa195f81584f4391ec149b3f5a7aa6587c99b2e100e8f094'
inputs={str(p.relative_to(R)):sha(p.read_bytes()) for p in sorted((R/'scripts').rglob('*.gd'))};(Q/'tested-inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
env=os.environ.copy();x=Path(tempfile.mkdtemp(prefix='godot-m1-v069-legacy-',dir='/tmp'))
for k in ['DATA','CONFIG','CACHE']:
 p=x/k.lower();p.mkdir();env['XDG_'+k+'_HOME']=str(p)
env['PULL_LEGACY_OUTPUT']=str(Q/'current');t=time.monotonic()
with (Q/'current.log.txt').open('wb') as f:p=subprocess.run(['/usr/local/bin/godot','--headless','--path',str(R),'--script',str(H)],env=env,stdout=f,stderr=subprocess.STDOUT,timeout=30)
log=(Q/'current.log.txt').read_text();result={'exit_code':p.returncode,'seconds':time.monotonic()-t,'errors':[s for s in log.splitlines() if 'ERROR' in s],'harness_sha256':sha(H.read_bytes()),'base_manifest':'v068-inventory-first-open/docs/qa/v067-legacy/tested-inputs.json','old_side_reused_not_rerun':True};(Q/'run-result.json').write_text(json.dumps(result,indent=2)+'\n');assert p.returncode==0 and not result['errors'],result
current=(Q/'current.bin').read_bytes();(Q/'current.bin.gz').write_bytes(gzip.compress(current,mtime=0))
saved=(Q/'current.save').read_bytes();before=(B/'current.save').read_bytes();projection=(Q/'current.projected-save.json').read_bytes()
comparison={'observations_equal':base==current,'bytes':len(current),'sha256':sha(current),'save_version_token_only':before.replace(b'"version": 43',b'"version": 44')==saved,'projected_save_equal':projection==(B/'current.projected-save.json').read_bytes(),'before_save_sha256':sha(before),'current_save_sha256':sha(saved),'input_hashes_unchanged':all(sha((R/n).read_bytes())==h for n,h in inputs.items())};(Q/'comparison.json').write_text(json.dumps(comparison,indent=2)+'\n');print(result);print(comparison);assert all(comparison[k] for k in ['observations_equal','save_version_token_only','projected_save_equal','input_hashes_unchanged'])
