"""Only refresh the existing swift support, gem and tornado examples."""
import json
from pathlib import Path
from merge_ruins_garden_reference import member_span

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / 'docs/qa/tornado-swift'
catalog = ROOT / 'docs/reference/catalog.json'
text = catalog.read_text()
before = json.loads(text)
fragment = json.loads((QA / 'reference-fragment.json').read_text())
changes = [
    (('supports', 'swift_projectiles'), fragment['support']),
    (('canonical', 'gem_definitions', 'support:swift_projectiles'), fragment['gem']),
    (('skills', 'tornado', 'compatible_supports'), fragment['compatible']),
    (('support_program_examples', 'swift_projectiles', 'examples'),
     dict(before['support_program_examples']['swift_projectiles']['examples'], tornado=fragment['program_example'])),
]
for config, added in fragment['examples'].items():
    old = before['skills']['tornado']['examples'][config]
    retained = [r for r in old if 'swift_projectiles' not in r['supports']]
    changes.append((('skills', 'tornado', 'examples', config), retained + added))
expected = json.loads(text)
spans = []
for path, value in changes:
    parent = expected
    for key in path[:-1]: parent = parent[key]
    parent[path[-1]] = value
    start, end = member_span(text, path)
    if path[:3] == ('skills', 'tornado', 'examples'):
        old_rows = before['skills']['tornado']['examples'][path[-1]]
        if any('swift_projectiles' in row['supports'] for row in old_rows):
            assert old_rows == value
            continue
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
print('Updated swift metadata and new tornado examples; other catalog sections preserved')
