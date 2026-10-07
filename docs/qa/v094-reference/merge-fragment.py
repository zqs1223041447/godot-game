#!/usr/bin/env python3
"""One bounded raw-token merge from c5690b9; no historical exporter or asset generator."""
import hashlib
import importlib.util
import json
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
QA=Path(__file__).resolve().parent
REF=ROOT/'docs/reference'
BASE='c5690b9'

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


def expected_data(old, fragment):
    result=json.loads(json.dumps(old,ensure_ascii=False))
    result['save_version']=fragment['save_version']
    result['supports']['encircling_cleave']=fragment['support']
    result['support_program_examples']['encircling_cleave']=fragment['support_program_example']
    result['skills']['cleave']['compatible_supports']=fragment['cleave_compatible_supports']
    rule=dict(fragment['encircling_cleave'])
    # Keep real Main receipt decimals from its original JSON, with no Godot roundtrip.
    accepted=json.loads((ROOT/rule['actual_main_report']['path']).read_text())
    rule['actual_main_samples']=accepted['samples']
    result['encircling_cleave']=rule
    return result


def main():
    before=baseline('docs/reference/catalog.json').decode()
    assert (REF/'catalog.json').read_text()==before, 'Only merge approved baseline once'
    fragment=json.loads((QA/'encircling-cleave-fragment.json').read_text())
    old=json.loads(before);expected=expected_data(old,fragment)
    assert fragment['game_version']==old['game_version']=='0.87.0'
    assert fragment['cleave_compatible_supports']==old['skills']['cleave']['compatible_supports']+['encircling_cleave']
    current=before;paths=[]
    for path,value in [('save_version',fragment['save_version']),('supports/encircling_cleave',fragment['support']),('support_program_examples/encircling_cleave',fragment['support_program_example']),('encircling_cleave',expected['encircling_cleave'])]:
        current=replace(current,path.split('/'),value);paths.append(path)
    path=['skills','cleave','compatible_supports']
    current=append_value(current,path,'encircling_cleave');paths.append('/'.join(path)+'/-')
    assert json.loads(current)==expected
    builder=module();art=json.loads((REF/'art/manifest.json').read_text())
    assert builder.build(old,art)==baseline('docs/reference/index.html').decode(), 'Prior catalog rendering must remain identical'
    source=ROOT/expected['encircling_cleave']['icon_source'].removeprefix('res://')
    target=REF/expected['encircling_cleave']['icon_file']
    assert sha(source.read_bytes())==expected['encircling_cleave']['icon_sha256']
    assert not target.exists(),'Only one new icon copy'
    target.write_bytes(source.read_bytes())
    (REF/'catalog.json').write_text(current)
    (REF/'index.html').write_text(builder.build(json.loads(current),art))
    retained=[k for k,v in tokens(before).items() if tokens(current)[k]==v]
    proof={'baseline_commit':BASE,'baseline_catalog_sha256':sha(before.encode()),'catalog_sha256':sha(current.encode()),'fragment_sha256':sha((QA/'encircling-cleave-fragment.json').read_bytes()),'changed_paths':paths,'preserved_raw_top_level':retained,'preserved_raw_top_level_count':len(retained),'method':'Only five paths changed; original nested tokens, float spellings and compatible-support entries remain. Main samples reuse original JSON. One source PNG copied without processing.'}
    (QA/'catalog-format-preservation.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2)+'\n')
    print('Merged encircling-cleave fragment; preserved',len(retained),'complete raw top-level sections')


if __name__=='__main__':main()
