#!/usr/bin/env python3
"""Reproducible, offline-queryable PoE1 ordinary-affix research reference.
Original research tooling. Exported game data is NOT covered by this tool's authorship.
No game runtime code is changed; no assets or source item descriptions are exported.
"""
from __future__ import annotations
import argparse, collections, hashlib, json, pathlib, urllib.request
ROOT = pathlib.Path(__file__).resolve().parents[1]
CLASSES = ['Amulet','Belt','Body Armour','Boots','Bow','Claw','Dagger','Gloves','Helmet','One Hand Axe','One Hand Mace','One Hand Sword','Quiver','Ring','Rune Dagger','Sceptre','Shield','Staff','Thrusting One Hand Sword','Two Hand Axe','Two Hand Mace','Two Hand Sword','Wand','Warstaff']
EXCLUDE_BASE_TAGS = {'talisman','demigods','trade_market_legacy_item','experimental_base'}
EXCLUDE_BASE_ID = ('Royale','Descent','MirrorRing','Ethereal','/Talismans/','StormBlade')

def read(path): return json.loads(path.read_text(encoding='utf-8'))
def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=None if path.name=='profiles.json' else 2, separators=(',',':') if path.name=='profiles.json' else None, sort_keys=False)+'\n',encoding='utf-8')
def digest(b): return hashlib.sha256(b).hexdigest()
def first_weight(rows, tags, default):
    return next((x['weight'] for x in rows if x['tag'] in tags), default)
def weight(mod, tags):
    return first_weight(mod['spawn_weights'], tags, 0)*first_weight(mod['generation_weights'], tags, 100)/100

def base_reason(key, b):
    if b['item_class'] not in CLASSES: return 'outside_24_equipment_classes'
    if b['release_state'] != 'released': return 'not_released_in_source'
    if b['domain'] != 'item': return 'non_item_domain'
    if EXCLUDE_BASE_TAGS.intersection(b['tags']): return 'excluded_special_or_legacy_base_tag'
    if any(x in key for x in EXCLUDE_BASE_ID): return 'excluded_alternate_mode_or_special_base_id'
    return None

def mod_reason(key, m):
    if m['domain'] != 'item': return 'non_item_domain'
    if m['generation_type'] not in ('prefix','suffix'): return 'not_prefix_or_suffix'
    if m['is_essence_only']: return 'essence_only'
    if 'Royale' in key: return 'alternate_mode_royale'
    return None

def verify_inputs(root):
    manifest = read(root/'source_manifest.json')
    for row in manifest['files']:
        b = (root/'raw'/row['name']).read_bytes()
        assert len(b)==row['bytes'], row['name']+' size mismatch'
        assert digest(b)==row['sha256'], row['name']+' sha256 mismatch'
        assert hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==row['git_blob_sha1']
    return manifest

def fetch(root):
    """Only retrieve the four fixed public URLs in the checked-in source manifest."""
    for row in read(root/'source_manifest.json')['files']:
        dst = root/'raw'/row['name']; dst.parent.mkdir(parents=True,exist_ok=True)
        if dst.exists() and digest(dst.read_bytes())==row['sha256']: continue
        with urllib.request.urlopen(row['url'],timeout=180) as r: b = r.read()
        assert digest(b)==row['sha256'], row['name']+' remote bytes changed'
        dst.write_bytes(b)
    verify_inputs(root)

def family_key(m):
    # A group is an exclusion rule, NOT a tier family. Preserve precise mechanics.
    return (m['generation_type'], tuple(m['groups']), m['type'], tuple(s['id'] for s in m['stats']))

