#!/usr/bin/env python3
"""Freeze independent v54 reference evidence; admit only reviewed v55 metadata deltas."""
import hashlib
import json
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OLD=ROOT.parent/'v054-final-source-snapshot/docs/reference'
QA=ROOT/'docs/qa/v055-reference'
NEW=ROOT/'docs/reference'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def digest(value):return hashlib.sha256(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def walk(a,b,p=()):
    if a==b:return []
    if isinstance(a,dict) and isinstance(b,dict):
        assert a.keys()<=b.keys(), p
        return [{'path':list(p+(k,)),'added':b[k]} for k in sorted(b.keys()-a.keys())]+[row for k in sorted(a) for row in walk(a[k],b[k],p+(k,))]
    if isinstance(a,list) and isinstance(b,list):
        if p==('town_maps','stock','equipment_merchant'):
            added=[(i,row) for i,row in enumerate(b) if row.get('catalog_id')=='forgeblade']
            assert len(added)==1 and [row for row in b if row.get('catalog_id')!='forgeblade']==a
            return [{'path':list(p+(added[0][0],)),'added':added[0][1]}]
        assert len(a)<=len(b),p
        return [row for k in range(len(a)) for row in walk(a[k],b[k],p+(k,))]+[{'path':list(p+(k,)),'added':b[k]} for k in range(len(a),len(b))]
    return [{'path':list(p),'before':a,'after':b}]
a=json.loads((OLD/'catalog.json').read_text()); b=json.loads((NEW/'catalog.json').read_text())
rows=walk(a,b)
new_paths=[];changes=[];categories={}
new_roots=[['forgeblade'],['equipment','forgeblade'],['equipment_pools','forgeblade_v34'],['loot_profiles','canonical_v34'],
           ['crafting','calibration_shard','rules','eligible_families_by_base','forgeblade'],
           ['weapon_stages','weapon_local','consumers_by_base'],['weapon_stages','weapon_local','consumers','cleave']]
old_text='没有命中时也正常支付，不借用白蜡长弓本地伤害。'
new_text='锻纹短刃的本地物理伤害参与本次斩击，白蜡长弓不参与。没有命中时也正常支付。'
for row in rows:
    p=row['path']; kind=''
    if 'added' in row:
        if p in new_roots:kind='new_content_or_consumer_metadata'
        elif row['added'] in ['forgeblade','forgeblade_v34','weapon']:
            assert p[0] in ['affixes','crafting','weapon_stages']
            if row['added']=='weapon':assert p[0]=='affixes' and p[1] in ['global_critical_chance','global_critical_multiplier'] and p[2]=='slots'
            kind='appended_eligibility_metadata'
        elif p==['current_loot_profile',5]:
            assert row['added']=={'pool_id':'forgeblade_v34','weight':5};kind='new_current_loot_profile'
        elif p[:3]==['town_maps','stock','equipment_merchant']:
            assert row['added']['catalog_id']=='forgeblade';kind='new_town_stock'
        elif p[0]=='crafting' and p[1] in ['targeted_reforge_damage','targeted_reforge_critical'] and p[2]=='eligibility':
            assert row['added']['base_id']=='forgeblade';kind='appended_eligibility_metadata'
        assert kind, row
        new_paths.append(p)
    else:
        before,after=row['before'],row['after']
        if p[-1] in ['save_version','schema'] and (before,after)==(33,34):kind='current_schema_metadata'
        elif p==['canonical','default_build','version'] and (before,after)==(33,34):kind='current_schema_metadata'
        elif p[-1]=='catalog_vocabulary' and p[0]=='crafting' and (before,after)==(27,34):kind='current_vocabulary_metadata'
        elif p==['game_version'] and (before,after)==('0.54.0','0.55.0'):kind='current_version_metadata'
        elif p==['current_loot_profile_id'] and (before,after)==('canonical_v27','canonical_v34'):kind='new_current_loot_profile'
        elif p==['current_loot_profile',0,'weight'] and (before,after)==(30,25):kind='new_current_loot_profile'
        elif p[-1]=='details' and isinstance(before,str) and before.replace(old_text,new_text)==after and old_text in before:kind='new_consumer_explanation_only'
        elif p==['weapon_stages','weapon_local','description']:
            assert before==a['weapon_stages']['weapon_local']['description']
            assert after=='局部点伤与局部物理提高先结算本武器；长弓仅加入普通攻击与龙卷箭体，锻纹短刃仅加入裂刃斩直接命中，均按技能基础倍率加入物理点数。保留原有角色基伤，不是完整武器基伤替换。'
            kind='new_consumer_explanation_only'
        assert kind,row
        changes.append(row)
    categories[kind]=categories.get(kind,0)+1
baseline={'source':'independent v054-final-source-snapshot/docs/reference','source_file_sha256':sha(OLD/'catalog.json'),
          'catalog_semantic_sha256':digest(a),'source_tree_sha256':digest(a['source_tree']),
          'source_coverage_sha256':sha(OLD/'source-tree-coverage.json'),
          'article_ids':re.findall(r'<article\b[^>]*\bid="([^"]+)"',(OLD/'index.html').read_text()),
          'image_sha256':{p.relative_to(OLD).as_posix():sha(p) for p in sorted(OLD.rglob('*.png'))},
          'new_paths':new_paths,'approved_changes':changes,'delta_categories':categories}
target=QA/'v054-reference-baseline.json'
assert not target.exists(),'Never overwrite frozen baseline'
target.write_text(json.dumps(baseline,ensure_ascii=False,indent=2)+'\n')
(QA/'catalog-diff-review.json').write_text(json.dumps({'reviewed_leaf_differences':len(rows),'categories':categories,'new_paths':new_paths,'approved_change_paths':[c['path'] for c in changes]},ensure_ascii=False,indent=2)+'\n')
print('Baseline captured:',categories)
