#!/usr/bin/env python3
"""Bounded Iron Grip merge; preserve every other catalog member and source record."""
import json
from pathlib import Path
from merge_ruins_garden_reference import member_span

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / 'docs/qa/iron-grip'
LINE = "Strength's Damage bonus applies to Projectile Attack Damage as well as Melee Damage"


def merge(text, fragment):
    before = json.loads(text)
    assert fragment['save_version'] == fragment['source_policy'] == 57
    assert fragment['source_sha256'] == before['source_tree']['source_sha256']
    previous = before['source_tree']['nodes']['12926']
    node = fragment['node']
    assert node['id'] == '12926' and node['execution']['status'] == 'full'
    ignore = {'execution', 'ordinary_reachable_class_ids'}
    assert {k: v for k, v in node.items() if k not in ignore} == {k: v for k, v in previous.items() if k not in ignore}
    changes = [(('save_version',), 57), (('source_tree', 'source_policy'), 57),
               (('source_tree', 'nodes', '12926'), node),
               (('source_tree_localization', 'nodes', '12926'), fragment['localized_node']),
               (('source_tree_localization', 'lines', LINE), fragment['localized_line']),
               (('iron_grip',), fragment['iron_grip'])]
    expected = json.loads(text)
    spans = []
    for path, value in changes:
        parent = expected
        for key in path[:-1]: parent = parent[key]
        parent[path[-1]] = value
        encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, indent='\t').replace('\n', '\n'+'\t'*len(path))
        if path == ('iron_grip',) and 'iron_grip' not in before:
            end = text.rfind('\n}')
            spans.append((end, end, ',\n\t"iron_grip": '+encoded))
        else:
            start, end = member_span(text, path)
            spans.append((start, end, encoded))
    for start, end, value in sorted(spans, reverse=True): text = text[:start]+value+text[end:]
    assert json.loads(text) == expected
    assert expected['canonical'] == before['canonical']
    return text


if __name__ == '__main__':
    catalog = ROOT / 'docs/reference/catalog.json'
    catalog.write_text(merge(catalog.read_text(), json.loads((QA/'reference-fragment.json').read_text())))
    print('Merged only12926 and current57 provenance; historical canonical untouched')