def build(root):
    manifest=verify_inputs(root)
    all_bases=read(root/'raw/base_items.json'); all_mods=read(root/'raw/mods.json'); all_stats=read(root/'raw/stats.json')
    base_excluded=collections.Counter(); mod_excluded=collections.Counter(); bases={}; profiles={}
    for key,b in sorted(all_bases.items()):
        reason=base_reason(key,b)
        if reason: base_excluded[reason]+=1; continue
        # Stable ID for exact class + ordered source tag set; no implied influence tags.
        signature=json.dumps([b['item_class'],b['tags']],separators=(',',':'))
        profile_id='profile_'+hashlib.sha256(signature.encode()).hexdigest()[:12]
        p=profiles.setdefault(profile_id,{'item_class':b['item_class'],'tags':b['tags'],'base_ids':[],'mod_weights':{}})
        p['base_ids'].append(key)
        bases[key]={'item_class':b['item_class'],'base_name':b['name'],'profile_id':profile_id,'drop_level_source':b['drop_level'],'tags':b['tags']}
    candidates={}
    for key,m in sorted(all_mods.items()):
        reason=mod_reason(key,m)
        if reason: mod_excluded[reason]+=1
        else: candidates[key]=m
    selected=set()
    for pid,p in profiles.items():
        for key,m in candidates.items():
            w=weight(m,p['tags'])
            if w>0: p['mod_weights'][key]=w; selected.add(key)
    mod_excluded['no_positive_weight_on_selected_base_profiles']=len(candidates)-len(selected)
    mods={}; stat_ids=set(); family_ids={}
    for key in sorted(selected):
        m=all_mods[key]; stat_ids.update(s['id'] for s in m['stats'])
        family_signature=family_key(m)
        family_id='family_'+hashlib.sha256(json.dumps(family_signature,separators=(',',':')).encode()).hexdigest()[:12]
        family_ids[key]=family_id
        # Numerical/mechanical fields only. Deliberately omit GGG affix names/text/art.
        mods[key]={k:m[k] for k in ('generation_type','required_level','groups','type','stats','spawn_weights','generation_weights','adds_tags','implicit_tags','grants_effects')}
        mods[key]['family_id_derived']=family_id
    families={}
    ambiguous=[]
    for pid,p in profiles.items():
        by_family=collections.defaultdict(list)
        for key in p['mod_weights']: by_family[family_ids[key]].append(key)
        p['family_tiers_derived']={}
        for fid,keys in by_family.items():
            levels=sorted({mods[key]['required_level'] for key in keys},reverse=True)
            p['family_tiers_derived'][fid]=[]
            for level in levels:
                at_level=sorted(k for k in keys if mods[k]['required_level']==level)
                row={'tier_index_derived':levels.index(level)+1,'required_item_level':level,'mod_ids':at_level,'ambiguous_same_level':len(at_level)>1}
                p['family_tiers_derived'][fid].append(row)
                if len(at_level)>1: ambiguous.append({'profile_id':pid,'family_id':fid,**row})
            m=mods[keys[0]]
            families.setdefault(fid,{'generation_type':m['generation_type'],'exclusion_groups':m['groups'],'type':m['type'],'ordered_stat_ids':[s['id'] for s in m['stats']],'mod_ids':set()})['mod_ids'].update(keys)
    for f in families.values(): f['mod_ids']=sorted(f['mod_ids'])
    # Conditional closure audit: chosen pool adds only has_attack_mod/has_caster_mod.
    # Detect any candidate unspawnable on a bare base that can become spawnable after these tags.
    conditional_only=set()
    for p in profiles.values():
        tags=set(p['tags']); changed=True
        while changed:
            before=set(tags)
            for m in candidates.values():
                if weight(m,tags)>0: tags.update(m['adds_tags'])
            changed=tags!=before
        for key,m in candidates.items():
            if weight(m,tags)>0 and key not in p['mod_weights']: conditional_only.add(key)
    per_class={}
    for cls in CLASSES:
        ps=[p for p in profiles.values() if p['item_class']==cls]
        ids=set().union(*(set(p['mod_weights']) for p in ps))
        per_class[cls]={'base_count':sum(len(p['base_ids']) for p in ps),'profile_count':len(ps),'distinct_mod_rows':len(ids),'prefix_rows':sum(mods[k]['generation_type']=='prefix' for k in ids),'suffix_rows':sum(mods[k]['generation_type']=='suffix' for k in ids)}
    coverage={'schema_version':1,'source_version':manifest['source_version'],'source_commit':manifest['export_commit'],'source_mod_rows':len(all_mods),'source_base_rows':len(all_bases),'equipment_classes':len(CLASSES),'selected_base_rows':len(bases),'exact_tag_profiles':len(profiles),'selected_mod_rows':len(mods),'prefix_rows':sum(m['generation_type']=='prefix' for m in mods.values()),'suffix_rows':sum(m['generation_type']=='suffix' for m in mods.values()),'exclusion_groups':len({g for m in mods.values() for g in m['groups']}),'derived_tier_families':len(families),'stat_ids':len(stat_ids),'per_class':per_class,'excluded_base_rows_first_reason':dict(base_excluded),'excluded_mod_rows_first_reason':dict(mod_excluded),'conditional_only_mod_ids':sorted(conditional_only),'ambiguous_derived_tier_entries':ambiguous,'completeness':'Exact selected-snapshot/filter coverage only. Release flags and positive weights do not certify current live drop availability. Source has no official displayed tier field.'}
    out=root/'normalized'
    for filename,data in [('mods.json',mods),('bases.json',bases),('profiles.json',profiles),('families.json',families),('stats.json',{k:all_stats[k] for k in sorted(stat_ids)}),('coverage.json',coverage)]:write(out/filename,data)
    write(root/'filter_spec.json',{'equipment_classes':CLASSES,'base_predicates':{'domain':'item','release_state':'released','excluded_tags':sorted(EXCLUDE_BASE_TAGS),'excluded_id_fragments':list(EXCLUDE_BASE_ID)},'mod_predicates':{'domain':'item','generation_types':['prefix','suffix'],'is_essence_only':False,'excluded_id_fragments':['Royale'],'effective_weight':'first matching spawn_weight * first matching generation_weight / 100; missing spawn=0, missing generation=100','eligible_if':'effective_weight > 0 for at least one retained non-influenced base profile'},'tier_derivation':'Within exact base profile, affix generation, ordered groups, type, ordered stat IDs: descending distinct required_level rank. Ties remain multiple IDs and are explicitly flagged; NOT official displayed tiers. Derive before applying requested item level so ranks do not renumber on low-level items.'})
    print(json.dumps({k:v for k,v in coverage.items() if k not in ('per_class','ambiguous_derived_tier_entries')},ensure_ascii=False,indent=2))

