#!/usr/bin/env python3
"""Verify a bounded jewel fragment against any current catalog, without replacing it."""
from __future__ import annotations
import hashlib
import json
import re
from pathlib import Path
from build_reference import ROOT, REF, build, merge_jewel_crafting_fragment


def verify() -> dict:
    fragment_path=ROOT/'docs/qa/v091-reference/jewel-crafting-fragment.json'
    fragment=json.loads(fragment_path.read_text())
    data=json.loads((REF/'catalog.json').read_text())
    original=json.dumps(data,ensure_ascii=False,sort_keys=True)
    merged=merge_jewel_crafting_fragment(data,fragment)
    assert json.dumps(data,ensure_ascii=False,sort_keys=True)==original
    assert {key:value for key,value in merged.items() if key!='jewel_crafting'}=={key:value for key,value in data.items() if key!='jewel_crafting'}
    rule=merged['jewel_crafting']
    assert rule['salvage_units']=={'magic':1,'rare':2}
    assert rule['reforge_costs']=={'magic':8,'rare':16}
    assert rule['affix_counts']=={'magic':{'min_prefixes':1,'max_prefixes':1,'suffixes':1},'rare':{'min_prefixes':1,'max_prefixes':2,'suffixes':2}}
    assert rule['quote_seconds']==120 and rule['save_version']==50
    example=rule['actual_main_example']
    assert example['whole_build_valid'] and example['exact_main_result_verified']
    for key in ['fixture','ui_log']:
        assert hashlib.sha256((ROOT/example[key]).read_bytes()).hexdigest()==example[key+'_sha256']
    assert example['balance_before']-example['balance_after']==example['cost']==8
    assert example['source']['id']==example['result']['id'] and example['source']['base']==example['result']['base']
    manifest=json.loads((REF/'art/manifest.json').read_text())
    # Remove only this fragment to compare against the unrelated catalog cards.
    without={key:value for key,value in data.items() if key!='jewel_crafting'}
    before_html=build(without,manifest)
    after_html=build(merged,manifest)
    pattern=r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
    before={match.group(1):match.group(0) for match in re.finditer(pattern,before_html,re.S)}
    after={match.group(1):match.group(0) for match in re.finditer(pattern,after_html,re.S)}
    expected={'jewels-'+base for base in rule['base_ids']}|{'currencies-'+key for key in data['currencies']}
    modified={key for key in before if before[key]!=after.get(key)}
    assert modified==expected,(modified,expected)
    assert set(after)-set(before)=={'rules-jewel_crafting'}
    assert set(before)<=set(after)
    card=after['rules-jewel_crafting']
    for rarity in ['magic','rare']:
        for operation,value in [('salvage',rule['salvage_units'][rarity]),('reforge',rule['reforge_costs'][rarity])]:
            assert f'data-jewel-craft="{operation}-{rarity}" data-value="{value}"' in card
    for base in rule['base_ids']:
        assert f'href="#jewels-{base}"' in card
        assert 'href="#rules-jewel_crafting"' in after['jewels-'+base]
    assert after['jewels-branchfinder']==before['jewels-branchfinder']
    for key in ['已插孔','待安置','结果可能相同或更差','120秒','测试数据','不是用户正式档']:
        assert key in card,key
    assert 'jewel_crafting' not in data or data['jewel_crafting']==rule
    Path('/tmp/v091-jewel-reference-preview.html').write_text(after_html)
    return {'ok':True,'fragment':str(fragment_path.relative_to(ROOT)),
            'fragment_sha256':hashlib.sha256(fragment_path.read_bytes()).hexdigest(),
            'unchanged_catalog_top_level_fields':len(without),'unrelated_cards_preserved':len(before)-len(modified),
            'modified_cards':sorted(modified),'added_cards':['rules-jewel_crafting'],
            'actual_main_fixture':example['fixture'],'actual_main_fixture_sha256':example['fixture_sha256'],
            'scope':'Static data, links and in-memory HTML only; existing catalog/index not written; browser rendering not claimed'}


if __name__=='__main__':
    print(json.dumps(verify(),ensure_ascii=False,indent=2))
