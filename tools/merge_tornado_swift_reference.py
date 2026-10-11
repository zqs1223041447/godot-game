"""Bounded existing support/gem refresh, retaining old example rows."""
import argparse, json
from pathlib import Path
from merge_ruins_garden_reference import member_span

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--support', choices=['swift_projectiles','heavy_projectiles','inward_pull','ambush','lingering_chill'], default='swift_projectiles')
parser.add_argument('--qa', type=Path, default=ROOT / 'docs/qa/tornado-swift')
parser.add_argument('--skill', choices=['tornado','cleave','chain','nova','frost','shade_bolt'], default='tornado')
args = parser.parse_args()
SKILL = args.skill
assert (SKILL == 'tornado' and args.support in ['swift_projectiles','heavy_projectiles']) or (SKILL in ['cleave','frost','shade_bolt'] and args.support == 'inward_pull') or (SKILL == 'chain' and args.support == 'ambush') or (SKILL == 'nova' and args.support == 'lingering_chill')
SUPPORT = args.support
QA = args.qa
catalog = ROOT / 'docs/reference/catalog.json'
text = catalog.read_text()
before = json.loads(text)
fragment = json.loads((QA / 'reference-fragment.json').read_text())
changes = [
    (('supports', SUPPORT), fragment['support']),
    (('canonical', 'gem_definitions', 'support:'+SUPPORT), fragment['gem']),
    (('skills', SKILL, 'compatible_supports'), fragment['compatible']),
    (('support_program_examples', SUPPORT, 'examples'),
     dict(before['support_program_examples'][SUPPORT]['examples'], **{SKILL:fragment['program_example']})),
]
for config, added in fragment['examples'].items():
    old = before['skills'][SKILL]['examples'][config]
    existing = {tuple(row['supports']): row for row in old}
    new_rows = []
    for row in added:
        key = tuple(row['supports'])
        if key in existing: assert existing[key] == row
        else: new_rows.append(row)
    changes.append((('skills', SKILL, 'examples', config), old + new_rows))
if SUPPORT == 'inward_pull':
    for field in ['skills','direction','movement','snapshot','scope','damage_scope','risk','statuses','migration','source_policy','equipment_vocabulary','test_offer']:
        changes.append((('inward_pull',field),fragment['inward_pull'][field]))
    changes.append((('inward_pull','examples'),dict(before['inward_pull']['examples'],**{SKILL:fragment['inward_pull']['examples'][SKILL]})))
if SUPPORT == 'ambush':
    for field in ['skills','snapshot','geometry','statuses','damage_scope','provenance','migration','source_policy','equipment_vocabulary','test_offer']:
        changes.append((('ambush',field),fragment['ambush'][field]))
    for skill in ['nova','meteor']:
        assert before['ambush']['examples'][skill] == fragment['ambush']['examples'][skill]
    changes.append((('ambush','examples'),dict(before['ambush']['examples'],chain=fragment['ambush']['examples']['chain'])))
if SUPPORT == 'lingering_chill':
    for skill in ['frost','nova']:
        changes.append((('skills',skill,'capabilities'),fragment['native_slow'][skill]))
    changes.append((('skills','nova','slow_duration'),fragment['native_slow']['nova_base']))
expected = json.loads(text)
spans = []
for path, value in changes:
    parent = expected
    for key in path[:-1]: parent = parent[key]
    parent[path[-1]] = value
    old_parent = before
    for key in path[:-1]: old_parent = old_parent[key]
    if path[-1] not in old_parent:
        _, parent_end = member_span(text,path[:-1])
        end = parent_end-1
        start = end
        while text[start-1].isspace(): start -= 1
        encoded = ',\n'+'\t'*len(path)+json.dumps(path[-1])+': '+json.dumps(value,ensure_ascii=False)+'\n'+'\t'*(len(path)-1)
        spans.append((start,end,encoded))
        continue
    start, end = member_span(text, path)
    if path in [('ambush','examples'),('inward_pull','examples'),('support_program_examples',SUPPORT,'examples')]:
        old_examples = before
        for key in path: old_examples = old_examples[key]
        if old_examples == value: continue
        assert all(value[key] == row for key,row in old_examples.items())
        added = {key:row for key,row in value.items() if key not in old_examples}
        assert len(added) == 1
        key,row = next(iter(added.items()))
        encoded_row = json.dumps(row, ensure_ascii=False, sort_keys=True, indent='\t').replace('\n', '\n' + '\t' * (len(path) + 1))
        encoded = text[start:end-1].rstrip() + ',\n' + '\t' * (len(path) + 1) + json.dumps(key) + ': ' + encoded_row + '\n' + '\t' * len(path) + '}'
    elif path[:3] == ('skills', SKILL, 'examples'):
        old_rows = before['skills'][SKILL]['examples'][path[-1]]
        if old_rows == value: continue
        added = value[len(old_rows):]
        encoded_rows = []
        for row in added:
            encoded_rows.append('\t' * (len(path) + 1) + json.dumps(row, ensure_ascii=False, sort_keys=True, indent='\t').replace('\n', '\n' + '\t' * (len(path) + 1)))
        encoded = text[start:end-1].rstrip() + ',\n' + ',\n'.join(encoded_rows) + '\n' + '\t' * len(path) + ']'
    else:
        encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, indent='\t').replace('\n', '\n' + '\t' * len(path))
    spans.append((start, end, encoded))
for start, end, value in sorted(spans, reverse=True): text = text[:start] + value + text[end:]
assert json.loads(text) == expected
catalog.write_text(text)
print('Updated '+SUPPORT+' metadata and new '+SKILL+' examples; other catalog sections preserved')
