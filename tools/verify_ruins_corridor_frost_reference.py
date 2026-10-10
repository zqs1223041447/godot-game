#!/usr/bin/env python3
import hashlib,json,re,subprocess
from build_reference import build
from merge_ruins_corridor_frost_reference import ROOT,QA,merge
BASE='874038562875d5ac39300ed4c16425a102c44b8f'
def original(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT).decode()
text=(ROOT/'docs/reference/catalog.json').read_text();old=original('docs/reference/catalog.json')
fragment=json.loads((QA/'reference-fragment.json').read_text());data=json.loads(text)
assert text==merge(old,fragment)==merge(text,fragment)
assert data['save_version']==61 and data['ruins_corridor_frost']['tiers']==[2,3]
html=(ROOT/'docs/reference/index.html').read_text();old_html=original('docs/reference/index.html')
art=json.loads((ROOT/'docs/reference/art/manifest.json').read_text())
assert html==build(data,art) and old_html==build(json.loads(old),art)
pattern=r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
before={m[1]:m[0] for m in re.finditer(pattern,old_html,re.S)};after={m[1]:m[0] for m in re.finditer(pattern,html,re.S)}
assert set(before)==set(after)
changed={k for k in before if before[k]!=after[k]}
assert changed=={'maps-broken_ruins'},changed
card=after['maps-broken_ruins']
for phrase in ['北侧第二驻点','0.9秒','半径90','25%','不冻结','普通、无机制','已有霜纹守卫','I档和固定测试地图不变']:
    assert phrase in card,phrase
ids=set(re.findall(r'\bid="([^"]+)"',html));links=re.findall(r'href="#([^"]+)"',card)
assert all(link in ids for link in links)
paths=['scripts/monsters/monster_catalog.gd','scripts/monsters/telegraph_profiles.gd','scripts/combat/telegraphed_area_runtime.gd','scripts/main.gd','scripts/world/exploration_map_plan.gd','scripts/world/map_run_state.gd','scripts/save/canonical_build_rules.gd','scripts/canonical_game_state.gd','scripts/world/ginkgo_roster_rules.gd','scripts/world/sunwell_roster_rules.gd','scripts/world/mist_skitter_roster_rules.gd']
for path in paths:assert (ROOT/path).read_text()==original(path),path
record={'baseline':BASE,'changed_cards':sorted(changed),'unchanged_cards':len(before)-1,'total_cards':len(after),'checked_internal_links':len(links),'schema':61,'unchanged_production_paths':paths,'catalog_sha256':hashlib.sha256(text.encode()).hexdigest(),'html_sha256':hashlib.sha256(html.encode()).hexdigest()}
(QA/'reference-verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(record,ensure_ascii=False))
