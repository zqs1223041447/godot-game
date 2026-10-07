#!/usr/bin/env python3
"""Merge only the bounded native map export, preserving all historical JSON bytes."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'docs/reference/catalog.json'
FRAGMENT = ROOT / 'docs/qa/v119-reference/ruins-garden-fragment.json'


def member_span(text, path, start=0):
    """Locate a JSON member structurally, without reserializing its neighbours."""
    decoder = json.JSONDecoder()
    cursor = start
    while text[cursor].isspace():
        cursor += 1
    if text[cursor] != '{':
        raise ValueError('Expected a JSON object')
    cursor += 1
    while True:
        while text[cursor].isspace() or text[cursor] == ',':
            cursor += 1
        if text[cursor] == '}':
            raise KeyError(path)
        key, cursor = decoder.raw_decode(text, cursor)
        while text[cursor].isspace():
            cursor += 1
        if text[cursor] != ':':
            raise ValueError('Expected a JSON member separator')
        cursor += 1
        while text[cursor].isspace():
            cursor += 1
        value_start = cursor
        _, cursor = decoder.raw_decode(text, cursor)
        if key == path[0]:
            return member_span(text, path[1:], value_start) if len(path) > 1 else (value_start, cursor)


def merge(text, fragment):
    if set(fragment) != {'ruins_garden'}:
        raise ValueError('Expected exactly the ruins_garden fragment')
    entry = fragment['ruins_garden']
    if entry['id'] != 'ruins_garden' or entry.get('native_entry') is not True or entry.get('test_available') is not False:
        raise ValueError('Expected a formal-only native map')
    before = json.loads(text)
    maps = before['exploration_maps']['maps']
    value = json.dumps(entry, ensure_ascii=False, sort_keys=True, indent='\t').replace('\n', '\n\t\t\t')
    if 'ruins_garden' in maps:
        start, end = member_span(text, ['exploration_maps', 'maps', 'ruins_garden'])
        result = text[:start] + value + text[end:]
    else:
        start, end = member_span(text, ['exploration_maps', 'maps'])
        insertion = text.rfind('\n', start, end)
        result = text[:insertion] + ',\n\t\t\t"ruins_garden": ' + value + text[insertion:]
    expected = json.loads(text)
    expected['exploration_maps']['maps']['ruins_garden'] = entry
    if json.loads(result) != expected:
        raise ValueError('Merge changed unrelated catalog data')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fragment', type=Path, default=FRAGMENT)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    before = CATALOG.read_text(encoding='utf-8')
    result = merge(before, json.loads(args.fragment.read_text(encoding='utf-8')))
    if args.check:
        if json.loads(before) != json.loads(result):
            raise SystemExit('Native map fragment differs from the catalog')
        print('Native map catalog matches bounded export')
    else:
        CATALOG.write_text(result, encoding='utf-8')
        print('Merged only exploration_maps.maps.ruins_garden')


if __name__ == '__main__':
    main()
