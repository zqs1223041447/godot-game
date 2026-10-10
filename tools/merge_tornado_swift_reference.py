"""Bounded existing projectile support/gem refresh, retaining old example rows."""
import argparse, json
from pathlib import Path
from merge_ruins_garden_reference import member_span

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--support', choices=['swift_projectiles','heavy_projectiles'], default='swift_projectiles')
parser.add_argument('--qa', type=Path, default=ROOT / 'docs/qa/tornado-swift')
args = parser.parse_args()
SUPPORT = args.support
QA = args.qa
catalog = ROOT / 'docs/reference/catalog.json'
text = catalog.read_text()
before = json.loads(text)
fragment = json.loads((QA / 'reference-fragment.json').read_text())
changes = [
    (('supports', SUPPORT), fragment['support']),
    (('canonical', 'gem_definitions', 'support:'+SUPPORT), fragment['gem']),
    (('skills', 'tornado', 'compatible_supports'), fragment['compatible']),
    (('support_program_examples', SUPPORT, 'examples'),
     dict(before['support_program_examples'][SUPPORT]['examples'], tornado=fragment['program_example'])),
]
for config, added in fragment['examples'].items():
    old = before['skills']['tornado']['examples'][config]
    existing = {tuple(row['supports']): row for row in old}
    new_rows = []
    for row in added:
        key = tuple(row['supports'])
        if key in existing: assert existing[key] == row
        else: new_rows.append(row)
    changes.append((('skills', 'tornado', 'examples', config), old + new_rows))
expected = json.loads(text)
spans = []
for path, value in changes:
    parent = expected
    for key in path[:-1]: parent = parent[key]
    parent[path[-1]] = value
    start, end = member_span(text, path)
    if path[:3] == ('skills', 'tornado', 'examples'):
        old_rows = before['skills']['tornado']['examples'][path[-1]]
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
print('Updated '+SUPPORT+' metadata and new tornado examples; other catalog sections preserved')
