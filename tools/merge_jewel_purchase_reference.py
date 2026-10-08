#!/usr/bin/env python3
"""Merge only town_maps.jewel_purchase, preserving old catalog field bytes."""
import json
from pathlib import Path
from merge_ruins_garden_reference import member_span
ROOT = Path(__file__).resolve().parents[1]
target = ROOT / 'docs/reference/catalog.json'
fragment = json.loads((ROOT / 'docs/qa/jewel-purchase-reference/fragment.json').read_text())
assert fragment['service_id']=='jewel_merchant' and fragment['fixed_minimum'] and not fragment['special_sold']
assert len(fragment['offers'])==3 and all(row['cost']==fragment['cost'] and row['rarity']=='magic' for row in fragment['offers'])
before = target.read_text()
expected = json.loads(before)
value = json.dumps(fragment,ensure_ascii=False,sort_keys=True,indent='\t').replace('\n','\n\t\t')
if 'jewel_purchase' in expected['town_maps']:
    start,end = member_span(before,['town_maps','jewel_purchase'])
    after = before[:start]+value+before[end:]
else:
    start,end = member_span(before,['town_maps'])
    insertion = before.rfind('\n',start,end)
    after = before[:insertion]+',\n\t\t"jewel_purchase": '+value+before[insertion:]
expected['town_maps']['jewel_purchase']=fragment
assert json.loads(after)==expected
target.write_text(after)
print('Merged only town_maps.jewel_purchase')
