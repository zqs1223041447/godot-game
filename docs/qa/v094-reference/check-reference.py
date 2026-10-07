#!/usr/bin/env python3
"""Focused v94 data, Chinese search, links, values and exact preservation; no Godot rerun."""
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import struct
import subprocess
from html.parser import HTMLParser
ROOT=Path(__file__).resolve().parents[3]
QA=Path(__file__).resolve().parent
REF=ROOT/'docs/reference'
BASE='c5690b9'

def sha(raw):return hashlib.sha256(raw).hexdigest()
def baseline(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

class Page(HTMLParser):
    def __init__(self):super().__init__();self.ids=[];self.links=[];self.assets=[];self.values={}
    def handle_starttag(self,tag,pairs):
        attrs=dict(pairs)
        if 'id' in attrs:self.ids.append(attrs['id'])
        if 'href' in attrs:self.links.append(attrs['href'])
        if 'src' in attrs:self.assets.append(attrs['src'])
        if 'data-encircling-value' in attrs:
            key=attrs['data-encircling-value'];amount=float(attrs['data-value'])
            if key in self.values:assert self.values[key]==amount
            self.values[key]=amount

def main():
    merge=module('merge_v094',QA/'merge-fragment.py');builder=module('builder_v094',ROOT/'tools/build_reference.py')
    old_raw=baseline('docs/reference/catalog.json').decode();raw=(REF/'catalog.json').read_text()
    old=json.loads(old_raw);data=json.loads(raw);fragment=json.loads((QA/'encircling-cleave-fragment.json').read_text())
    assert data==merge.expected_data(old,fragment),'Only bounded fragment semantics may change'
    assert data['game_version']==old['game_version']=='0.87.0' and data['save_version']==52
    old_tokens,current_tokens=merge.tokens(old_raw),merge.tokens(raw)
    changed_sections={key for key in old_tokens if old_tokens[key]!=current_tokens[key]}
    assert changed_sections=={'save_version','supports','support_program_examples','skills'}
    retained=[key for key,token in old_tokens.items() if current_tokens[key]==token]
    assert len(retained)==84
    for section in ['supports','support_program_examples','skills']:
        a,b=merge.tokens(old_tokens[section]),merge.tokens(current_tokens[section])
        for key,token in a.items():
            if section=='skills' and key=='cleave':
                x,y=merge.tokens(token),merge.tokens(b[key])
                assert all(y[field]==value for field,value in x.items() if field!='compatible_supports')
                assert json.loads(y['compatible_supports'])==json.loads(x['compatible_supports'])+['encircling_cleave']
            else:assert b[key]==token,(section,key)
    html=(REF/'index.html').read_text();old_html=baseline('docs/reference/index.html').decode()
    cards=lambda text:{key:body for body,key in re.findall(r'(<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>)',text,re.S)}
    previous,current=cards(old_html),cards(html)
    new={'supports-encircling_cleave','rules-encircling_cleave'}
    assert set(current)-set(previous)==new and set(previous)<=set(current)
    schema={'rules-source_tree','rules-source_monster_movement','rules-source_monster_damage_life','rules-source_monster_shield_recharge','rules-frost_lock','rules-elemental_conversion','rules-physical_fire_conversion','rules-equipment','rules-exploration_maps'}
    intended=schema|{'skills-cleave','rules-ember_proliferation'}
    changed={key for key in previous if previous[key]!=current[key]}
    assert changed==intended,(changed-intended,intended-changed)
    for key in schema:
        expected=previous[key].replace('当前存档51','当前存档52').replace('当前存档 51','当前存档 52').replace('当前存档结构 51','当前存档结构 52').replace('schema51 / source49 / equipment51','schema52 / source49 / equipment51')
        assert current[key]==expected,key
    assert current['rules-ember_proliferation']==previous['rules-ember_proliferation'].replace('<dt>当前辅助数量</dt><dd>22</dd>','<dt>当前辅助数量</dt><dd>23</dd>')
    preserved={key:sha(body.encode()) for key,body in previous.items() if key not in changed}
    assert len(preserved)==3796
    for key in data['exploration_maps']['maps']:assert current['maps-'+key]==previous['maps-'+key]
    for key in ['rules-jewel_crafting','rules-chaos_defense']:assert current[key]==previous[key]
    for key in data['monsters']:assert current['monsters-'+key]==previous['monsters-'+key]
    page=Page();page.feed(html)
    assert len(page.ids)==len(set(page.ids))
    for link in page.links:
        if link.startswith('#'):assert link[1:] in page.ids,link
        elif not re.match(r'^[a-z]+:',link):assert (REF/link.split('#')[0]).resolve().exists(),link
    for path in page.assets:
        if not re.match(r'^[a-z]+:',path):assert (REF/path).is_file(),path
    payload=json.loads(re.search(r'<script id="reference-data" type="application/json">(.*?)</script>',html,re.S)[1])
    records={row['id']:row for row in payload['records']}
    for key in new:
        assert key in records
        for term in ['环斩','360','0.75','1.25','裂刃斩']:
            assert term.casefold() in records[key]['search'],(key,term)
    assert '环斩' in records['skills-cleave']['search']
    assert '#supports-encircling_cleave' in current['skills-cleave']
    rule=current['rules-encircling_cleave']
    for term in ['五槽','主命中','墙体视线','攻击闪避','面积倍率','schema51','不赠宝石','ENCIRCLING_CLEAVE.zh-CN.md','owned-fixture.json','main-result.json']:
        assert term in rule,term
    expected_values={'save-version':52,'source-policy':49,'equipment-vocabulary':51,'base-arc':180,'arc':360,'hit-multiplier':.75,'mana-multiplier':1.25,'radius':95,'compatible-count':6,'maximum-supports':5,'merchant-cost':4,'base-coefficient':280,'added-effectiveness':280,'before-mana':12,'after-mana':15,'before-cooldown':1.4,'after-cooldown':1.4,'before-radius-example':95,'after-radius-example':95,'before-hit':75.712,'after-hit':56.784,'main-checks':121,'actual-hit-targets':9,'actual-hit':56.784}
    assert page.values.keys()==expected_values.keys()
    for key,amount in expected_values.items():assert math.isclose(page.values[key],amount,rel_tol=0,abs_tol=1e-10),(key,page.values[key],amount)
    inputs=json.loads((QA/'export-input-sha256.json').read_text())
    for path,digest in inputs.items():assert sha((ROOT/path).read_bytes())==digest,path
    for key in ['actual_main_report','actual_main_run','actual_main_fixture']:
        evidence=data['encircling_cleave'][key];assert sha((ROOT/evidence['path']).read_bytes())==evidence['sha256']
    accepted=json.loads((ROOT/data['encircling_cleave']['actual_main_report']['path']).read_text())
    assert accepted['checks']==121 and accepted['failures']==0 and not accepted['labels']
    assert accepted['samples']==data['encircling_cleave']['actual_main_samples']
    receipts=accepted['samples'][0]['receipts'];assert len(receipts)==len({r['target_id'] for r in receipts})==9
    assert all(r['phase']=='direct' and r['skill_id']=='cleave' and r['total']==accepted['samples'][0]['expected']['total'] for r in receipts)
    tracked=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],cwd=ROOT,text=True).splitlines()
    protected=[p for p in tracked if p.lower().endswith(('.png','.ttf','.otf','.woff','.woff2')) or (p.startswith('docs/reference/') and p not in ['docs/reference/catalog.json','docs/reference/index.html'])]
    protected_hashes={}
    for path in protected:
        raw_file=(ROOT/path).read_bytes();assert raw_file==baseline(path),path;protected_hashes[path]=sha(raw_file)
    image=data['encircling_cleave'];png=(REF/image['icon_file']).read_bytes()
    assert png==(ROOT/image['icon_source'].removeprefix('res://')).read_bytes()
    assert sha(png)==image['icon_sha256']=='029dd3e73ca913cd91505f2d986f946d2b73b250caa63450b2f23d94bfe4dc51'
    assert png[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',png[16:24])==(1254,1254) and png[25]==6
    art=json.loads((REF/'art/manifest.json').read_text())
    assert builder.build(old,art)==old_html,'Baseline rendering must remain byte-identical without fragment'
    assert builder.build(data,art)==html,'Current HTML must be deterministic'
    run=json.loads((QA/'export-run.json').read_text());assert run['exit_code']==0 and run['export_count']==1 and run['input_fingerprints_unchanged']
    proof={'baseline_commit':BASE,'preserved_raw_top_level_count':len(retained),'preserved_raw_top_level':retained,'old_card_count':len(previous),'current_card_count':len(current),'unchanged_card_count':len(preserved),'changed_card_count':len(changed),'changed_cards':sorted(changed),'new_cards':sorted(new),'schema_number_only_cards':sorted(schema),'current_support_count_only_card':'rules-ember_proliferation','all_monsters_chaos_jewels_four_routes_byte_identical':True,'all_local_links_and_chinese_search_pass':True,'unique_anchor_count':len(page.ids),'numeric_values_verified':len(expected_values),'protected_file_count':len(protected),'protected_png_count':sum(p.endswith('.png') for p in protected),'protected_font_count':sum(p.lower().endswith(('.ttf','.otf','.woff','.woff2')) for p in protected),'protected_sha256':protected_hashes,'new_icon_sha256':sha(png),'new_icon_dimensions':[1254,1254],'new_icon_rgba':True,'input_count':len(inputs),'input_fingerprints_match':True,'actual_main_checks':121,'actual_main_failures':0,'actual_main_target_receipts':9,'deterministic_current_and_backward_builder':True,'scope':'Focused data, provenance, search, links and byte preservation. One bounded export only; no Main, old exporter, source coverage, maps, combat matrices, art generation or screenshots.'}
    (QA/'preservation.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2)+'\n')
    (QA/'card-sha256.json').write_text(json.dumps({'baseline_commit':BASE,'unchanged':preserved,'changed':{k:{'before':sha(previous[k].encode()),'after':sha(current[k].encode())} for k in sorted(changed)},'new':{k:sha(current[k].encode()) for k in sorted(new)}},ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in proof.items() if k not in ['protected_sha256','preserved_raw_top_level']},ensure_ascii=False,indent=2))

if __name__=='__main__':main()
