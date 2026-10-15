#!/usr/bin/env python3
"""Reconstruct the archived candidate in /tmp without changing production files."""
import hashlib,json,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE='125112823ddf88784e2399c565e974ad04afdc49'
EXPECTED_MAIN_SHA256='98c1f36ce2d09bdf25d285a3e8a0ad6eec76221a8af94a02d1f27c4c85994252'
QA=ROOT/'docs/qa/burn-prediction-cache-20261015'
work=Path(tempfile.mkdtemp(prefix='burn-cache-20261015-reproduce-'))
source=subprocess.check_output(['git','show',BASE+':scripts/main.gd'],cwd=ROOT)
assert hashlib.sha256(source).hexdigest()==EXPECTED_MAIN_SHA256, 'Published baseline main.gd must match the frozen tested source'
(work/'scripts').mkdir(); (work/'scripts/main.gd').write_bytes(source)
subprocess.run(['patch','-p1','-i',str(QA/'candidate.patch')],cwd=work,check=True)
s=(work/'scripts/main.gd').read_text()
(work/'main.candidate.gd').write_text(s)
s+='\nvar cache20261015_counts:Dictionary={"hits":0,"misses":0,"stores":0,"max_entries":0}\n'
s=s.replace('if prediction_rates.has(prediction_key):\n','if prediction_rates.has(prediction_key):\n\t\t\t\tcache20261015_counts.hits+=1\n')
s=s.replace('var rate:Dictionary=Defense.incoming_burn(float(status.raw_dps),fire_resistance','cache20261015_counts.misses+=1\n\t\t\t\tvar rate:Dictionary=Defense.incoming_burn(float(status.raw_dps),fire_resistance')
s=s.replace('prediction_rates[prediction_key]=damage_rate','prediction_rates[prediction_key]=damage_rate\n\t\t\t\t\tcache20261015_counts.stores+=1\n\t\t\t\t\tcache20261015_counts.max_entries=maxi(cache20261015_counts.max_entries,prediction_rates.size())')
(work/'main.instrumented.gd').write_text(s)
print(json.dumps({'baseline_commit':BASE,'baseline_main_sha256':hashlib.sha256(source).hexdigest(),'candidate':str(work/'main.candidate.gd'),'diagnostic':str(work/'main.instrumented.gd')},indent=2))
