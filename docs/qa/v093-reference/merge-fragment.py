#!/usr/bin/env python3
"""Bounded raw-token catalog merge. Never load or call the old Godot exporter."""
import hashlib
import importlib.util
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'
BASE = '897dbfc'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def baseline(path): return subprocess.check_output(['git', 'show', BASE + ':' + path], cwd=ROOT)


def tokens(raw):
    decoder = json.JSONDecoder(); cursor = 1; result = {}
    while True:
        while raw[cursor].isspace(): cursor += 1
        if raw[cursor] == '}': return result
        key, cursor = decoder.raw_decode(raw, cursor)
        while raw[cursor].isspace(): cursor += 1
        assert raw[cursor] == ':'; cursor += 1
        while raw[cursor].isspace(): cursor += 1
        start = cursor; _, cursor = decoder.raw_decode(raw, cursor)
        result[key] = raw[start:cursor]
        while raw[cursor].isspace(): cursor += 1
        if raw[cursor] == ',': cursor += 1
        else:
            assert raw[cursor] == '}'; return result


def encoded(value, level):
    return json.dumps(value, ensure_ascii=False, indent='\t', sort_keys=True).replace('\n', '\n' + '\t' * (level + 1))


def compose(raw, replacements, level):
    values = tokens(raw); values.update(replacements); indent = '\t' * (level + 1)
    return '{\n' + ',\n'.join(indent + json.dumps(k) + ': ' + v for k, v in sorted(values.items())) + '\n' + '\t' * level + '}'


def replace(raw, path, value, level=0):
    key, *rest = path
    return compose(raw, {key: replace(tokens(raw)[key], rest, value, level+1) if rest else encoded(value, level)}, level)


def append_value(raw, path, value, level=0):
    key, *rest = path
    if rest: return compose(raw, {key: append_value(tokens(raw)[key], rest, value, level+1)}, level)
    old = tokens(raw)[key]
    assert old.endswith(']') and isinstance(json.loads(old), list)
    # All previous array-entry tokens, including float spellings, stay exact.
    new = old[:-1].rstrip() + ',\n' + '\t' * (level+2) + encoded(value, level+1) + '\n' + '\t' * (level+1) + ']'
    return compose(raw, {key: new}, level)


def module():
    spec = importlib.util.spec_from_file_location('build_reference', ROOT/'tools/build_reference.py')
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value


def main():
    before = baseline('docs/reference/catalog.json').decode()
    assert (REF/'catalog.json').read_text() == before, 'Only merge the approved baseline once'
    fragment = json.loads((QA/'chaos-defense-fragment.json').read_text())
    old = json.loads(before); current = before
    changed = []
    def update(path, value):
        nonlocal current
        current = replace(current, path.split('/'), value); changed.append(path)
    for key in ['game_version', 'save_version', 'current_loot_profile_id', 'current_loot_profile']:
        if old[key] != fragment[key]: update(key, fragment[key])
    rule = dict(fragment['chaos_defense'])
    # Reuse Main JSON floats directly, avoiding a second Godot decimal roundtrip.
    main_report = json.loads((ROOT/rule['actual_main_report']['path']).read_text())
    rule['actual_main_receipts'] = main_report['receipts']
    update('chaos_defense', rule)
    update('affixes/ring_voidward', fragment['affix'])
    update('equipment_pools/build_nine_slot_v51', fragment['new_pool'])
    update('loot_profiles/canonical_v51', fragment['current_loot_profile'])
    update('equipment/nine_slot_etched_ring/eligible_affixes', fragment['ring_eligible_affixes'])
    for affix in fragment['new_pool']['affix_ids']:
        if affix == 'ring_voidward': continue
        path = ['affixes', affix, 'pools']
        current = append_value(current, path, 'build_nine_slot_v51'); changed.append('/'.join(path))
    update('monsters/chaos_guard', fragment['monster'])
    update('monster_attacks/locked_circle_chaos', fragment['attack'])
    path = ['town_maps', 'options', 'special_modifiers']
    current = append_value(current, path, fragment['special']); changed.append('/'.join(path)+'/-')
    preserved = [key for key, value in tokens(before).items() if tokens(current)[key] == value]
    proof = {'baseline_commit': BASE, 'baseline_catalog_sha256': sha(before.encode()),
        'catalog_sha256': sha(current.encode()), 'fragment_sha256': sha((QA/'chaos-defense-fragment.json').read_bytes()),
        'changed_paths': changed, 'preserved_raw_top_level': preserved,
        'method': 'Only approved paths replaced; all unrelated dictionary tokens and existing special-array entries retain original bytes.'}
    (REF/'catalog.json').write_text(current)
    (QA/'catalog-format-preservation.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2)+'\n')
    builder = module()
    art = json.loads((REF/'art/manifest.json').read_text())
    (REF/'index.html').write_text(builder.build(json.loads(current), art))
    print('Merged bounded chaos fragment; preserved', len(preserved), 'complete raw top-level sections')


if __name__ == '__main__': main()
