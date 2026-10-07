from pathlib import Path
import json,sys,runpy,hashlib,subprocess,re,time
root=Path(__file__).resolve().parents[3];sys.path.insert(0,str(root/'tools'))
import build_reference as renderer
from verify_jewel_crafting_reference import verify
spans=runpy.run_path(str(root/'docs/qa/v086-reference/merge-fragment.py'))['spans']
ref=root/'docs/reference';qa=Path(__file__).resolve().parent
old=(ref/'catalog.json').read_text();old_html=(ref/'index.html').read_text();old_data=json.loads(old);fragment=json.loads((root/'docs/qa/v091-reference/jewel-crafting-fragment.json').read_text());assert 'jewel_crafting' not in old_data
expected=renderer.merge_jewel_crafting_fragment(old_data,fragment);ranges=spans(old)
key='jewel_crafting';following=min(k for k in ranges if k>key);start=ranges[following][0];addition=json.dumps(key)+': '+json.dumps(fragment[key],ensure_ascii=False,sort_keys=True,indent='\t').replace('\n','\n\t')+',\n\t';new=old[:start]+addition+old[start:];assert json.loads(new)==expected
newranges=spans(new)
for k,(_,a,b) in ranges.items():
 _,x,y=newranges[k];assert old[a:b]==new[x:y],k
art=json.loads((ref/'art/manifest.json').read_text());html=renderer.build(expected,art)
pattern=r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
before={m.group(1):m.group(0) for m in re.finditer(pattern,old_html,re.S)};after={m.group(1):m.group(0) for m in re.finditer(pattern,html,re.S)}
changed={k for k in before if before[k]!=after.get(k)};assert changed=={'jewels-emberheart','jewels-tideglass','jewels-windweave','currencies-calibration_shard'},changed
assert set(after)-set(before)=={'rules-jewel_crafting'}
for k in ['maps-old_garden','maps-broken_ruins','maps-sunwell_terrace','maps-ginkgo_arcade','rules-exploration_maps']:assert before[k]==after[k],k
assets={str(p.relative_to(root)):{'sha':hashlib.sha256(p.read_bytes()).hexdigest(),'mtime_ns':p.stat().st_mtime_ns} for p in ref.rglob('*') if p.is_file() and p.name not in ['catalog.json','index.html'] and p.suffix not in ['.import']}
(ref/'catalog.json').write_text(new);(ref/'index.html').write_text(html)
result=verify();assert all(hashlib.sha256((root/p).read_bytes()).hexdigest()==v['sha'] and (root/p).stat().st_mtime_ns==v['mtime_ns'] for p,v in assets.items())
result.update({'v090_cards_preserved':True,'raw_existing_top_fields':len(ranges),'existing_assets_byte_and_mtime_preserved':len(assets),'catalog_sha256':hashlib.sha256(new.encode()).hexdigest(),'index_sha256':hashlib.sha256(html.encode()).hexdigest()})
(qa/'reference-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False,indent=2))
