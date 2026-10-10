#!/usr/bin/env python3
"""Append one map special and its evidence; preserve all existing catalog values."""
import argparse
import json
from pathlib import Path
from merge_ruins_garden_reference import member_span

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'docs/reference/catalog.json'
FRAGMENT = ROOT / 'docs/qa/chaos-aegis/reference-fragment.json'


def value_span(text, path):
    start, end = 0, len(text)
    decoder = json.JSONDecoder()
    for key in path:
        if isinstance(key, str):
            start, end = member_span(text, [key], start)
        else:
            assert text[start] == '['
            cursor = start + 1
            for _ in range(key + 1):
                while text[cursor].isspace() or text[cursor] == ',':
                    cursor += 1
                start = cursor
                _, cursor = decoder.raw_decode(text, cursor)
            end = cursor
    return start, end


def merge(text, fragment):
    assert fragment['id'] == 'chaos_aegis' and fragment['integration_status'] == 'implemented'
    assert fragment['definition']['damage_types'] == ['chaos'] and fragment['chaos_cap'] == 0.75
    expected = json.loads(text)
    specials = expected['town_maps']['options']['special_modifiers']
    matching = [i for i, row in enumerate(specials) if row['id'] == 'chaos_aegis']
    assert len(matching) <= 1
    if matching:
        assert specials[matching[0]] == fragment['options']['test']
    else:
        start, end = member_span(text, ['town_maps', 'options', 'special_modifiers'])
        insertion = text.rfind('\n', start, end)
        value = json.dumps(fragment['options']['test'], ensure_ascii=False, sort_keys=True, indent='\t').replace('\n', '\n\t\t\t\t')
        text = text[:insertion] + ',\n\t\t\t\t' + value + text[insertion:]
        specials.append(fragment['options']['test'])
    # Only the new modifier's eligibility changes in existing tier tables.
    # Historical layouts, receipts and other modifier lists are not regenerated.
    for map_id, tiers in fragment['eligible_tiers'].items():
        roots = [['exploration_maps', 'maps', map_id]]
        if map_id in ('ginkgo_arcade', 'sunwell_terrace'):
            roots.append([map_id])
        for root in roots:
            for tier in tiers:
                path = root + ['tiers', tier - 1, 'eligible_special_ids']
                ids = expected
                for key in path:
                    ids = ids[key]
                if 'chaos_aegis' in ids:
                    continue
                start, end = value_span(text, path)
                insertion = text.rfind('\n', start, end)
                assert insertion > start and ids
                text = text[:insertion] + ',\n' + '\t' * (len(path) + 1) + '"chaos_aegis"' + text[insertion:]
                ids.append('chaos_aegis')
    value = json.dumps(fragment, ensure_ascii=False, sort_keys=True, indent='\t').replace('\n', '\n\t\t')
    if 'chaos_aegis' in expected['town_maps']:
        start, end = member_span(text, ['town_maps', 'chaos_aegis'])
        text = text[:start] + value + text[end:]
    else:
        start, end = member_span(text, ['town_maps'])
        insertion = text.rfind('\n', start, end)
        text = text[:insertion] + ',\n\t\t"chaos_aegis": ' + value + text[insertion:]
    expected['town_maps']['chaos_aegis'] = fragment
    assert json.loads(text) == expected, 'Unrelated catalog values changed'
    return text


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    before = TARGET.read_text()
    result = merge(before, json.loads(FRAGMENT.read_text()))
    if args.check:
        assert result == before, 'Current catalog differs from bounded export'
        print('Chaos aegis catalog matches bounded export byte-for-byte')
    else:
        TARGET.write_text(result)
        print('Merged one special option, its tier eligibility and town_maps.chaos_aegis')
