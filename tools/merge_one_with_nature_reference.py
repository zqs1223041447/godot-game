#!/usr/bin/env python3
"""Merge one source effect, its directly linked route and current provenance."""
import json
from pathlib import Path
from merge_ruins_garden_reference import member_span

ROOT = Path(__file__).resolve().parents[1]
LINE = '24% increased Elemental Damage with Attack Skills'
QA = ROOT / 'docs/qa/one-with-nature-reference'


def merge(text, fragment):
    before = json.loads(text)
    assert fragment['save_version'] == fragment['source_policy'] == 56
    assert fragment['source_sha256'] == before['source_tree']['source_sha256']
    previous = before['source_tree']['nodes']['15842']
    node = fragment['node']
    assert node['id'] == '15842' and node['execution']['status'] == 'full'
    assert node['execution']['unsupported'] == []
    assert {k: v for k, v in node.items() if k not in {'execution', 'ordinary_reachable_class_ids'}} == {k: v for k, v in previous.items() if k not in {'execution', 'ordinary_reachable_class_ids'}}
    assert fragment['localized_node']['name'] == '与自然合一'
    assert fragment['localized_line']['text'] == '攻击技能造成的元素伤害提高24%'
    assert fragment['localized_line']['status']['implemented']
    assert node['ordinary_reachable_class_ids'] == fragment['linked_existing_node']['ordinary_reachable_class_ids'] == list(range(7))
    assert fragment['linked_existing_node']['id'] == '18670'
    changes = [(('save_version',),56), (('source_tree','source_policy'),56),
               (('source_tree','nodes','15842'),node),
               (('source_tree','nodes','18670','ordinary_reachable_class_ids'),list(range(7))),
               (('source_tree_localization','nodes','15842'),fragment['localized_node']),
               (('source_tree_localization','lines',LINE),fragment['localized_line']),
               (('one_with_nature',),fragment['one_with_nature'])]
    expected = json.loads(text)
    spans = []
    for path, value in changes:
        parent = expected
        for key in path[:-1]: parent = parent[key]
        parent[path[-1]] = value
        encoded = json.dumps(value,ensure_ascii=False,sort_keys=True,indent='\t').replace('\n','\n'+'\t'*len(path))
        if path == ('one_with_nature',) and 'one_with_nature' not in before:
            end = text.rfind('\n}')
            assert end > 0
            spans.append((end,end,',\n\t"one_with_nature": '+encoded))
        else:
            start,end = member_span(text,path)
            spans.append((start,end,encoded))
    for start,end,value in sorted(spans,reverse=True): text = text[:start]+value+text[end:]
    assert json.loads(text) == expected, 'Unrelated catalog data changed'
    assert expected['canonical'] == before['canonical'], 'Historical canonical47 snapshot changed'
    return text


if __name__ == '__main__':
    catalog = ROOT / 'docs/reference/catalog.json'
    catalog.write_text(merge(catalog.read_text(),json.loads((QA/'fragment.json').read_text())))
    print('Merged exact15842, reachable18670 and current56 provenance only')
