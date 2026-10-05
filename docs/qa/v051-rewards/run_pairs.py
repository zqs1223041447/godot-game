from pathlib import Path
import os,subprocess,tempfile,json,time,sys
r=Path('/workspace/scratch/a51485f153de/v051-reward-inventory-cost');out=r/'docs/qa/v051-rewards';phase=sys.argv[1];rows=[]
for case,repeat in [('plain',0),('plain',1),('plain',2),('failed_save',0),('full_bag',0)]:
 label=f'{phase}-{case}-{repeat}';env=os.environ.copy();tmp=Path(tempfile.mkdtemp(prefix=f'godot-m1-v051-{label}-'));env.update({f'XDG_{k}_HOME':str(tmp/k.lower()) for k in ['DATA','CONFIG','CACHE']});env.update(V051_REWARD_OUT=str(out/label),V051_CASE=case,V051_SOURCE='7b1642d' if phase=='before' else 'v051-allocation-guard')
 if phase!='before':env['V051_MATCH_INITIAL_RNG_FROM']=str(out/f'before-{case}-{repeat}.bin')
 t=time.monotonic();p=subprocess.run(['/usr/local/bin/godot','--headless','--path',str(r),'--script','tools/diagnostics/reward_settlement_v51.gd'],env=env,capture_output=True,text=True,timeout=40);log=p.stdout+p.stderr;(out/(label+'.log')).write_text(log)
 row={'label':label,'exit_code':p.returncode,'seconds':time.monotonic()-t,'errors':[s for s in log.splitlines() if 'ERROR' in s]};rows.append(row);(out/(phase+'-runner.json')).write_text(json.dumps(rows,indent=2)+'\n');print(row,flush=True)
 if p.returncode or row['errors']:print(log);raise SystemExit(1)
 print(json.loads((out/(label+'.json')).read_text()),flush=True)
