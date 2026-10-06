#!/usr/bin/env python3
"""Insert one new map into exact f18cf07 bytes; preserve old numeric tokens."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'
BASE = 'f18cf07'

def sha(data):
    return hashlib.sha256(data).hexdigest()

def baseline(path):
    return subprocess.check_output(['git', 'show', BASE + ':' + path], cwd=ROOT)

def spans(text, start=0):
    decoder = json.JSONDecoder()
    cursor = start + 1
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

def main():
    raw = baseline('docs/reference/catalog.json')
    before = raw.decode()
    old = json.loads(before)
    fragment_raw = (QA / 'ginkgo-fragment.json').read_bytes()
    fragment = json.loads(fragment_raw)
    assert set(fragment) == {'game_version', 'save_version', 'ginkgo_arcade'}
    assert fragment['game_version'] == '0.83.0' and fragment['save_version'] == 50
    assert fragment['ginkgo_arcade']['source_policy'] == 49
    assert 'ginkgo_arcade' not in old
    fields = spans(before)
    changes = []
    for key in ['game_version', 'save_version']:
        _, start, end = fields[key]
        changes.append((start, end, json.dumps(fragment[key], ensure_ascii=False)))
    key = 'ginkgo_arcade'
    following = min(name for name in fields if name > key)
    start = fields[following][0]
    content = json.dumps(fragment[key], ensure_ascii=False, indent='\t', sort_keys=True).replace('\n', '\n\t')
    changes.append((start, start, json.dumps(key) + ': ' + content + ',\n\t'))
    after = before
    for start, end, replacement in sorted(changes, reverse=True):
        after = after[:start] + replacement + after[end:]
    assert json.loads(after) == {**old, **fragment}
    current_fields = spans(after)
    retained = []
    for key, (_, start, end) in fields.items():
        if key in ['game_version', 'save_version']: continue
        _, a, b = current_fields[key]
        assert before[start:end] == after[a:b], key
        retained.append(key)
    assert (REF / 'source-tree-coverage.json').read_bytes() == baseline('docs/reference/source-tree-coverage.json')
    (REF / 'catalog.json').write_text(after)
    proof = {'baseline_commit': BASE, 'baseline_sha256': sha(raw), 'catalog_sha256': sha(after.encode()),
             'fragment_sha256': sha(fragment_raw), 'new_section': 'ginkgo_arcade', 'splice_count': len(changes),
             'current_version_labels': {'game_version': [old['game_version'], fragment['game_version']],
                                        'save_version': [old['save_version'], fragment['save_version']]},
             'historical_raw_sections_preserved': retained, 'historical_raw_section_count': len(retained),
             'source_coverage_byte_preserved': True,
             'method': 'Insert one runtime fragment and replace two top-level version labels in exact baseline bytes. No old catalog read by Godot; no old numerical token reformatted.'}
    with (QA / 'catalog-format-preservation.json').open('x') as handle:
        json.dump(proof, handle, ensure_ascii=False, indent=2)
        handle.write('\n')
    print(json.dumps(proof, ensure_ascii=False, indent=2))

if __name__ == '__main__': main()
