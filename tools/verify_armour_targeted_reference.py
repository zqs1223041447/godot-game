#!/usr/bin/env python3
import hashlib,json,re,subprocess
from build_reference import build
from merge_armour_targeted_reference import ROOT,QA,OP,merge
BASE='a071697f85496b8dd0f7e63aa68f7e00d74c5d80'
def original(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT).decode()
text=(ROOT/'docs/reference/catalog.json').read_text();old=original('docs/reference/catalog.json')
fragment=json.loads((QA/'reference-fragment.json').read_text());data=json.loads(text)
assert text==merge(old,fragment)==merge(text,fragment)
assert data['save_version']==61 and data['crafting'][OP]['catalog_vocabulary']==51
entry=data['crafting'][OP]
assert entry['eligible_base_ids']==['emberhide_vest'] and entry['target_family_ids']==['ironhide']
assert entry['cost_by_rarity']=={'magic':16,'rare':40}
assert entry['eligibility'][0]['minimum_item_level_by_rarity']=={'magic':1,'rare':1}
assert [(r['tier'],r['min'],r['max']) for r in entry['eligibility'][0]['target_tiers_at_maximum_level']]==[(1,30,50),(2,55,80),(3,85,120)]
html=(ROOT/'docs/reference/index.html').read_text();old_html=original('docs/reference/index.html')
art=json.loads((ROOT/'docs/reference/art/manifest.json').read_text())
assert html==build(data,art) and old_html==build(json.loads(old),art)
pattern=r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
before={m[1]:m[0] for m in re.finditer(pattern,old_html,re.S)};after={m[1]:m[0] for m in re.finditer(pattern,html,re.S)}
assert set(after)-set(before)=={'crafting-'+OP} and not set(before)-set(after)
changed={k for k in before if before[k]!=after[k]}
assert changed=={'affixes-ironhide','crafting-calibration_shard','currencies-calibration_shard','town_services-crafter'},changed
for phrase in ['灰烬皮甲','总计32碎片','不保留其他原词缀','物品等级8','等级16','原子写盘','失败重试保持种子']:
    assert phrase in after['crafting-'+OP],phrase
ids=set(re.findall(r'\bid="([^"]+)"',html));links=[]
for key in changed|{'crafting-'+OP}:
    for link in re.findall(r'href="#([^"]+)"',after[key]):
        assert link in ids,link
        links.append(link)
unchanged_paths=['scripts/items/equipment_catalog.gd','scripts/items/defense_rating_affix_profile.gd','scripts/items/crafting_transaction_planner.gd','scripts/items/crafting_rules.gd','scripts/canonical_game_state.gd','scripts/mechanics/defense_rules.gd','scripts/combat/damage_resolver.gd','scripts/save/canonical_build_rules.gd','docs/reference/source-tree-coverage.json']
for path in unchanged_paths:assert (ROOT/path).read_text()==original(path),path
record={'baseline':BASE,'new_cards':['crafting-'+OP],'changed_existing_cards':sorted(changed),'unchanged_existing_cards':len(before)-len(changed),'total_cards':len(after),'checked_internal_links':len(links),'schema':61,'vocabulary':51,'unchanged_production_paths':unchanged_paths,'catalog_sha256':hashlib.sha256(text.encode()).hexdigest(),'html_sha256':hashlib.sha256(html.encode()).hexdigest()}
(QA/'reference-verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(record,ensure_ascii=False))
