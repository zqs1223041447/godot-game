from pathlib import Path
import tempfile,os,time,subprocess,json,hashlib,sys
root=Path(__file__).resolve().parents[3]; q=Path(__file__).resolve().parent
mode=sys.argv[1]; attempt=sys.argv[2] if len(sys.argv)>2 else '01'
def run(label,script,extra={}):
 tmp=Path(tempfile.mkdtemp(prefix='godot-m1-v052-'+label+'-',dir='/tmp'));env=dict(os.environ,**extra)
 for key in ['DATA','CACHE','CONFIG']:
  path=tmp/key.lower();path.mkdir();env['XDG_'+key+'_HOME']=str(path)
 inputs={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.joinpath('scripts').rglob('*.gd')}
 inputs[script]=hashlib.sha256(root.joinpath(script).read_bytes()).hexdigest()
 t=time.monotonic();r=subprocess.run(['/usr/local/bin/godot','--headless','--path',str(root),'--script','res://'+script],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=60)
 (q/(label+'.log')).write_text(r.stdout);errors=[line for line in r.stdout.splitlines() if 'ERROR:' in line or 'Parse Error:' in line]
 out={'exit_code':r.returncode,'seconds':time.monotonic()-t,'errors':errors,'inputs':inputs,'inputs_unchanged':all(hashlib.sha256(root.joinpath(p).read_bytes()).hexdigest()==h for p,h in inputs.items())}
 (q/(label+'.json')).write_text(json.dumps(out,indent=2)+'\n');print(label,r.returncode,errors);print(r.stdout[-2200:]);return r.returncode==0 and not errors
if mode=='boundaries':
 sys.exit(0 if run('boundaries-'+attempt,'tests/shock_settlement_boundaries_test.gd') else 1)
if mode=='legacy':
 for variant in ['original','integrated']:
  output=q/('legacy-'+variant+'-'+attempt)
  if not run('legacy-'+variant+'-run-'+attempt,'tests/shock_legacy_equivalence_probe.gd',{'SHOCK_LEGACY_OLD':'1' if variant=='original' else '0','SHOCK_LEGACY_OUTPUT':str(output)}):sys.exit(1)
 results={}
 for suffix in ['.bin','.save','.json']:
  old=(q/('legacy-original-'+attempt+suffix)).read_bytes();new=(q/('legacy-integrated-'+attempt+suffix)).read_bytes()
  results[suffix]={'equal':old==new,'bytes':len(old),'sha256':hashlib.sha256(old).hexdigest()}
 (q/('legacy-comparison-'+attempt+'.json')).write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results));sys.exit(0 if all(x['equal'] for x in results.values()) else 1)
