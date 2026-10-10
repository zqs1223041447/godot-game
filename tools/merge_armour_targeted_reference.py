#!/usr/bin/env python3
"""Append one crafting entry and its metadata without rerolling prior examples."""
import json
from pathlib import Path
from merge_ruins_garden_reference import member_span
ROOT=Path(__file__).resolve().parents[1]
QA=ROOT/'docs/qa/armour-targeted-reforge'
OP='targeted_reforge_armour'
def merge(text,fragment):
    before=json.loads(text);expected=json.loads(text)
    for path,value in [(('crafting',OP),fragment['operation']),(('crafting','calibration_shard','rules','operations',OP),fragment['rule'])]:
        target=expected
        for key in path[:-1]:target=target[key]
        target[path[-1]]=value
        current=json.loads(text);parent=current
        for key in path[:-1]:parent=parent[key]
        encoded=json.dumps(value,ensure_ascii=False,sort_keys=True,indent='\t').replace('\n','\n'+'\t'*len(path))
        if path[-1] in parent:
            start,end=member_span(text,list(path));text=text[:start]+encoded+text[end:]
        else:
            start,end=member_span(text,list(path[:-1]));insert=text.rfind('\n',start,end)
            text=text[:insert]+',\n'+'\t'*len(path)+json.dumps(path[-1])+': '+encoded+text[insert:]
    assert json.loads(text)==expected
    return text
if __name__=='__main__':
    path=ROOT/'docs/reference/catalog.json'
    path.write_text(merge(path.read_text(),json.loads((QA/'reference-fragment.json').read_text())))
    print('Only armour craft entry and corresponding material metadata appended')
