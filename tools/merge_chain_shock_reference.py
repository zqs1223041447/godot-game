"""Append or refresh one verified build section, retaining all historical bytes."""
import json
from pathlib import Path
from merge_ruins_garden_reference import member_span

ROOT = Path(__file__).resolve().parents[1]
path = ROOT/'docs/reference/catalog.json'
fragment = json.loads((ROOT/'docs/qa/chain-shock-build/reference-fragment.json').read_text())
assert set(fragment)=={'chain_shock_build'}
text=path.read_text()
expected=json.loads(text)
key='chain_shock_build'
value=fragment[key]
encoded=json.dumps(value,ensure_ascii=False,sort_keys=True,indent='\t').replace('\n','\n\t')
if key in expected:
    start,end=member_span(text,(key,))
    text=text[:start]+encoded+text[end:]
else:
    text=text.rstrip()
    assert text.endswith('}')
    text=text[:-1].rstrip()+',\n\t'+json.dumps(key)+': '+encoded+'\n}\n'
expected[key]=value
assert json.loads(text)==expected
path.write_text(text)
print('Only chain_shock_build section updated')
