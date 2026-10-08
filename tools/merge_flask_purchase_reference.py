#!/usr/bin/env python3
"""Merge only town_maps.flask_purchase; preserve existing catalog value bytes."""
import json
from pathlib import Path
from merge_ruins_garden_reference import member_span

ROOT = Path(__file__).resolve().parents[1]
target = ROOT / 'docs/reference/catalog.json'
fragment = json.loads((ROOT / 'docs/qa/flask-purchase-reference/fragment.json').read_text())
assert fragment['service_id'] == 'equipment_merchant' and fragment['cost'] == 8
assert {row['definition_id'] for row in fragment['offers']} == {'flask:life', 'flask:mana'}
assert len(fragment['offers']) == 2 and all(row['cost'] == fragment['cost'] and row['size'] == [1, 2] for row in fragment['offers'])
before = target.read_text()
expected = json.loads(before)
value = json.dumps(fragment, ensure_ascii=False, sort_keys=True, indent='\t').replace('\n', '\n\t\t')
if 'flask_purchase' in expected['town_maps']:
    start, end = member_span(before, ['town_maps', 'flask_purchase'])
    after = before[:start] + value + before[end:]
else:
    start, end = member_span(before, ['town_maps'])
    insertion = before.rfind('\n', start, end)
    after = before[:insertion] + ',\n\t\t"flask_purchase": ' + value + before[insertion:]
expected['town_maps']['flask_purchase'] = fragment
assert json.loads(after) == expected
target.write_text(after)
print('Merged only town_maps.flask_purchase')
