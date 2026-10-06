#!/usr/bin/env python3
"""Splice only new reference data into the verified v74 catalog bytes."""
import hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];QA=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
raw=subprocess.check_output(['git','show','f2427f3:docs/reference/catalog.json'],cwd=ROOT)
base=raw.decode();baseline=json.loads((QA/'v074-baseline.json').read_text());assert sha(raw)==baseline['catalog_sha256']
old=json.loads(base);fragment=json.loads((QA/'source-fragment.json').read_text())
assert fragment['game_version']=='0.75.0'
assert fragment['mechanisms']['source_gale_stride']==old['mechanisms']['source_gale_stride']
assert set(fragment['mechanisms'])=={'source_ember_power','source_gale_stride','source_grove_vitality'}
decoder=json.JSONDecoder()
def fields(text,start=0):
    i=start+1;result={}
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
root_fields=fields(base);mechanisms=fields(base,root_fields['mechanisms'][1]);movement=fields(base,root_fields['source_monster_movement'][1]);changes=[];insertions={}
def render(value,level):return json.dumps(value,ensure_ascii=False,indent='\t',sort_keys=True).replace('\n','\n'+'\t'*level)
def update(mapping,key,value,level):
    if key in mapping:
        _,start,end=mapping[key];changes.append((start,end,render(value,level)));return
    later=sorted(k for k in mapping if k>key)
    if later:pos=mapping[later[0]][0];suffix=True
    else:pos=mapping[max(mapping)][2];suffix=False
    insertions.setdefault((pos,level,suffix),[]).append((key,value))
update(root_fields,'game_version',fragment['game_version'],1)
update(root_fields,'source_monster_damage_life',fragment['source_monster_damage_life'],1)
for key in ['source_ember_power','source_grove_vitality']:update(mechanisms,key,fragment['mechanisms'][key],2)
for key,value in fragment['movement_updates'].items():update(movement,key,value,2)
for (pos,level,suffix),items in insertions.items():
    text=(',\n'+'\t'*level).join(json.dumps(key)+': '+render(value,level) for key,value in sorted(items))
    text=text+',\n'+'\t'*level if suffix else ',\n'+'\t'*level+text
    changes.append((pos,pos,text))
after=base
for start,end,replacement in sorted(changes,reverse=True):after=after[:start]+replacement+after[end:]
expected=json.loads(base);expected['game_version']=fragment['game_version'];expected['source_monster_damage_life']=fragment['source_monster_damage_life']
for key in ['source_ember_power','source_grove_vitality']:expected['mechanisms'][key]=fragment['mechanisms'][key]
expected['source_monster_movement'].update(fragment['movement_updates'])
assert json.loads(after)==expected
# Canonical serialization additionally proves historic integer/float token types survive.
canonical=lambda d:json.dumps(d,ensure_ascii=False,sort_keys=True,separators=(',',':'))
assert canonical(json.loads(after))==canonical(expected)
(ROOT/'docs/reference/catalog.json').write_text(after)
proof={'base_commit':'f2427f3','baseline_sha256':sha(raw),'final_sha256':sha(after.encode()),'fragment_sha256':sha((QA/'source-fragment.json').read_bytes()),'method':'Only listed value/insert spans applied to exact Git baseline; all other original bytes untouched; no historical JSON round-trip through Godot','modified_fields':['game_version','mechanisms.source_ember_power','mechanisms.source_grove_vitality','source_monster_damage_life']+['source_monster_movement.'+k for k in fragment['movement_updates']],'splice_count':len(changes),'historical_number_types_preserved':True,'old_gale_definition_preserved':True}
with (QA/'catalog-format-preservation.json').open('x') as f:json.dump(proof,f,indent=2);f.write('\n')
print(json.dumps(proof,indent=2))
