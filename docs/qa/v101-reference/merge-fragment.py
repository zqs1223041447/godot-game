#!/usr/bin/env python3
"""Replace only current Ginkgo metadata and add its separately named policy."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'
BASE = 'bdea0872'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def baseline(path): return subprocess.check_output(['git', 'show', BASE + ':' + path], cwd=ROOT)


def spans(raw):
    decoder = json.JSONDecoder(); cursor = 1; result = {}
    while True:
        while raw[cursor].isspace(): cursor += 1
        if raw[cursor] == '}': return result
        key, cursor = decoder.raw_decode(raw, cursor)
        while raw[cursor].isspace(): cursor += 1
        assert raw[cursor] == ':'; cursor += 1
        while raw[cursor].isspace(): cursor += 1
        start = cursor; _, cursor = decoder.raw_decode(raw, cursor)
        result[key] = (start, cursor)
        while raw[cursor].isspace(): cursor += 1
        if raw[cursor] == ',': cursor += 1
        else:
            assert raw[cursor] == '}'; return result


def tokens(raw): return {key: raw[start:end] for key, (start, end) in spans(raw).items()}


def encoded(value, level):
    return json.dumps(value, ensure_ascii=False, indent='\t', sort_keys=True).replace('\n', '\n' + '\t' * (level + 1))


def replace(raw, path, value, level=0):
    key, *rest = path
    start, end = spans(raw)[key]
    new = replace(raw[start:end], rest, value, level + 1) if rest else encoded(value, level)
    return raw[:start] + new + raw[end:]


def append_policy(raw, value):
    assert 'ginkgo_inner_outer' not in spans(raw)
    closing = raw.rfind('}')
    body = raw[:closing].rstrip()
    return body + ',\n\t"ginkgo_inner_outer": ' + encoded(value, 0) + '\n' + raw[closing:]


def module():
    spec = importlib.util.spec_from_file_location('build_reference_v101', ROOT / 'tools/build_reference.py')
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result); return result


def expected_data(old, fragment):
    result = json.loads(json.dumps(old, ensure_ascii=False))
    current = result['exploration_maps']['maps']['ginkgo_arcade']
    current['boss_definition'] = fragment['boss_definition']
    current['description'] = fragment['description']
    rule = json.loads(json.dumps(fragment['ginkgo_inner_outer'], ensure_ascii=False))
    report = json.loads((ROOT / rule['actual_main_report']['path']).read_text())
    example = report['groups'][rule['example_group']]
    # Godot JSON reparsing can shift a double by one ULP. Preserve original receipt values.
    for key, value in {'example_source': report['entries'][0]['boss'], 'example_policy': report['entries'][0]['policy'],
            'example_events': example['trace'], 'example_initial_attack': example['initial_attack'],
            'example_outer_snapshot': example['outer_snapshot']}.items():
        rule[key] = value
    result['ginkgo_inner_outer'] = rule
    return result


def main():
    before = baseline('docs/reference/catalog.json').decode()
    existing = (REF / 'catalog.json').read_bytes()
    if existing != before.encode():
        proof = json.loads((QA / 'first-merge-preservation.json').read_text())
        assert sha(existing) == proof['catalog_sha256'] and proof['baseline_commit'] == BASE, 'Only correct the preserved first projection'
    fragment = json.loads((QA / 'ginkgo-inner-outer-fragment.json').read_text())
    old = json.loads(before); expected = expected_data(old, fragment)
    assert fragment['game_version'] == old['game_version']
    assert fragment['save_version'] == old['save_version']
    current = before; paths = []
    for name in ['boss_definition', 'description']:
        path = ['exploration_maps', 'maps', 'ginkgo_arcade', name]
        current = replace(current, path, fragment[name]); paths.append('/'.join(path))
    current = append_policy(current, expected['ginkgo_inner_outer']); paths.append('ginkgo_inner_outer')
    assert json.loads(current) == expected
    builder = module(); art = json.loads((REF / 'art/manifest.json').read_text())
    assert builder.build(old, art) == baseline('docs/reference/index.html').decode(), 'Old input must render byte-identically'
    (REF / 'catalog.json').write_text(current)
    (REF / 'index.html').write_text(builder.build(json.loads(current), art))
    old_tokens, new_tokens = tokens(before), tokens(current)
    retained = [key for key in old_tokens if old_tokens[key] == new_tokens[key]]
    result = {'baseline_commit': BASE, 'baseline_catalog_sha256': sha(before.encode()),
        'catalog_sha256': sha(current.encode()), 'fragment_sha256': sha((QA / 'ginkgo-inner-outer-fragment.json').read_bytes()),
        'changed_paths': paths, 'preserved_raw_top_level': retained, 'preserved_raw_top_level_count': len(retained),
        'method': 'Two exact value-span replacements and one appended policy. All surrounding bytes, unrelated values, historical Ginkgo archive and numeric token spellings retained. Main example dictionaries projected directly from original report JSON to avoid Godot double roundtrip shifts.'}
    (QA / 'catalog-format-preservation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print('Merged current Ginkgo only; preserved', len(retained), 'complete raw top-level sections')


if __name__ == '__main__': main()
