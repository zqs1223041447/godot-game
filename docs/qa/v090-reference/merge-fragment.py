#!/usr/bin/env python3
"""Replace only current exploration metadata; retain all other JSON raw tokens."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'
BASE = '8944b8f'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def baseline(path):
    return subprocess.check_output(['git', 'show', BASE + ':' + path], cwd=ROOT)


def spans(text):
    decoder = json.JSONDecoder()
    cursor = 1
    result = {}
    while True:
        while text[cursor].isspace(): cursor += 1
        if text[cursor] == '}': return result
        key_start = cursor
        key, cursor = decoder.raw_decode(text, cursor)
        while text[cursor].isspace(): cursor += 1
        assert text[cursor] == ':'
        cursor += 1
        while text[cursor].isspace(): cursor += 1
        value_start = cursor
        _, cursor = decoder.raw_decode(text, cursor)
        result[key] = (key_start, value_start, cursor)
        while text[cursor].isspace(): cursor += 1
        if text[cursor] == ',': cursor += 1
        else:
            assert text[cursor] == '}'
            return result


def tokens(raw):
    return {key: raw[start:end] for key, (_, start, end) in spans(raw).items()}


def encoded(value, level):
    return json.dumps(value, ensure_ascii=False, indent='\t', sort_keys=True).replace('\n', '\n' + '\t' * (level + 1))


def compose(raw, replacements, level, removed=()):
    values = tokens(raw)
    for key in removed: del values[key]
    values.update(replacements)
    indent = '\t' * (level + 1)
    return '{\n' + ',\n'.join(indent + json.dumps(key) + ': ' + value for key, value in sorted(values.items())) + '\n' + '\t' * level + '}'


def evidence(path):
    return {'path': path, 'sha256': sha((ROOT / path).read_bytes())}


def main():
    before = (REF / 'catalog.json').read_text()
    assert before.encode() == baseline('docs/reference/catalog.json')
    old = json.loads(before)
    fragment = json.loads((QA / 'exploration-fragment.json').read_text())
    tested = json.loads((ROOT / 'docs/qa/v090-routes/tested-inputs.json').read_text())
    for path, digest in tested.items(): assert sha((ROOT / path).read_bytes()) == digest, path
    report = json.loads((ROOT / 'docs/qa/v090-routes/main-result.json').read_text())
    layout = json.loads((ROOT / 'docs/qa/v090-routes/layout-result.json').read_text())
    assert report['checks'] == 185 and report['failures'] == 0 and not report['failed_labels']
    assert layout['checks'] == 28135 and layout['failures'] == 0 and len(layout['plans']) == 36
    assert {row['map_id'] for row in report['entries']} == {'broken_ruins', 'sunwell_terrace', 'ginkgo_arcade'}
    assert old['game_version'] == '0.87.0' and old['save_version'] == 50
    exploration_raw = tokens(before)['exploration_maps']
    maps_raw = tokens(exploration_raw)['maps']
    old_maps = tokens(maps_raw)
    replacements = {}
    for map_id, update in fragment['maps'].items():
        entry_raw = old_maps[map_id]
        if map_id == 'old_garden':
            records = report['full_run']['records']
            actual = {'spawn_records': records, 'actor_ids': [row['actor_id'] for row in records],
                      'actor_ids_origin': 'Derived from full_run.records; this report has no old_garden entries item.',
                      'report_record_path': 'full_run.records'}
        else:
            index, observed = next((i, row) for i, row in enumerate(report['entries']) if row['map_id'] == map_id)
            actual = {'entry': observed['entry'], 'actor_ids': observed['ids'], 'spawn_records': observed['records'],
                      'report_record_path': f'entries[{index}]'}
        assert len(actual['spawn_records']) == old['exploration_maps']['maps'][map_id]['ordinary_target'] + 1
        assert all(row['spawn_key'].startswith(map_id + '/') for row in actual['spawn_records'])
        update['actual_main_entry'] = actual
        replacements[map_id] = compose(entry_raw, {key: encoded(value, 3) for key, value in update.items()}, 3)
        for key, value in tokens(entry_raw).items():
            if key not in update: assert tokens(replacements[map_id])[key] == value, (map_id, key)
    current_maps = compose(maps_raw, replacements, 2)
    metadata = {
        'route_distribution': fragment['route_distribution'],
        'layout_test': evidence('docs/qa/v090-routes/layout-result.json'),
        'tested_inputs': evidence('docs/qa/v090-routes/tested-inputs.json'),
        'actual_main_report': evidence('docs/qa/v090-routes/main-result.json'),
        'actual_main_checks': report['checks'], 'actual_main_failures': report['failures'],
        'layout_checks': layout['checks'], 'layout_configurations': len(layout['plans']),
        'scope': '本批资料仅导出四图I档同源布局与独立Plan，并只读复用冻结输入下的28,135项布局/Plan验证（四图×三档×三种子，共36配置，包含旧Plan同源编排比较）和185项实际Main验证。Main的entries仅记录残垣、晴泉、银杏三图；旧庭记录来自full_run.records，实体ID从记录提取，不虚构旧庭entries或入场坐标。原Main包含受控致死结算、有限后代与返城领奖辅助，不是自然战斗录像。此资料步骤不重跑战斗、不构造角色装备、不生成PNG；没有原生F8视觉、600秒稳定性、安装包或Release验收结论。',
    }
    removed = ['actual_main_original_failures', 'focused_input_checks', 'focused_input_report', 'main_acceptance', 'plan_test', 'plan_test_inputs']
    current_exploration = compose(exploration_raw, {'maps': current_maps, **{key: encoded(value, 1) for key, value in metadata.items()}}, 1, removed)
    _, start, end = spans(before)['exploration_maps']
    after = before[:start] + current_exploration + before[end:]
    preserved = []
    for key, value in tokens(before).items():
        if key != 'exploration_maps':
            assert tokens(after)[key] == value, key
            preserved.append(key)
    (REF / 'catalog.json').write_text(after)
    proof = {'baseline_commit': BASE, 'baseline_catalog_sha256': sha(before.encode()),
             'catalog_sha256': sha(after.encode()), 'fragment_sha256': sha((QA / 'exploration-fragment.json').read_bytes()),
             'replaced_top_level': ['exploration_maps'], 'retained_raw_top_level': preserved,
             'map_changed_fields': ['actual_main_entry', 'description', 'geometry', 'plan_example'],
             'all_other_map_field_tokens_preserved': True, 'old_garden_main_record_path': 'full_run.records',
             'game_version_preserved': old['game_version'], 'method': 'Raw-token splice; old catalog is parsed only in Python, never Godot.'}
    (QA / 'catalog-format-preservation.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2) + '\n')
    print('Replaced exploration metadata; preserved', len(preserved), 'other top-level raw sections and all map economy/boss tokens')


if __name__ == '__main__': main()
