#!/usr/bin/env python3
"""Produce the audited runtime facts without upstream images or image locators."""
from pathlib import Path
import argparse
import hashlib
import json
ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'data/passive_source/normalized_tree.json'
OUTPUT = ROOT / 'data/passives/official_tree_runtime.json'
IMAGE_FIELDS = {'icon', 'activeIcon', 'inactiveIcon', 'activeEffectImage', 'flavourText', 'flavourTextColour', 'flavourTextRect'}
def build(source):
    return {
        'schema_version': 1,
        'source': source['provenance'],
        'points': source['points'], 'bounds': source['bounds'],
        'classes': [{key: entry[key] for key in ('name', 'base_str', 'base_dex', 'base_int')} |
                    {'ascendancies': [{key: asc[key] for key in ('id', 'name')} for asc in entry['ascendancies']]}
                    for entry in source['classes']],
        'nodes': {key: {field: value for field, value in record.items() if field not in IMAGE_FIELDS}
                  for key, record in source['node_records'].items()},
        'groups': source['groups'], 'positions': source['positions'],
        'edges': source['edges'], 'standard_tree': source['standard_tree'],
        'special_subtrees': source['special_subtrees'],
        'coverage': source['coverage'],
    }
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    source = json.loads(SOURCE.read_text())
    result = build(source)
    raw = (json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n').encode()
    assert len(result['nodes']) == len(source['node_records']) == 3390
    for node_id, record in source['node_records'].items():
        assert result['nodes'][node_id].get('stats') == record.get('stats')
        assert result['nodes'][node_id].get('masteryEffects') == record.get('masteryEffects')
    assert b'Art/2DArt' not in raw
    assert b'flavourText' not in raw, 'Narrative/artwork layout is not a runtime rule input'
    if args.check:
        assert OUTPUT.read_bytes() == raw, 'Runtime tree drift'
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_bytes(raw)
    print(f'Runtime source facts: {len(result["nodes"])} records, {len(result["positions"])} positions, {len(raw)} bytes; SHA256 {hashlib.sha256(raw).hexdigest()}')
if __name__ == '__main__': main()
