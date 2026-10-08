#!/usr/bin/env python3
"""Merge five authoritative source cards, one localized line and current provenance."""
import argparse
import json
from pathlib import Path

from merge_ruins_garden_reference import member_span

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'docs/reference/catalog.json'
IDS = {'18670', '25511', '30894', '56646', '64878'}
LINE = '12% increased Elemental Damage with Attack Skills'


def merge(text, fragment):
    before = json.loads(text)
    assert set(fragment) == {'save_version', 'source_policy', 'source_sha256', 'nodes', 'localized_nodes', 'localized_lines'}
    assert set(fragment['nodes']) == set(fragment['localized_nodes']) == IDS
    assert set(fragment['localized_lines']) == {LINE}
    assert fragment['source_sha256'] == before['source_tree']['source_sha256']
    assert fragment['save_version'] == fragment['source_policy'] == 55
    changes = [(('save_version',), fragment['save_version']),
               (('source_tree', 'source_policy'), fragment['source_policy'])]
    for key in sorted(IDS):
        node = fragment['nodes'][key]
        previous = before['source_tree']['nodes'][key]
        assert node['stats'] == previous['stats'] == [LINE]
        assert node['execution']['status'] == 'full' and not node['execution']['unsupported']
        assert {k: v for k, v in node.items() if k not in {'execution', 'ordinary_reachable_class_ids'}} == {k: v for k, v in previous.items() if k not in {'execution', 'ordinary_reachable_class_ids'}}
        assert node['ordinary_reachable_class_ids'] == ([] if key == '18670' else list(range(7)))
        localized = fragment['localized_nodes'][key]
        assert {k: v for k, v in localized.items() if k != 'stats'} == {k: v for k, v in before['source_tree_localization']['nodes'][key].items() if k != 'stats'}
        changes += [(('source_tree', 'nodes', key), node), (('source_tree_localization', 'nodes', key), localized)]
    changes.append((('source_tree_localization', 'lines', LINE), fragment['localized_lines'][LINE]))
    expected = json.loads(text)
    spans = []
    for path, value in changes:
        parent = expected
        for key in path[:-1]:
            parent = parent[key]
        parent[path[-1]] = value
        start, end = member_span(text, path)
        serialized = json.dumps(value, ensure_ascii=False, sort_keys=True, indent='\t').replace('\n', '\n' + '\t' * len(path))
        spans.append((start, end, serialized))
    for start, end, value in sorted(spans, reverse=True):
        text = text[:start] + value + text[end:]
    assert json.loads(text) == expected, 'Unrelated catalog data changed'
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('fragment', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    before = CATALOG.read_text(encoding='utf-8')
    result = merge(before, json.loads(args.fragment.read_text(encoding='utf-8')))
    if args.check:
        assert json.loads(before) == json.loads(result), 'Catalog differs from bounded export'
        print('Five source cards and current provenance match the runtime export')
    else:
        CATALOG.write_text(result, encoding='utf-8')


if __name__ == '__main__':
    main()
