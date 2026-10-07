#!/usr/bin/env python3
"""Insert one exploration section into exact eb487876 bytes; preserve old numeric tokens."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'
BASE = 'eb487876'

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
    fragment_raw = (QA / 'exploration-fragment.json').read_bytes()
    fragment = json.loads(fragment_raw)
    assert set(fragment) == {'game_version', 'exploration_maps'}
    assert fragment['game_version'] == '0.86.0' and fragment['exploration_maps']['save_version'] == old['save_version'] == 50
    assert fragment['exploration_maps']['source_policy'] == 49
    assert 'exploration_maps' not in old
    fields = spans(before)
    changes = []
    for key in ['game_version']:
        _, start, end = fields[key]
        changes.append((start, end, json.dumps(fragment[key], ensure_ascii=False)))
    key = 'exploration_maps'
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
        if key in ['game_version']: continue
        _, a, b = current_fields[key]
        assert before[start:end] == after[a:b], key
        retained.append(key)
    assert (REF / 'source-tree-coverage.json').read_bytes() == baseline('docs/reference/source-tree-coverage.json')
    (REF / 'catalog.json').write_text(after)
    proof = {'baseline_commit': BASE, 'baseline_sha256': sha(raw), 'catalog_sha256': sha(after.encode()),
             'fragment_sha256': sha(fragment_raw), 'new_section': 'exploration_maps', 'splice_count': len(changes),
             'current_version_labels': {'game_version': [old['game_version'], fragment['game_version']],
                                        'save_version': [old['save_version'], old['save_version']]},
             'historical_raw_sections_preserved': retained, 'historical_raw_section_count': len(retained),
             'source_coverage_byte_preserved': True,
             'method': 'Insert one runtime fragment and replace only the game_version label in exact baseline bytes. No old catalog read by Godot; no old numerical token reformatted.'}
    with (QA / 'catalog-format-preservation.json').open('x') as handle:
        json.dump(proof, handle, ensure_ascii=False, indent=2)
        handle.write('\n')
    print(json.dumps(proof, ensure_ascii=False, indent=2))

if __name__ == '__main__': main()
