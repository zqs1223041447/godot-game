#!/usr/bin/env python3
"""Merge one current corridor encounter rule and its map description; preserve all examples."""
import json
from pathlib import Path
from merge_ruins_garden_reference import member_span
ROOT=Path(__file__).resolve().parents[1]
QA=ROOT/'docs/qa/ruins-corridor-frost'
def merge(text,fragment):
    expected=json.loads(text)
    expected['ruins_corridor_frost']=fragment
    expected['exploration_maps']['maps']['broken_ruins']['description']=fragment['description']
    path=['exploration_maps','maps','broken_ruins','description']
    start,end=member_span(text,path)
    text=text[:start]+json.dumps(fragment['description'],ensure_ascii=False)+text[end:]
    encoded=json.dumps(fragment,ensure_ascii=False,sort_keys=True,indent='\t').replace('\n','\n\t')
    if 'ruins_corridor_frost' in json.loads(text):
        start,end=member_span(text,['ruins_corridor_frost']);text=text[:start]+encoded+text[end:]
    else:
        at=text.rfind('\n}')
        assert at>=0
        text=text[:at]+',\n\t"ruins_corridor_frost": '+encoded+text[at:]
    assert json.loads(text)==expected
    return text
if __name__=='__main__':
    path=ROOT/'docs/reference/catalog.json'
    path.write_text(merge(path.read_text(),json.loads((QA/'reference-fragment.json').read_text())))
    print('Merged current Ruins corridor encounter and one description; old examples unchanged')
