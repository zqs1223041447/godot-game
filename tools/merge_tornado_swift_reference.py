"""Bounded existing support/gem refresh, retaining old example rows."""
import argparse, json
from pathlib import Path
from merge_ruins_garden_reference import member_span

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--support', choices=['swift_projectiles','heavy_projectiles','inward_pull','ambush'], default='swift_projectiles')
parser.add_argument('--qa', type=Path, default=ROOT / 'docs/qa/tornado-swift')
parser.add_argument('--skill', choices=['tornado','cleave','chain'], default='tornado')
args = parser.parse_args()
SKILL = args.skill
assert (SKILL == 'tornado' and args.support in ['swift_projectiles','heavy_projectiles']) or (SKILL == 'cleave' and args.support == 'inward_pull') or (SKILL == 'chain' and args.support == 'ambush')
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
    for field in ['skills','direction','movement','snapshot','scope','damage_scope','risk','migration','source_policy','equipment_vocabulary','test_offer']:
        changes.append((('inward_pull',field),fragment['inward_pull'][field]))
    changes.append((('inward_pull','examples'),dict(before['inward_pull']['examples'],cleave=fragment['inward_pull']['examples']['cleave'])))
if SUPPORT == 'ambush':
    for field in ['skills','snapshot','geometry','statuses','damage_scope','provenance','migration','source_policy','equipment_vocabulary','test_offer']:
        changes.append((('ambush',field),fragment['ambush'][field]))
    for skill in ['nova','meteor']:
        assert before['ambush']['examples'][skill] == fragment['ambush']['examples'][skill]
    changes.append((('ambush','examples'),dict(before['ambush']['examples'],chain=fragment['ambush']['examples']['chain'])))
expected = json.loads(text)
spans = []
for path, value in changes:
    parent = expected
    for key in path[:-1]: parent = parent[key]
    parent[path[-1]] = value
    start, end = member_span(text, path)
    if path == ('ambush','examples'):
        if before['ambush']['examples'] == value: continue
        assert 'chain' not in before['ambush']['examples']
        chain = json.dumps(value['chain'], ensure_ascii=False, sort_keys=True, indent='\t').replace('\n', '\n' + '\t' * (len(path) + 1))
        encoded = text[start:end-1].rstrip() + ',\n' + '\t' * (len(path) + 1) + '"chain": ' + chain + '\n' + '\t' * len(path) + '}'
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
