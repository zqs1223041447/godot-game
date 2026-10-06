from pathlib import Path
import hashlib,json,subprocess,os,tempfile,time,gzip
Q=Path(__file__).resolve().parent;P=Q.parent;H=Q/'production-pair-probe.gd';sha=lambda b:hashlib.sha256(b).hexdigest();runs=[]
for label,root in [('before',P/'v067-inward-pull'),('after',P/'v068-inventory-first-open')]:
 x=Path(tempfile.mkdtemp(prefix='godot-m1-v068-pair-'+label+'-',dir='/tmp'));env=os.environ.copy()
 for k in ['DATA','CONFIG','CACHE']:
  d=x/k.lower();d.mkdir();env['XDG_'+k+'_HOME']=str(d)
 env.update(FIRST_I_OUTPUT=str(Q/label),FIRST_I_SOURCE='bcecff233e0e37082c590c662af6e6f67b01b47b'+(' + root static Grid preload' if label=='after' else ''))
 inputs={str(f.relative_to(root)):sha(f.read_bytes()) for f in sorted((root/'scripts').rglob('*.gd'))};(Q/(label+'-input-sha256.json')).write_text(json.dumps(inputs,indent=2)+'\n')
 t=time.monotonic()
 with (Q/(label+'.log.txt')).open('wb') as f:r=subprocess.run(['/usr/local/bin/godot','--headless','--path',str(root),'--script',str(H)],stdout=f,stderr=subprocess.STDOUT,env=env,timeout=35)
 text=(Q/(label+'.log.txt')).read_text();row={'label':label,'exit_code':r.returncode,'seconds':time.monotonic()-t,'errors':[s for s in text.splitlines() if 'ERROR' in s],'inputs_unchanged':all(sha((root/n).read_bytes())==h for n,h in inputs.items()),'harness_sha256':sha(H.read_bytes())};runs.append(row);(Q/'pair-runs.json').write_text(json.dumps(runs,indent=2)+'\n');print(row,flush=True)
 if r.returncode or row['errors']:print(text[-5000:],flush=True);raise SystemExit(1)
 raw=(Q/(label+'.bin')).read_bytes();(Q/(label+'.bin.gz')).write_bytes(gzip.compress(raw,mtime=0));d=json.loads((Q/(label+'.json')).read_text());print({'setup':d['setup'],'phases':[{k:v for k,v in x.items() if k in ['phase','us']} for x in d['phases']]},flush=True)
a=(Q/'before.bin').read_bytes();b=(Q/'after.bin').read_bytes();comparison={'exact_observation_equal':a==b,'before_sha256':sha(a),'after_sha256':sha(b),'bytes':len(a),'same_harness_all_runs':True};(Q/'pair-comparison.json').write_text(json.dumps(comparison,indent=2)+'\n');print(comparison,flush=True);assert a==b
