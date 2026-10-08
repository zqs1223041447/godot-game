#!/usr/bin/env python3
"""Insert only the catalog-only purchase metadata; retain all old JSON bytes."""
import json
from pathlib import Path
from merge_ruins_garden_reference import member_span

ROOT = Path(__file__).resolve().parents[1]
catalog = ROOT / 'docs/reference/catalog.json'
fragment = json.loads((ROOT / 'docs/qa/equipment-purchase-reference/fragment.json').read_text())
assert fragment['service_id'] == 'equipment_merchant'
assert fragment['offers'] and all(row['cost'] == fragment['cost'] and row['item_level'] == fragment['item_level'] and row['rarity'] == 'normal' and row['affix_count'] == 0 for row in fragment['offers'])
before = catalog.read_text()
expected = json.loads(before)
value = json.dumps(fragment, ensure_ascii=False, sort_keys=True, indent='\t').replace('\n', '\n\t\t')
if 'equipment_purchase' in expected['town_maps']:
    start, end = member_span(before, ['town_maps', 'equipment_purchase'])
    after = before[:start] + value + before[end:]
else:
    start, end = member_span(before, ['town_maps'])
    insertion = before.rfind('\n', start, end)
    after = before[:insertion] + ',\n\t\t"equipment_purchase": ' + value + before[insertion:]
expected['town_maps']['equipment_purchase'] = fragment
assert json.loads(after) == expected
catalog.write_text(after)
print('Merged only town_maps.equipment_purchase')
