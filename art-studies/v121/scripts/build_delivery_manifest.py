#!/usr/bin/env python3
"""Write local manifests only. Does not archive, upload, commit, or publish."""
from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parents[1]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
# Deliberately omit source asset folders, packed blend, backup blends and logs.
public=[]
for p in sorted(R.rglob('*')):
 if not p.is_file():continue
 q=p.relative_to(R)
 if q.name.startswith(('SHA256SUMS','DELIVERY-MANIFEST','PUBLIC-BACKUP-FILES')):continue
 if q.parts[0]=='work_sources' or q.parts[0]=='logs' or p.suffix in ['.blend','.blend1']:continue
 if q.parts[0] in ['scripts','reports','renders','licenses'] or len(q.parts)==1 and p.suffix=='.md':public.append(q.as_posix())
local=[p.relative_to(R).as_posix() for p in sorted(R.rglob('*')) if p.is_file() and (p.relative_to(R).parts[0]=='work_sources' or p.suffix in ['.blend','.blend1'])]
M=json.loads((R/'reports/source-manifest.json').read_text())
inputs=[]
for key,val in M['archives'].items():
 inputs.append({'kind':'original_character_archive','name':val['filename'],'bytes':val['bytes'],'sha256':val['sha256'],'required_for':'Recreating work_sources from public candidate scripts; no package bytes included in public candidates.','official_url':'https://quaternius.itch.io/'+('modular-character-outfits-fantasy' if key=='fantasy' else 'universal-base-characters')})
inputs.append({'kind':'existing_project_background','path':'godot-game/art-studies/v118/qa/sparse-assembly.png','sha256':'95a571895b67878e0a7084dbd0ae08046a1245910ffda059e68e7686895af4fe','required_for':'Actual-scale technical composite only; existing project file remains read-only and is not duplicated.'})
inputs.append({'kind':'environment_provenance_only','path':'godot-game/art-studies/v111/source/modules.blend','sha256':'2f6ffcd31cf04d2e347be087f111ead2e71968d2aab61a4a36cc1943a8fbb424','required_for':'Not needed to rerender when the captured reports/environment-settings.json is retained; provenance only.'})
manifest={'status':'Local manifest only. No publication, upload, archive creation or repository push performed.','public_backup_candidates':public,'public_candidate_notes':['Self-authored scripts, technical reports, rendered result images, documentation, and source/license evidence.','Candidate inclusion is not an independent rights clearance or authorization to publish. Root task coordinates publication.','No original ZIP, raw model, working-source texture package, or packed blend is a public candidate.'],'external_inputs':inputs,'local_only':local,'local_only_note':'Final packed blend, prior local snapshots and extracted model/texture working copies are excluded from public backup candidates.'}
(R/'DELIVERY-MANIFEST.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False))
(R/'PUBLIC-BACKUP-FILES.txt').write_text('\n'.join(public+['DELIVERY-MANIFEST.json','PUBLIC-BACKUP-FILES.txt','SHA256SUMS.txt'])+'\n')
public_hash_files=public+['DELIVERY-MANIFEST.json','PUBLIC-BACKUP-FILES.txt']
(R/'SHA256SUMS.txt').write_text(''.join(f'{digest(R/q)}  {q}\n' for q in sorted(public_hash_files)))
(R/'SHA256SUMS-local-only.txt').write_text(''.join(f'{digest(R/q)}  {q}\n' for q in local))
print(json.dumps({'public_candidate_files':len(public),'local_only_files':len(local),'public_bytes':sum((R/q).stat().st_size for q in public),'local_only_bytes':sum((R/q).stat().st_size for q in local),'published':False},indent=2))
