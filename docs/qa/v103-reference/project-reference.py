#!/usr/bin/env python3
"""Append four authority-backed cards, retaining every prior catalog value token."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'
BASE = 'b7d98c5b94c2c39f6f258835b28cfc32c4cd34d9'
REPORT = 'docs/qa/v103-transactions/first/transactions-report.json'
TX = ROOT / Path(REPORT).parent
IDS = ['targeted_reforge_' + target + '_resistance' for target in ['fire', 'cold', 'lightning', 'chaos']]
PRIMARY = ['emberhide_vest-magic-fire_resistance', 'emberhide_vest-rare-cold_resistance',
    'nine_slot_etched_ring-magic-lightning_resistance', 'nine_slot_etched_ring-rare-chaos_resistance']


def sha(raw): return hashlib.sha256(raw).hexdigest()
def baseline(path): return subprocess.check_output(['git', 'show', BASE + ':' + path], cwd=ROOT)
def load(path): return json.loads(path.read_text())


def spans(raw):
    decoder = json.JSONDecoder()
    cursor = raw.index('{') + 1
    result = {}
    while True:
        while raw[cursor].isspace(): cursor += 1
        if raw[cursor] == '}': return result
        key, cursor = decoder.raw_decode(raw, cursor)
        while raw[cursor].isspace(): cursor += 1
        assert raw[cursor] == ':'
        cursor += 1
        while raw[cursor].isspace(): cursor += 1
        start = cursor
        _, cursor = decoder.raw_decode(raw, cursor)
        result[key] = (start, cursor)
        while raw[cursor].isspace(): cursor += 1
        if raw[cursor] == ',': cursor += 1
        else:
            assert raw[cursor] == '}'
            return result


def tokens(raw): return {k: raw[a:b] for k, (a, b) in spans(raw).items()}


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def balance(snapshot):
    return sum(item['payload']['quantity'] for uid, item in snapshot['items'].items()
        if item['definition_id'] == 'currency:calibration_shard' and snapshot['locations'][uid]['kind'] == 'bag')


def evidence(row):
    facts = []
    profile = row['profiles']['after']
    for element, label in [('fire', '火焰'), ('cold', '冰霜'), ('lightning', '闪电')]:
        for field, suffix in [('raw_resistances', '原始抗性'), ('effective_resistances', '有效抗性'), ('maximum_resistances', '有效上限')]:
            facts.append({'key': element + '-' + field, 'label': label + suffix,
                'value': profile[field][element], 'percent': True})
    for field, label in [('raw', '原始抗性'), ('effective', '有效抗性'), ('cap', '有效上限')]:
        facts.append({'key': 'chaos-' + field, 'label': '混沌' + label,
            'value': row['profiles']['chaos_after'][field], 'percent': True})
    base = '../qa/v103-transactions/first/'
    return {'title': '实际保存后重新穿戴的角色抗性',
        'scope': '以下数值来自同一真实模型事务的保存、穿戴与重载结果。源装备在背包，重铸时不直接改变角色防御；这些是穿戴新装备后的完整角色值，不是只归因于该词缀的提升量。百分比为原始比例×100；本工艺不提高最大抗性，也不保证更强。',
        'facts': facts, 'links': [
            {'label': '四抗规则与阶级、后缀取舍', 'href': '../RESISTANCE_TARGETED_REFORGE.zh-CN.md'},
            {'label': '本批范围与原始凭据', 'href': '../qa/v103-reference/README.md'},
            {'label': '真实事务报告', 'href': base + 'transactions-report.json'},
            {'label': '合法源存档', 'href': base + row['source_snapshot_file']},
            {'label': '保存并穿戴后的存档', 'href': base + row['snapshot_file']}]}


def entries():
    authority = load(QA / 'authority-fragment.json')
    report = load(ROOT / REPORT)
    assert report['schema'] == authority['schema'] == 53
    assert report['vocabulary'] == authority['vocabulary'] == 51
    assert report['failure_count'] == 0 and len(report['transactions']) == 14
    rows = {row['name']: row for row in report['transactions']}
    result = {}
    for operation, name in zip(IDS, PRIMARY):
        row = rows[name]
        rule = authority['operations'][operation]
        presentation = rule['presentation']
        assert presentation == row['presentation'] and row['operation'] == operation
        before, after = load(TX / row['source_snapshot_file']), load(TX / row['snapshot_file'])
        uid = row['crafted']['id']
        assert before['items'][uid]['payload'] == row['generation']['source'] == row['quote']['source_instance']
        assert after['items'][uid]['payload'] == row['crafted']
        assert before['version'] == after['version'] == 53
        assert balance(before) - balance(after) == row['cost'] == row['quote']['cost']['calibration_shard']
        item = dict(rule['constraints'])
        item.update({'name': presentation['label'] + ' · ' + presentation['target_label'],
            'kind': 'operation', 'description': presentation['description'], 'risk': presentation['risk'],
            'rule': rule['rule'], 'rules_version': row['quote']['rules_version'],
            'example_note': '这是实际模型报价、确认和原子保存的已完成示例。源装备由真实目录生成，费用与余额来自合法源/结果存档；保留原UID，全部词缀重新生成。模型报告覆盖重新穿戴与重载，不预告玩家下一次随机结果。',
            'example': {'source': row['generation']['source'],
                'before_definition': authority['definitions'][name]['before'], 'quote': row['quote'],
                'balance_before': balance(before), 'balance_after': balance(after),
                'revision_before': before['crafting']['revision'], 'revision_after': row['result']['revision'],
                'after_instance': row['crafted'], 'after_definition': authority['definitions'][name]['after'],
                'full_candidate_valid': True, 'save_version': after['version'],
                'actual_model_record': name, 'actual_model_report': REPORT,
                'generation': row['generation'], 'transaction_result': row['result'],
                'profiles': row['profiles'], 'source_snapshot': str((TX / row['source_snapshot_file']).relative_to(ROOT)),
                'equipped_snapshot': str((TX / row['snapshot_file']).relative_to(ROOT))},
            'evidence': evidence(row)})
        result[operation] = item
    return result


def append_entries(raw, values):
    start, end = spans(raw)['crafting']
    crafting = raw[start:end]
    assert not set(values) & tokens(crafting).keys()
    closing = crafting.rfind('}')
    body = crafting[:closing].rstrip()
    for key, value in values.items():
        encoded = json.dumps(value, ensure_ascii=False, indent='\t', sort_keys=True).replace('\n', '\n\t\t')
        body += ',\n\t\t' + json.dumps(key) + ': ' + encoded
    return raw[:start] + body + '\n\t}' + raw[end:]


def main():
    before = baseline('docs/reference/catalog.json').decode()
    assert (REF / 'catalog.json').read_text() == before, 'Do not overwrite another projection'
    assert not (QA / 'projection.json').exists(), 'Retain the original projection record'
    values = entries()
    current = append_entries(before, values)
    expected = json.loads(before)
    expected['crafting'].update(values)
    assert json.loads(current) == expected
    builder = module('builder_v103', ROOT / 'tools/build_reference.py')
    rendered = builder.build(expected, load(REF / 'art/manifest.json'))
    (QA / 'new-crafting-entries.json').write_text(json.dumps(values, ensure_ascii=False, indent=2) + '\n')
    (REF / 'catalog.json').write_text(current)
    (REF / 'index.html').write_text(rendered)
    record = {'baseline_commit': BASE, 'added_operations': IDS, 'primary_actual_records': PRIMARY,
        'baseline_catalog_sha256': sha(before.encode()), 'catalog_sha256': sha(current.encode()),
        'html_sha256': sha(rendered.encode()), 'authority_sha256': sha((QA / 'authority-fragment.json').read_bytes()),
        'model_report_sha256': sha((ROOT / REPORT).read_bytes()),
        'method': 'Append four new crafting value spans only. All prior top-level/nested tokens and numerical spellings are retained. Quote, result, source/output instances and profiles are projected directly from the original model JSON; only catalog definitions and metadata use the read-only authority export.'}
    (QA / 'projection.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(record, indent=2))


if __name__ == '__main__': main()
