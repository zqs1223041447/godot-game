#!/usr/bin/env python3
"""Compare full serialized observations; produce compact evidence before archiving binaries."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[2]; QA=ROOT/'docs/qa/burn-prediction-cache-20261015'
raw=Path('/tmp/burn-cache-20261015/observations');raw.mkdir(parents=True,exist_ok=True)
def data(name):
 p=QA/name
 return p.read_bytes() if p.exists() else (raw/name).read_bytes()
checks=[];timing={};files={}
for label,mode in [('ember','ember_deaths'),('no-burn','no_burn'),('ignite','ignite')]:
 baseline='baseline-'+label
 names=[baseline,'candidate-'+label,'baseline-repeat-'+label,'candidate-repeat-'+label]
 if label=='ember':names+=['diagnostic-ember']
 for suffix in ['-'+mode+'.bin','-'+mode+'-final.bin','-'+mode+'.save']:
  expected=data(baseline+suffix)
  for name in names:
   content=data(name+suffix);ok=content==expected
   checks.append({'file':name+suffix,'equals':baseline+suffix,'exact':ok});assert ok
   files[name+suffix]={'sha256':hashlib.sha256(content).hexdigest(),'bytes':len(content)}
 timing[mode]={}
 for name in names:
  row=json.loads((QA/(name+'.json')).read_text())['rows'][0]
  timing[mode][name]=row['tick']
summary={'decision':'rejected','reason':'No-burn control means regressed in both bounded pairs; signed-zero key-preservation premise was false. No production optimization retained.','baseline_commit':'4e581e223bf012c04c94ec1f1a558021feeea03a','exact_comparisons':checks,'files':files,'timing':timing,'raw_archive':str(raw)}
(QA/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
for name in files:
 p=QA/name
 if p.exists():shutil.move(str(p),str(raw/name))
print('All',len(checks),'full-byte comparisons passed; raw artifacts preserved in',raw)
