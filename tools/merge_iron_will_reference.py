#!/usr/bin/env python3
"""Bounded Iron Will merge; preserve every other catalog member and source record."""
import json
from pathlib import Path
from merge_ruins_garden_reference import member_span

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / 'docs/qa/iron-will'
LINE = "Strength's Damage bonus applies to all Spell Damage as well"


def merge(text, fragment):
    before = json.loads(text)
    assert fragment['save_version'] == fragment['source_policy'] == 58
    assert fragment['source_sha256'] == before['source_tree']['source_sha256']
    previous = before['source_tree']['nodes']['50288']
    node = fragment['node']
    assert node['id'] == '50288' and node['execution']['status'] == 'full'
    ignore = {'execution', 'ordinary_reachable_class_ids'}
    assert {k: v for k, v in node.items() if k not in ignore} == {k: v for k, v in previous.items() if k not in ignore}
    changes = [(('save_version',), 58), (('source_tree', 'source_policy'), 58),
               (('source_tree', 'nodes', '50288'), node),
               (('source_tree_localization', 'nodes', '50288'), fragment['localized_node']),
               (('source_tree_localization', 'lines', LINE), fragment['localized_line']),
               (('iron_will',), fragment['iron_will'])]
    expected = json.loads(text)
    spans = []
    for path, value in changes:
        parent = expected
        for key in path[:-1]: parent = parent[key]
        parent[path[-1]] = value
        encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, indent='\t').replace('\n', '\n'+'\t'*len(path))
        if path == ('iron_will',) and 'iron_will' not in before:
            end = text.rfind('\n}')
            spans.append((end, end, ',\n\t"iron_will": '+encoded))
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
    print('Merged only50288 and current58 provenance; historical canonical untouched')
