#!/usr/bin/env python3
"""Read the independent released v55 tree; admit only the reviewed v56 delta."""
import hashlib
import json
import re
import subprocess
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = ROOT/'docs/qa/v056-reference'
COMMIT = '63d84b2'


def old_bytes(path):
    return subprocess.check_output(['git', 'show', COMMIT+':'+path], cwd=ROOT)


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest()


def differences(old, new, path=()):
    if old == new:
        return []
    if len(path) == 5 and path[:2] == ('forgeblade', 'examples') and path[3:] == ('casts', 'basic'):
        return [{'path': list(path), 'before': old, 'after': new}]
    if isinstance(old, dict) and isinstance(new, dict):
        assert old.keys() <= new.keys(), ('Unexpected removed keys', path)
        return ([{'path': list(path+(key,)), 'added': new[key]} for key in sorted(new.keys()-old.keys())]
                + [row for key in sorted(old) for row in differences(old[key], new[key], path+(key,))])
    if isinstance(old, list) and isinstance(new, list) and len(old) == len(new):
        return [row for index in range(len(old)) for row in differences(old[index], new[index], path+(index,))]
    return [{'path': list(path), 'before': old, 'after': new}]


def main():
    original = old_bytes('docs/reference/catalog.json')
    old = json.loads(original)
    new = json.loads((ROOT/'docs/reference/catalog.json').read_text())
    rows = differences(old, new)
    added, changed, categories = [], [], Counter()
    replacements = {
        '本武器物理单独结算，仅增强裂刃斩直接命中。详情列出基底、本地点数与本地提高。':
            '装备后普通攻击变为单目标近战挥击；本武器物理增强普通近战攻击与裂刃斩。',
        '本地W仅裂刃direct；全局暴击仍作用于攻击、法术及独立secondary，最大魔力与魔力恢复仍是角色全局资源。':
            '本地W仅短刃普通近战basic/direct与裂刃cleave/direct；全局暴击仍作用于攻击、法术及独立secondary，最大魔力与魔力恢复仍是角色全局资源。',
        old['weapon_stages']['weapon_local']['description']:
            '局部点伤与局部物理提高先结算本武器；长弓仅加入普通攻击与龙卷箭体，锻纹短刃仅加入普通近战攻击与裂刃斩直接命中，均按技能基础倍率加入物理点数。保留原有角色基伤，不是完整武器基伤替换。',
    }
    for row in rows:
        path = row['path']
        category = ''
        if 'added' in row:
            if path == ['melee_basic']:
                category = 'new_melee_reference'
            elif path in [['forgeblade', 'local_consumers', 'basic'],
                          ['weapon_stages', 'weapon_local', 'consumers_by_base', 'forgeblade', 'basic']]:
                assert row['added'] == ['direct']
                category = 'new_basic_consumer_metadata'
            assert category, row
            added.append(path)
        else:
            before, after = row['before'], row['after']
            if path == ['game_version'] and (before, after) == ('0.55.0', '0.56.0'):
                category = 'game_version_only'
            elif len(path) == 5 and path[:2] == ['forgeblade', 'examples'] and path[3:] == ['casts', 'basic']:
                assert set(before['hits']) == {'projectile', 'secondary'}
                assert set(after['hits']) == {'direct'} and set(after['critical']) == {'primary'}
                category = 'approved_new_forgeblade_basic'
            elif path == ['weapon_stages', 'weapon_local', 'consumers', 'basic']:
                assert before == ['projectile'] and after == ['projectile', 'direct']
                category = 'new_basic_consumer_metadata'
            elif isinstance(before, str) and any(old_text in before and after == before.replace(old_text, new_text, 1)
                                                  for old_text, new_text in replacements.items()):
                assert path[-1] in ['description', 'global_scope']
                assert path[0] in ['forgeblade', 'equipment', 'weapon_stages', 'town_maps']
                category = 'exact_consumer_description'
            elif path[-1] == 'weapon_damage_summary' and isinstance(before, str):
                assert '；仅裂刃斩直接命中' in before
                assert after == before.replace('；仅裂刃斩直接命中', '；普通近战攻击与裂刃斩')
                category = 'exact_consumer_description'
            assert category, row
            changed.append(row)
        categories[category] += 1
    image_paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', COMMIT,
                                           'docs/reference'], cwd=ROOT, text=True).splitlines()
    baseline = {
        'source_commit': COMMIT,
        'source': 'released v0.55 docs/reference from git object, never rebuilt with v56 code',
        'source_file_sha256': hashlib.sha256(original).hexdigest(),
        'catalog_semantic_sha256': digest(old),
        'source_tree_sha256': digest(old['source_tree']),
        'source_coverage_sha256': hashlib.sha256(old_bytes('docs/reference/source-tree-coverage.json')).hexdigest(),
        'article_ids': re.findall(r'<article\b[^>]*\bid="([^"]+)"', old_bytes('docs/reference/index.html').decode()),
        'image_sha256': {path.removeprefix('docs/reference/'): hashlib.sha256(old_bytes(path)).hexdigest()
                         for path in image_paths if path.endswith('.png')},
        'new_paths': added, 'approved_changes': changed, 'delta_categories': dict(categories),
    }
    target = QA/'v055-reference-baseline.json'
    assert not target.exists(), 'Never overwrite an independent baseline'
    target.write_text(json.dumps(baseline, ensure_ascii=False, indent=2)+'\n')
    (QA/'catalog-diff-review.json').write_text(json.dumps({
        'categories': dict(categories), 'new_paths': added,
        'approved_change_paths': [row['path'] for row in changed],
    }, ensure_ascii=False, indent=2)+'\n')
    print('Exact v55 baseline captured:', dict(categories))


if __name__ == '__main__':
    main()
