from pathlib import Path
import os,subprocess,tempfile,json,time,sys
r=Path('/workspace/scratch/a51485f153de/v051-reward-inventory-cost');out=r/'docs/qa/v051-inventory';phase=sys.argv[1];rows=[]
for repeat in range(3):
 label=f'actual-{phase}-{repeat}';env=os.environ.copy();tmp=Path(tempfile.mkdtemp(prefix=f'godot-m1-v051-{label}-'));env.update({f'XDG_{k}_HOME':str(tmp/k.lower()) for k in ['DATA','CONFIG','CACHE']});env.update(INVENTORY_PROFILE_OUT=str(out/(label+'.json')),INVENTORY_PROFILE_SOURCE='7b1642d' if phase=='before' else 'v051-projection-reuse')
 t=time.monotonic();p=subprocess.run(['/usr/local/bin/godot','--headless','--path',str(r),'--script','tools/diagnostics/inventory_projection_v51.gd'],env=env,capture_output=True,text=True,timeout=40);log=p.stdout+p.stderr;(out/(label+'.log')).write_text(log)
 row={'label':label,'exit_code':p.returncode,'seconds':time.monotonic()-t,'errors':[s for s in log.splitlines() if 'ERROR' in s]};rows.append(row);(out/(phase+'-actual-runner.json')).write_text(json.dumps(rows,indent=2)+'\n');print(row,flush=True)
 if p.returncode or row['errors']:print(log);raise SystemExit(1)
 d=json.loads((out/(label+'.json')).read_text());print({v['phase']:v['synchronous_us'] for v in d['phases'] if v['phase'] in ['first_I_open','twenty_normal_root_deaths_bag_closed','confirm_one_visible_targeted_craft']},flush=True)
