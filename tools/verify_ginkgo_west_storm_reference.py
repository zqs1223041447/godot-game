#!/usr/bin/env python3
import hashlib,json,re,subprocess
from build_reference import build
from merge_ginkgo_west_storm_reference import ROOT,QA,merge
BASE='8ed6961ccc8a87793cbd1ae76c9afe8ae4d9b95a'
def original(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT).decode()
text=(ROOT/'docs/reference/catalog.json').read_text();old=original('docs/reference/catalog.json')
fragment=json.loads((QA/'reference-fragment.json').read_text());data=json.loads(text)
assert text==merge(old,fragment)==merge(text,fragment)
assert data['save_version']==61 and data['ginkgo_west_storm']['tiers']==[2,3]
html=(ROOT/'docs/reference/index.html').read_text();old_html=original('docs/reference/index.html')
art=json.loads((ROOT/'docs/reference/art/manifest.json').read_text())
assert html==build(data,art) and old_html==build(json.loads(old),art)
pattern=r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
before={m[1]:m[0] for m in re.finditer(pattern,old_html,re.S)};after={m[1]:m[0] for m in re.finditer(pattern,html,re.S)}
assert set(before)==set(after)
changed={k for k in before if before[k]!=after[k]}
assert changed=={'maps-ginkgo_arcade'},changed
card=after['maps-ginkgo_arcade']
for phrase in ['第3名额','0.7秒','半径65','15%','历史资料','普通、无机制','裂殖','孵化']:
    assert phrase in card,phrase
ids=set(re.findall(r'\bid="([^"]+)"',html));links=re.findall(r'href="#([^"]+)"',card)
assert all(link in ids for link in links)
paths=['scripts/monsters/monster_catalog.gd','scripts/monsters/telegraph_profiles.gd','scripts/combat/telegraphed_area_runtime.gd','scripts/main.gd','scripts/world/exploration_map_plan.gd','scripts/world/map_run_state.gd','scripts/save/canonical_build_rules.gd','scripts/canonical_game_state.gd']
for path in paths:assert (ROOT/path).read_text()==original(path),path
record={'baseline':BASE,'changed_cards':sorted(changed),'unchanged_cards':len(before)-1,'total_cards':len(after),'checked_internal_links':len(links),'schema':61,'unchanged_production_paths':paths,'catalog_sha256':hashlib.sha256(text.encode()).hexdigest(),'html_sha256':hashlib.sha256(html.encode()).hexdigest()}
(QA/'reference-verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(record,ensure_ascii=False))