def query(root, base_id, item_level, affix=None, group=None, existing_ids=()):
    bases=read(root/'normalized/bases.json');profiles=read(root/'normalized/profiles.json');mods=read(root/'normalized/mods.json')
    if base_id not in bases: raise ValueError('Exact base ID not in selected scope')
    p=profiles[bases[base_id]['profile_id']]; tags=set(p['tags']); occupied=set()
    for key in existing_ids:
        m=mods[key]; tags.update(m['adds_tags']); occupied.update(m['groups'])
    result=[]
    for key,m in mods.items():
        if m['required_level']>item_level or occupied.intersection(m['groups']): continue
        if affix and m['generation_type']!=affix: continue
        if group and group not in m['groups']: continue
        w=weight(m,tags)
        if w<=0: continue
        tiers=p['family_tiers_derived'].get(m['family_id_derived'],[])
        tier=next((x['tier_index_derived'] for x in tiers if key in x['mod_ids']),None)
        result.append({'id':key,'affix':m['generation_type'],'required_item_level':m['required_level'],'tier_index_derived':tier,'effective_weight':w,'groups':m['groups'],'stats':m['stats']})
    return result

def validate(root):
    verify_inputs(root)
    mods=read(root/'normalized/mods.json');bases=read(root/'normalized/bases.json');profiles=read(root/'normalized/profiles.json');stats=read(root/'normalized/stats.json');coverage=read(root/'normalized/coverage.json')
    assert len(mods)==coverage['selected_mod_rows'];assert len(bases)==coverage['selected_base_rows']
    for key,m in mods.items():
        assert 'Royale' not in key
        assert m['generation_type'] in ('prefix','suffix')
        assert all(s['min']<=s['max'] and s['id'] in stats for s in m['stats'])
    for p in profiles.values():
        for key,w in p['mod_weights'].items(): assert w==weight(mods[key],p['tags']) and w>0
    assert first_weight([{'tag':'weapon','weight':0},{'tag':'default','weight':1000}],{'weapon','default'},0)==0
    assert weight(mods['LocalIncreasedPhysicalDamagePercent8'],{'bow','weapon','default'})==25
    assert weight(mods['LocalIncreasedPhysicalDamagePercent8'],{'wand','weapon','wand_can_roll_caster_modifiers','default'})==12.5
    assert weight(mods['IncreasedLife8'],{'ring','default'})==0
    bow='Metadata/Items/Weapons/TwoHandWeapons/Bows/Bow1'
    r=query(root,bow,82,group='LocalPhysicalDamagePercent'); assert len(r)==7 and not any(x['id']=='LocalIncreasedPhysicalDamagePercent8' for x in r)
    r=query(root,bow,83,group='LocalPhysicalDamagePercent'); assert len(r)==8 and next(x for x in r if x['id']=='LocalIncreasedPhysicalDamagePercent8')['tier_index_derived']==1
    r=query(root,bow,100,group='LocalPhysicalDamagePercent',existing_ids=['LocalIncreasedPhysicalDamagePercent1']);assert not r
    r=query(root,bow,100,group='LocalIncreasedPhysicalDamagePercentAndAccuracyRating',existing_ids=['LocalIncreasedPhysicalDamagePercent1']);assert r
    assert not coverage['conditional_only_mod_ids'], 'Conditional-only candidates need a separate coverage policy'
    result={'passed':True,'checks':['4 pinned source SHA256 + Git blob SHA1 + byte sizes','selected counts/references','stat range order and source metadata presence','every profile effective weight','first matching zero blocks later default','caster-weapon generation weight multiplier','body/slot-specific life tier restriction','item level 82/83 tier eligibility boundary','tier rank remains global to profile before ilvl filter','same group exclusion','hybrid different-group coexistence','conditional adds_tags closure'], 'source_version':coverage['source_version'],'selected_mod_rows':len(mods),'selected_base_rows':len(bases)}
    write(root/'validation.json',result);print(json.dumps(result,ensure_ascii=False,indent=2))

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('command',choices=['fetch','build','validate','query']);parser.add_argument('--root',type=pathlib.Path,default=ROOT);parser.add_argument('--base-id');parser.add_argument('--ilvl',type=int,default=86);parser.add_argument('--affix',choices=['prefix','suffix']);parser.add_argument('--group');parser.add_argument('--existing',action='append',default=[])
    a=parser.parse_args()
    if a.command=='query': print(json.dumps(query(a.root,a.base_id,a.ilvl,a.affix,a.group,a.existing),ensure_ascii=False,indent=2))
    else: {'fetch':fetch,'build':build,'validate':validate}[a.command](a.root)
if __name__=='__main__':main()
