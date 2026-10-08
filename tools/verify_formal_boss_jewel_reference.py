#!/usr/bin/env python3
"""Static one-card sync and frozen runtime/save-scope proof; no gameplay reruns."""
import hashlib
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlsplit

from build_reference import build
from merge_ruins_garden_reference import member_span

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / 'docs/qa/formal-boss-jewel-recovery'
REF = ROOT / 'docs/reference'
BASE = 'a0a8734b95f1f0f2c4d2af307db8590555067651'


def old(path):
    return subprocess.check_output(['git', 'show', BASE + ':' + path], cwd=ROOT)


def function(text, name):
    return re.search(r'^func ' + name + r'\(.*?(?=^func |\Z)', text, re.M | re.S)[0].rstrip()


def verify():
    unchanged = ['scripts/save/canonical_build_rules.gd', 'scripts/save/canonical_build_store.gd',
                 'scripts/save/canonical_build_migration.gd', 'scripts/items/item_location_rules.gd',
                 'scripts/items/item_transfer_plan.gd', 'scripts/items/unified_item_catalog.gd',
                 'scripts/ui/canonical_inventory_panel.gd', 'scripts/ui/canonical_passive_panel.gd',
                 'scripts/passives/source_tree_runtime.gd', 'scripts/passives/source_tree_allocation_rules.gd',
                 'scripts/items/jewel_purchase.gd', 'scripts/items/jewel_craft_rules.gd',
                 'scripts/monsters/monster_runtime.gd', 'data/passives/official_tree_runtime.json',
                 'data/passive_source/localization_zh_CN.json', 'docs/reference/source-tree-coverage.json',
                 'tests/formal_boss_equipment_recovery_test.gd', 'tests/source_tree_allocation_rules_test.gd']
    for path in unchanged:
        assert (ROOT / path).read_bytes() == old(path), path
    model = (ROOT / 'scripts/canonical_game_state.gd').read_text()
    previous = old('scripts/canonical_game_state.gd').decode()
    preserved_functions = ['award_equipment', 'award_normal_boss_equipment', '_award_equipment',
                           'award_jewel', 'award_special_jewel', '_admit_reward_item', '_admit_reward_item_candidate']
    for name in preserved_functions:
        assert function(model, name) == function(previous, name), name
    main = (ROOT / 'scripts/main.gd').read_text()
    prior_main = old('scripts/main.gd').decode()
    assert function(main, '_award_kill_equipment') == function(prior_main, '_award_kill_equipment')
    assert function(main, '_finish_enemy_death') == function(prior_main, '_finish_enemy_death').replace('_award_kill_special_jewel()', '_award_kill_special_jewel(enemy)')
    for suite in ['formal_boss_jewel_recovery_test', 'source_tree_allocation_rules_test']:
        run = json.loads((QA / (suite + '-run.json')).read_text())
        assert run['ok'] and run['failures'] == 0 and run['exit_code'] == 0
        for path, digest in run['sha256'].items():
            assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, path
    report = json.loads((QA / 'formal_boss_jewel_recovery_test.json').read_text())
    text = (REF / 'catalog.json').read_text()
    original = old('docs/reference/catalog.json').decode()
    start, end = member_span(original, ['jewels', 'branchfinder', 'description'])
    assert text == original[:start] + json.dumps(report['description'], ensure_ascii=False) + original[end:]
    data = json.loads(text)
    html = (REF / 'index.html').read_text()
    assert html == build(data, json.loads((REF / 'art/manifest.json').read_text()))
    pattern = r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
    cards = {m[1]: m[0] for m in re.finditer(pattern, html, re.S)}
    prior = {m[1]: m[0] for m in re.finditer(pattern, old('docs/reference/index.html').decode(), re.S)}
    assert cards.keys() == prior.keys()
    changed = {key for key in cards if cards[key] != prior[key]}
    assert changed == {'jewels-branchfinder'}, changed
    target = cards['jewels-branchfinder']
    for phrase in ['小型与显著天赋', '不含基石、精通、起点或珠宝孔', '280', '1 点', '同一珠宝到待安置', '非正式与普通掉落规则保持']:
        assert phrase in target, phrase
    anchors = set(re.findall(r'\bid="([^"]+)"', html))
    links = 0
    for href in re.findall(r'(?:href|src)="([^"]+)"', target):
        parsed = urlsplit(href)
        if parsed.scheme or parsed.netloc:
            continue
        if parsed.path:
            assert (REF / unquote(parsed.path)).is_file(), href
        else:
            assert unquote(parsed.fragment) in anchors, href
        links += 1
    paths = unchanged + ['scripts/main.gd', 'scripts/canonical_game_state.gd', 'scripts/jewel_data.gd',
                         'tests/formal_boss_jewel_recovery_test.gd', 'tools/build_reference.py',
                         'docs/reference/catalog.json', 'docs/reference/index.html']
    return {'ok': True, 'baseline': BASE, 'schema': 58, 'unchanged_files': unchanged,
            'unchanged_model_functions': preserved_functions, 'changed_cards': sorted(changed),
            'other_cards_byte_identical': len(cards) - len(changed), 'checked_related_links': links,
            'catalog_changed_members': ['jewels.branchfinder.description'],
            'sha256': {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}}


if __name__ == '__main__':
    result = verify()
    (QA / 'scope-reference.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ['sha256', 'unchanged_files', 'unchanged_model_functions']}, ensure_ascii=False))
