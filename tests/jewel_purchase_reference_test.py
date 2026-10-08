#!/usr/bin/env python3
"""Check only the approved four-card jewel documentation delta."""
import hashlib
import importlib.util
import json
import re
import subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
BASE = 'baefe3004901abef10cbb3fd2a90507a8da1984d'
def baseline(path):
    return subprocess.check_output(['git','show',f'{BASE}:{path}'],cwd=ROOT)
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,ROOT/path)
    result=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result
builder=module('jewel_reference_builder','tools/build_reference.py')
scanner=module('jewel_reference_span','tools/merge_ruins_garden_reference.py')
old_text=baseline('docs/reference/catalog.json').decode()
old=json.loads(old_text)
new_text=(ROOT/'docs/reference/catalog.json').read_text()
new=json.loads(new_text)
purchase=new['town_maps'].pop('jewel_purchase')
assert new==old, 'Unrelated catalog semantic changes'
for key in old:
    paths=[['town_maps',child] for child in old[key]] if key=='town_maps' else [[key]]
    for path in paths:
        a,b=scanner.member_span(old_text,path)
        c,d=scanner.member_span(new_text,path)
        assert old_text[a:b]==new_text[c:d], f'Unrelated catalog bytes changed: {path}'
art=json.loads((ROOT/'docs/reference/art/manifest.json').read_text())
old_html=baseline('docs/reference/index.html').decode()
assert builder.build(old,art)==old_html, 'Generator changed old-input HTML'
new_html=(ROOT/'docs/reference/index.html').read_text()
pattern=r'(<article\b[^>]*id="([^"]+)"[^>]*>.*?</article>)'
def cards(text): return {key:card for card,key in re.findall(pattern,text,re.S)}
before,after=cards(old_html),cards(new_html)
assert before and before.keys()==after.keys()
changed=[key for key in before if before[key]!=after[key]]
assert len(purchase['offers'])==3 and purchase['cost']==8 and purchase['fixed_minimum'] and not purchase['special_sold']
expected={'town_services-jewel_merchant'}|{'jewels-'+row['base_id'] for row in purchase['offers']}
assert set(changed)==expected, f'Unexpected changed cards: {changed}'
merchant=after['town_services-jewel_merchant']
assert '不出售特殊珠宝' in merchant and '固定最低数值魔法珠宝' in merchant and '已分配并连通起点的合法珠宝孔' in merchant
assert f'data-jewel-purchase-field="cost">{purchase["cost"]}</span>' in merchant
assert len(re.findall('data-jewel-purchase-id=',merchant))==3
assert 'data-jewel-purchase-id="branchfinder"' not in new_html
for row in purchase['offers']:
    card=after['jewels-'+row['base_id']]
    for text in [merchant,card]:
        assert f'data-jewel-purchase-id="{row["base_id"]}" data-cost="{row["cost"]}"' in text
        assert builder.lines(row['description']) in text
    assert row['rarity']=='magic' and len(row['affixes'])==2 and row['size']==[1,1]
    assert '合法珠宝孔' in card and '商店不出售特殊珠宝' in card
for source,digest in purchase['source_sha256'].items():
    assert hashlib.sha256((ROOT/source).read_bytes()).hexdigest()==digest
assert baseline('docs/reference/source-tree-coverage.json')==(ROOT/'docs/reference/source-tree-coverage.json').read_bytes()
assert not subprocess.check_output(['git','diff','--name-only',BASE,'--','docs/reference/art','assets','scripts'],cwd=ROOT)
ids=set(re.findall(r'\bid="([^"]+)"',new_html))
links=[key for card in expected for key in re.findall(r'href="#([^"]+)"',after[card])]
assert all(key in ids for key in links)
report={'baseline':BASE,'old_input_html_byte_identical':True,'old_catalog_semantics_and_value_bytes_preserved':True,
        'drop_and_craft_data_and_cards_unchanged':True,'runtime_and_art_unchanged':True,'execution_coverage_unchanged':True,
        'total_cards':len(before),'changed_cards':changed,'unchanged_cards':len(before)-len(changed),
        'ordinary_offers':len(purchase['offers']),'internal_links':len(links),'cost':purchase['cost'],'save_version':purchase['save_version'],
        'source_sha256':purchase['source_sha256']}
(ROOT/'docs/qa/jewel-purchase-reference/preservation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
