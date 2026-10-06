from pathlib import Path
import subprocess, os, json, hashlib, time, gzip
ROOT=Path(__file__).resolve().parents[3]; QA=Path(__file__).resolve().parent
BASE=ROOT.parent/'v063-final-source-snapshot'; HARNESS=QA/'harness.gd'
sha=lambda b:hashlib.sha256(b).hexdigest()
records=[]
for label,project in [('before',BASE),('after',ROOT)]:
    env=os.environ.copy()
    for k,s in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
        p=Path('/tmp/godot-m1-v064-legacy-'+label)/s;p.mkdir(parents=True,exist_ok=True);env[k]=str(p)
    env['IRON_REFLEXES_LEGACY_OUTPUT']=str(QA/label)
    cmd=['/usr/local/bin/godot','--headless','--path',str(project),'--script',str(HARNESS)]
    inputs={str(p.relative_to(project)):sha(p.read_bytes()) for p in sorted((project/'scripts').rglob('*.gd'))}
    (QA/(label+'-inputs.json')).write_text(json.dumps(inputs,indent=2)+'\n')
    start=time.monotonic()
    with (QA/(label+'.log.txt')).open('wb') as f:
        result=subprocess.run(cmd,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=45)
    log=(QA/(label+'.log.txt')).read_text(); record={'label':label,'command':cmd,'exit_code':result.returncode,'elapsed_seconds':time.monotonic()-start,'harness_sha256':sha(HARNESS.read_bytes()),'script_error':any(x in log for x in ['SCRIPT ERROR','ERROR:','Parse Error'])};records.append(record)
    (QA/'run-results.json').write_text(json.dumps(records,indent=2)+'\n');print(json.dumps(record),flush=True)
    if result.returncode or record['script_error']:raise SystemExit(1)
comparison={}
for ext in ['bin','save','projected-save.json']:
    a=(QA/('before.'+ext)).read_bytes();b=(QA/('after.'+ext)).read_bytes()
    comparison[ext]={'same':a==b,'before_bytes':len(a),'after_bytes':len(b),'before_sha256':sha(a),'after_sha256':sha(b)}
a=(QA/'before.save').read_bytes();b=(QA/'after.save').read_bytes()
comparison['raw_version_token_only']=a.replace(b'"version": 39',b'"version": 40')==b
comparison['projection']='Only serialized build version39 ->40; no stats/combat/resources/RNG projection'
for label in ['before','after']:
    raw=(QA/(label+'.bin')).read_bytes();data=gzip.compress(raw,mtime=0);(QA/(label+'.bin.gz')).write_bytes(data);assert gzip.decompress(data)==raw
(QA/'comparison.json').write_text(json.dumps(comparison,indent=2)+'\n');print(json.dumps(comparison),flush=True)
assert comparison['bin']['same'] and comparison['projected-save.json']['same'] and comparison['raw_version_token_only']
