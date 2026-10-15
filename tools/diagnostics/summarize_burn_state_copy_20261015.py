#!/usr/bin/env python3
"""Evaluate the predeclared gate on complete bytes, never rounded projections."""
from pathlib import Path
import hashlib,json,shutil,os
root=Path(__file__).resolve().parents[2];qa=Path(os.environ.get('STATE20261015_EVIDENCE_DIR',str(root/'docs/qa/burn-state-copy-20261015')));archive=Path(os.environ.get('STATE20261015_ARCHIVE_DIR','/tmp/burn-state-copy-20261015-observations'))
checks=[];paired_checks=[];files={};timing={};decisions={}
def data(name):
 p=qa/name
 return p.read_bytes() if p.exists() else (archive/name).read_bytes()
for mode in ['ember_deaths','no_burn','ignite']:
 timing[mode]={};names=[f'{mode}-pair{p}-{v}' for p,v in [(1,'baseline'),(1,'candidate'),(2,'candidate'),(2,'baseline')]]
 for suffix in [f'-{mode}.bin',f'-{mode}-final.bin',f'-{mode}.save']:
  expected=data(names[0]+suffix)
  for name in names:
   content=data(name+suffix);ok=content==expected
   checks.append({'file':name+suffix,'equals':names[0]+suffix,'exact':ok});assert ok
   files[name+suffix]={'sha256':hashlib.sha256(content).hexdigest(),'bytes':len(content)}
 for pair in [1,2]:
  for suffix in [f'-{mode}.bin',f'-{mode}-final.bin',f'-{mode}.save']:
   baseline=f'{mode}-pair{pair}-baseline'+suffix;candidate=f'{mode}-pair{pair}-candidate'+suffix
   ok=data(baseline)==data(candidate);assert ok
   paired_checks.append({'baseline':baseline,'candidate':candidate,'exact':ok})
 for name in names:timing[mode][name]=json.loads((qa/(name+'.json')).read_text())['rows'][0]['tick']
 ratios={}
 for field in ['mean_us','max_us']:
  bs=[timing[mode][f'{mode}-pair{p}-baseline'][field] for p in [1,2]];cs=[timing[mode][f'{mode}-pair{p}-candidate'][field] for p in [1,2]]
  ratios[field]={'pair_ratios':[c/b for c,b in zip(cs,bs)],'pooled_ratio':sum(cs)/sum(bs)}
 decisions[mode]=ratios
ember=all(all(r<1 for r in d['pair_ratios']) and d['pooled_ratio']<=0.97 for d in decisions['ember_deaths'].values())
controls=all(not(all(r>1.03 for r in d['pair_ratios']) or d['pooled_ratio']>1.05) for m in ['no_burn','ignite'] for d in decisions[m].values())
summary={'timing_gate_pass':ember and controls,'ember_gate_pass':ember,'control_gate_pass':controls,'baseline_commit':'461824776e500ea868f72aea58a4f54db40b4423','exact_comparisons':checks,'direct_paired_comparisons':paired_checks,'comparison_counts':{'artifact_receipts':36,'baseline_self_checks':9,'nonself_against_pair1_baseline':27,'direct_paired_candidate_vs_baseline':18},'files':files,'timing':timing,'ratios':decisions,'raw_archive':str(archive)}
(qa/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({'timing_gate_pass':ember and controls,'ratios':decisions},indent=2))
archive.mkdir(exist_ok=True)
for name in files:
 p=qa/name
 if p.exists():assert not (archive/name).exists();shutil.move(str(p),str(archive/name))
