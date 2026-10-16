from pathlib import Path
import json,hashlib,re
p=Path('/tmp/burn-advance-budget-20261015');r=Path('/workspace/scratch/a51485f153de/godot-game')
h=lambda b:hashlib.sha256(b).hexdigest()
m=json.load(open(p/'frozen-manifest.json'))
checks={}
for base in [r,p/'repo']:
 checks[str(base)]=all(h((base/f).read_bytes())==v for f,v in m['files'].items())
checks['instrumentation_unchanged']=all(h((p/f).read_bytes())==v for f,v in json.load(open(p/'instrumentation-manifest.json')).items())
receipts=[]
for suf in ['.bin','-final.bin','.save']:
 a=(p/('clean-ember_deaths'+suf)).read_bytes();b=(p/('instrumented-ember_deaths'+suf)).read_bytes()
 receipts.append({'artifact':suf,'equal':a==b,'bytes':len(a),'sha256':h(a),'instrumented_sha256':h(b)})
clean=json.load(open(p/'clean.json'))['rows'][0];inst=json.load(open(p/'instrumented.json'))['rows'][0]
checks['all_20_frames_equal']=all(a['observation_sha256']==b['observation_sha256'] for a,b in zip(clean['samples'],inst['samples'])) and len(clean['samples'])==len(inst['samples'])==20
frames=[];prior={'inclusive_us':0,'bookkeeping_us':0,'phase_us':{},'phase_calls':{}}
for line in (p/'instrumented.log').read_text().splitlines():
 if line.startswith('ADVANCE_DIAGNOSTIC '):
  _,frame,s=line.split(' ',2);cur=json.loads(s)
  delta={k:cur[k]-prior[k] for k in ['inclusive_us','bookkeeping_us']}
  for k in ['phase_us','phase_calls']:delta[k]={x:v-prior[k].get(x,0) for x,v in cur[k].items()}
  delta['frame']=int(frame);delta['unattributed_us']=delta['inclusive_us']-delta['bookkeeping_us']-sum(delta['phase_us'].values());frames.append(delta);prior=cur
phase=inst['extra_counts'];total=phase['inclusive_us'];total_tick=sum(s['cpu_us'] for s in inst['samples'])
summary={'checks':checks,'artifacts':receipts,'clean_tick':clean['tick'],'instrumented_tick':inst['tick'],'totals':phase,'unattributed_us':total-phase['bookkeeping_us']-sum(phase['phase_us'].values()),'phase_pct_of_inclusive':{k:v/total*100 for k,v in phase['phase_us'].items()},'inclusive_pct_tick':total/total_tick*100,'peak_instrumented':frames[max(range(20),key=lambda i:inst['samples'][i]['cpu_us'])],'frame_deltas':frames}
json.dump(summary,open(p/'verification.json','w'),indent=2)
assert all(checks.values()) and all(x['equal'] for x in receipts)
for n in ['clean','instrumented']:
 log=(p/(n+'.log')).read_text();assert 'CACHE20261015_BURN_PROFILE_AUDIT_COMPLETE' in log; assert not re.search(r'SCRIPT ERROR|Parse Error|ERROR:',log)
print(json.dumps({k:v for k,v in summary.items() if k!='frame_deltas'},indent=2))
