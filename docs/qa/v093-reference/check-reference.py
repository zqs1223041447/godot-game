#!/usr/bin/env python3
"""Focused v93 values, search, links and byte preservation. No Godot rerun."""
import hashlib
import importlib.util
import json
import math
import re
import subprocess
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT/'docs/reference'
BASE = '897dbfc'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def baseline(path): return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path); m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


class Page(HTMLParser):
    def __init__(self):
        super().__init__();self.ids=[];self.links=[];self.assets=[];self.values={}
    def handle_starttag(self,tag,pairs):
        attrs=dict(pairs)
        if 'id' in attrs:self.ids.append(attrs['id'])
        if 'href' in attrs:self.links.append(attrs['href'])
        if 'src' in attrs:self.assets.append(attrs['src'])
        if 'data-chaos-value' in attrs:
            key=attrs['data-chaos-value'];amount=float(attrs['data-value'])
            if key in self.values:assert self.values[key]==amount
            self.values[key]=amount


def main():
    merge=module('merge',QA/'merge-fragment.py');builder=module('builder',ROOT/'tools/build_reference.py')
    old_raw=baseline('docs/reference/catalog.json').decode();raw=(REF/'catalog.json').read_text()
    old=json.loads(old_raw);data=json.loads(raw);fragment=json.loads((QA/'chaos-defense-fragment.json').read_text())
    expected=json.loads(old_raw)
    for key in ['game_version','save_version','current_loot_profile_id','current_loot_profile','chaos_defense']:expected[key]=fragment[key]
    expected['chaos_defense']=dict(expected['chaos_defense'])
    expected['chaos_defense']['actual_main_receipts']=json.loads((ROOT/fragment['chaos_defense']['actual_main_report']['path']).read_text())['receipts']
    expected['affixes']['ring_voidward']=fragment['affix']
    expected['equipment_pools']['build_nine_slot_v51']=fragment['new_pool']
    expected['loot_profiles']['canonical_v51']=fragment['current_loot_profile']
    expected['equipment']['nine_slot_etched_ring']['eligible_affixes']=fragment['ring_eligible_affixes']
    for key in fragment['new_pool']['affix_ids']:
        if key!='ring_voidward':expected['affixes'][key]['pools'].append('build_nine_slot_v51')
    expected['monsters']['chaos_guard']=fragment['monster'];expected['monster_attacks']['locked_circle_chaos']=fragment['attack']
    expected['town_maps']['options']['special_modifiers'].append(fragment['special'])
    assert data==expected,'Every semantic change must be in the bounded fragment allowlist'
    old_tokens=merge.tokens(old_raw);current_tokens=merge.tokens(raw)
    retained=[key for key,token in old_tokens.items() if current_tokens[key]==token]
    assert len(retained)==77
    for section in ['equipment_pools','loot_profiles','monsters','monster_attacks']:
        a,b=merge.tokens(old_tokens[section]),merge.tokens(current_tokens[section])
        assert all(b[key]==value for key,value in a.items()),section
    for section in ['equipment','affixes']:
        for key,value in merge.tokens(old_tokens[section]).items():
            a,b=merge.tokens(value),merge.tokens(merge.tokens(current_tokens[section])[key])
            allowed={'eligible_affixes'} if section=='equipment' and key=='nine_slot_etched_ring' else {'pools'} if section=='affixes' and key in fragment['new_pool']['affix_ids'] else set()
            assert all(b[field]==token for field,token in a.items() if field not in allowed),(section,key)
    html=(REF/'index.html').read_text();old_html=baseline('docs/reference/index.html').decode()
    cards=lambda text:{key:body for body,key in re.findall(r'(<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>)',text,re.S)}
    previous,current=cards(old_html),cards(html)
    new={'affixes-ring_voidward','monsters-chaos_guard','monster_attacks-locked_circle_chaos','map_specials-chaos_patrol','rules-chaos_defense'}
    assert set(current)-set(previous)==new and set(previous)<=set(current)
    schema_only={'rules-source_tree','rules-source_monster_movement','rules-source_monster_damage_life','rules-source_monster_shield_recharge','rules-frost_lock','rules-elemental_conversion','rules-physical_fire_conversion'}
    intended={'equipment-nine_slot_etched_ring','rules-equipment','rules-exploration_maps'}|{'affixes-'+key for key in fragment['new_pool']['affix_ids'] if key!='ring_voidward'}|schema_only
    changed={key for key in previous if previous[key]!=current[key]}
    assert changed==intended,(changed-intended,intended-changed)
    for key in schema_only:
        assert current[key]==previous[key].replace('当前存档50','当前存档51').replace('当前存档 50','当前存档 51'),key
    preserved={key:sha(body.encode()) for key,body in previous.items() if key not in changed}
    assert len(preserved)==3777
    for key in list(data['exploration_maps']['maps']):assert current['maps-'+key]==previous['maps-'+key]
    assert current['rules-jewel_crafting']==previous['rules-jewel_crafting']
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
        assert 'chaos' in json.dumps(records[key],ensure_ascii=False).lower(),key
    rule=current['rules-chaos_defense']
    for term in ['混沌','50%','75%','后缀','魔力分担','显式旧池','新掉落','RNG','schema50','毒','CHAOS_DEFENSE.zh-CN.md','main-result.json','equipped-fixture.json']:
        assert term in rule,term
    expected_values={'windup':1,'radius':90,'trigger-distance':150,'recovery':1.8,'multiplier':.8,'minimum-wave':5,
        'formal-special-reward':2,'test-special-reward':0,'save-version':51,'equipment-vocabulary':51,'source-policy':49,
        'minimum':0,'cap':.75,'equipped-effective':.5,'monster-chaos-resistance':.25,'main-checks':130,
        'outgoing-raw':62.4,'outgoing-mitigated':46.8,'outgoing-shield':46.8,'outgoing-life':0,
        'incoming-raw':17.2,'incoming-mitigated':8.6,'incoming-shield':5,'incoming-life':3.6}
    for tier,(level,minimum,maximum,weight) in enumerate([(1,8,12,100),(8,13,18,60),(16,19,25,30)],1):
        for name,amount in [('level',level),('min',minimum),('max',maximum),('weight',weight)]:expected_values[f'tier-{tier}-{name}']=amount
    for wave,base,raw_hit in [(5,20.8,16.64),(10,24.3,19.44)]:
        expected_values[f'wave-{wave}-source']=base
        for resistance in [0,25,50]:expected_values[f'wave-{wave}-res-{resistance}']=raw_hit*(1-resistance/100)
    assert page.values.keys()==expected_values.keys()
    for key,amount in expected_values.items():assert math.isclose(page.values[key],amount,rel_tol=0,abs_tol=1e-10),(key,page.values[key],amount)
    inputs=json.loads((QA/'export-input-sha256.json').read_text())
    for path,digest in inputs.items():assert sha((ROOT/path).read_bytes())==digest,path
    for key in ['actual_main_report','actual_main_run','actual_main_fixture']:
        ev=data['chaos_defense'][key];assert sha((ROOT/ev['path']).read_bytes())==ev['sha256']
    accepted=json.loads((ROOT/data['chaos_defense']['actual_main_report']['path']).read_text())
    assert accepted['checks']==130 and accepted['failures']==0 and not accepted['labels']
    assert accepted['receipts']==data['chaos_defense']['actual_main_receipts']
    tracked=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],cwd=ROOT,text=True).splitlines()
    protected=[p for p in tracked if p.lower().endswith(('.png','.ttf','.otf','.woff','.woff2')) or (p.startswith('docs/reference/') and p not in ['docs/reference/catalog.json','docs/reference/index.html'])]
    protected_hashes={}
    for path in protected:
        raw_file=(ROOT/path).read_bytes();assert raw_file==baseline(path),path;protected_hashes[path]=sha(raw_file)
    art=json.loads((REF/'art/manifest.json').read_text())
    assert builder.build(old,art)==old_html,'New helper must preserve the complete old rendering when the fragment is absent'
    assert builder.build(data,art)==html,'Current HTML must exactly match deterministic builder output'
    proof={'baseline_commit':BASE,'preserved_raw_top_level_count':len(retained),'preserved_raw_top_level':retained,
        'unchanged_card_count':len(preserved),'changed_card_count':len(changed),'changed_cards':sorted(changed),'new_cards':sorted(new),
        'old_card_count':len(previous),'current_card_count':len(current),'schema_number_only_cards':sorted(schema_only),
        'four_route_cards_and_jewel_crafting_byte_identical':True,'old_pools_loot_profiles_monsters_attacks_raw_tokens_identical':True,
        'all_local_links_and_search_records_pass':True,'unique_anchor_count':len(page.ids),'numeric_values_verified':len(expected_values),
        'protected_file_count':len(protected),'protected_png_count':sum(p.endswith('.png') for p in protected),
        'protected_font_count':sum(p.lower().endswith(('.ttf','.otf','.woff','.woff2')) for p in protected),
        'protected_sha256':protected_hashes,'input_fingerprints_match':True,'actual_main_checks':130,'actual_main_failures':0,
        'deterministic_current_and_backward_builder':True,'scope':'Static values, input provenance, search records, links, and byte preservation only. No game/Main/map/art/source coverage rerun.'}
    (QA/'preservation.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2)+'\n')
    (QA/'card-sha256.json').write_text(json.dumps({'baseline_commit':BASE,'unchanged':preserved,'changed':{k:{'before':sha(previous[k].encode()),'after':sha(current[k].encode())} for k in sorted(changed)},'new':{k:sha(current[k].encode()) for k in sorted(new)}},ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({key:value for key,value in proof.items() if key not in ['protected_sha256','preserved_raw_top_level']},ensure_ascii=False,indent=2))


if __name__=='__main__':main()
