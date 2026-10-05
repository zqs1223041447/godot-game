#!/usr/bin/env python3
"""Capture a constrained, reviewable delta against the frozen v57 runtime catalog."""
import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = ROOT/'docs/qa/v058-reference'
STAT = 'damage_taken_from_mana_before_life'
IDS = {'34098', '42144', '922'}
LINES = {f'{percent}% of Damage is taken from Mana before Life' for percent in (8, 10, 40)}


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('frozen_checkout', type=Path); args = parser.parse_args()
    prior_path = args.frozen_checkout/'docs/reference/catalog.json'
    prior = json.loads(prior_path.read_text())
    current = json.loads((ROOT/'docs/reference/catalog.json').read_text())
    baseline_path = QA/'v057-reference-baseline.json'
    baseline = json.loads(baseline_path.read_text())
    assert baseline['catalog_file_sha256'] == hashlib.sha256(prior_path.read_bytes()).hexdigest()
    assert baseline['catalog_semantic_sha256'] == digest(prior)
    additions, changes = [], []

    def change(path, before, after):
        if path == ['game_version']:
            assert (before, after) == ('0.57.0', '0.58.0'); category = 'version'
        elif path[-1] in ('version', 'save_version', 'schema'):
            assert (before, after) == (34, 35); category = 'version'
        elif path[:2] == ['source_tree', 'nodes'] and path[2] in IDS:
            assert path[3] == 'execution' and path[4] in ('grants', 'status', 'supported', 'unsupported')
            category = 'source_execution'
        elif path[:2] == ['source_tree_localization', 'lines'] and path[2] in LINES:
            assert path[3:] in [['text'], ['status','grants'], ['status','implemented'], ['status','parser_supported']]
            category = 'display_metadata'
        elif path[:2] == ['source_tree_localization', 'nodes'] and path[2] in IDS:
            assert path[3] == 'stats' or path[2:] == ['34098','name']
            category = 'display_metadata'
        elif path == ['town_maps','options','special_modifiers',2,'description']:
            assert before.replace('雷电圆形预警可走开，不产生感电。', '雷电圆形预警可走开；命中会施加1秒感电，使后续命中承受伤害提高15%。') == after
            category = 'display_metadata'
        else:
            raise AssertionError(('Unapproved mechanical or structural change', path, before, after))
        changes.append({'path':path, 'before':before, 'after':after, 'category':category})

    def walk(before, after, path):
        if isinstance(before, dict) and isinstance(after, dict):
            assert set(before) <= set(after), ('Removed historical field', path)
            for key in before: walk(before[key], after[key], path+[key])
            for key in set(after)-set(before):
                assert path+[key] == ['mana_guard'] or (key == STAT and after[key] == 0), (path, key)
                additions.append(path+[key])
        elif isinstance(before, list) and isinstance(after, list) and len(before) == len(after):
            for index, (left, right) in enumerate(zip(before, after)): walk(left, right, path+[index])
        elif before != after:
            change(path, before, after)

    walk(prior, current, [])
    assert {c['path'][2] for c in changes if c['category'] == 'source_execution'} == IDS
    baseline['new_paths'] = sorted(additions, key=str)
    baseline['approved_changes'] = changes
    baseline_path.write_text(json.dumps(baseline, ensure_ascii=False, sort_keys=True, indent=2)+'\n')
    summary = {'frozen_commit':baseline['source_commit'], 'new_branch':'mana_guard',
               'default_zero_stat_additions':len(additions)-1, 'changed_leaf_groups':dict(Counter(c['category'] for c in changes)),
               'unchanged_mechanical_projection':True}
    (QA/'projection-summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == '__main__': main()
