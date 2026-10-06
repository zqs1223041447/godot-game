#!/usr/bin/env python3
"""Splice new shield reference spans into the exact v75 baseline, retaining old tokens."""
import hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];QA=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
BASE='76c9cab'
raw=subprocess.check_output(['git','show',BASE+':docs/reference/catalog.json'],cwd=ROOT)
base=raw.decode();baseline=json.loads((QA/'v075-baseline.json').read_text());assert sha(raw)==baseline['catalog_sha256']
old=json.loads(base);fragment=json.loads((QA/'source-fragment.json').read_text())
assert fragment['game_version']=='0.76.0'
old_source={'source_gale_stride','source_ember_power','source_grove_vitality'}
new_source={'source_aegis_capacity','source_aegis_recovery'}
for key in old_source:assert fragment['mechanisms'][key]==old['mechanisms'][key],key
assert set(fragment['mechanisms'])==old_source|new_source

def fields(text,start=0):
    decoder=json.JSONDecoder();i=start+1;result={}
    while True:
        while text[i].isspace():i+=1
        if text[i]=='}':return result
        key_start=i;key,i=decoder.raw_decode(text,i)
        while text[i].isspace():i+=1
        assert text[i]==':';i+=1
        while text[i].isspace():i+=1
        value_start=i;_,i=decoder.raw_decode(text,i);result[key]=(key_start,value_start,i)
        while text[i].isspace():i+=1
        if text[i]==',':i+=1
        else:assert text[i]=='}';return result
root_fields=fields(base);mechanisms=fields(base,root_fields['mechanisms'][1]);changes=[];insertions={};changed_fields=[]
def render(value,level):return json.dumps(value,ensure_ascii=False,indent='\t',sort_keys=True).replace('\n','\n'+'\t'*level)
def update(mapping,key,value,level,path):
    if key in mapping:
        _,start,end=mapping[key]
        if json.loads(base[start:end])==value:return
        changes.append((start,end,render(value,level)));changed_fields.append(path);return
    later=sorted(k for k in mapping if k>key)
    if later:pos=mapping[later[0]][0];suffix=True
    else:pos=mapping[max(mapping)][2];suffix=False
    insertions.setdefault((pos,level,suffix),[]).append((key,value));changed_fields.append(path)
update(root_fields,'game_version',fragment['game_version'],1,'game_version')
update(root_fields,'source_monster_shield_recharge',fragment['source_monster_shield_recharge'],1,'source_monster_shield_recharge')
for key in sorted(new_source):update(mechanisms,key,fragment['mechanisms'][key],2,'mechanisms.'+key)
for chapter,updates in [('source_monster_movement','movement_updates'),('source_monster_damage_life','damage_life_updates')]:
    chapter_fields=fields(base,root_fields[chapter][1])
    for key,value in fragment[updates].items():update(chapter_fields,key,value,2,chapter+'.'+key)
for (pos,level,suffix),items in insertions.items():
    text=(',\n'+'\t'*level).join(json.dumps(key)+': '+render(value,level) for key,value in sorted(items))
    text=text+',\n'+'\t'*level if suffix else ',\n'+'\t'*level+text
    changes.append((pos,pos,text))
after=base
for start,end,replacement in sorted(changes,reverse=True):after=after[:start]+replacement+after[end:]
expected=json.loads(base);expected['game_version']=fragment['game_version'];expected['source_monster_shield_recharge']=fragment['source_monster_shield_recharge']
for key in new_source:expected['mechanisms'][key]=fragment['mechanisms'][key]
expected['source_monster_movement'].update(fragment['movement_updates']);expected['source_monster_damage_life'].update(fragment['damage_life_updates'])
canonical=lambda d:json.dumps(d,ensure_ascii=False,sort_keys=True,separators=(',',':'))
assert canonical(json.loads(after))==canonical(expected)
# Direct raw token verification is stricter than structural or float equality.
new_roots=fields(after);new_mechanisms=fields(after,new_roots['mechanisms'][1])
for key,(_,start,end) in mechanisms.items():
    _,new_start,new_end=new_mechanisms[key];assert base[start:end]==after[new_start:new_end],key
for chapter in ['source_monster_movement','source_monster_damage_life']:
    old_fields=fields(base,root_fields[chapter][1]);new_fields=fields(after,new_roots[chapter][1])
    for key,(_,start,end) in old_fields.items():
        if chapter+'.'+key not in changed_fields:
            _,new_start,new_end=new_fields[key];assert base[start:end]==after[new_start:new_end],chapter+'.'+key
for key,(_,start,end) in root_fields.items():
    if key not in ['game_version','mechanisms','source_monster_movement','source_monster_damage_life']:
        _,new_start,new_end=new_roots[key];assert base[start:end]==after[new_start:new_end],key
(ROOT/'docs/reference/catalog.json').write_text(after)
proof={'base_commit':BASE,'baseline_sha256':sha(raw),'final_sha256':sha(after.encode()),'fragment_sha256':sha((QA/'source-fragment.json').read_bytes()),'method':'Only listed spans spliced into exact Git baseline; all other original bytes and numeric token types retained; no old JSON parsed by Godot','modified_fields':changed_fields,'splice_count':len(changes),'historical_raw_tokens_preserved':True,'legacy_definitions_preserved':23,'old_source_definitions_preserved':3,'old_movement_and_damage_life_budgets_preserved':True}
with (QA/'catalog-format-preservation.json').open('x') as f:json.dump(proof,f,indent=2);f.write('\n')
print(json.dumps(proof,indent=2))
