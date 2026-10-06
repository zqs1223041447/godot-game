"""Preserve historical catalog tokens/whitespace while adding verified new data."""
from pathlib import Path
import hashlib,json,subprocess
root=Path(__file__).resolve().parents[3]
p=root/'docs/reference/catalog.json';before=p.read_text();current=json.loads(before)
base_bytes=subprocess.check_output(['git','show','a1dd1acf:docs/reference/catalog.json'],cwd=root);base=base_bytes.decode();decoder=json.JSONDecoder()
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
root_fields=fields(base);mech=fields(base,root_fields['mechanisms'][1]);changes=[]
def insert_before(mapping,key,value,level):
 next_key=min(k for k in mapping if k>key)
 pos=mapping[next_key][0]
 rendered=json.dumps(value,ensure_ascii=False,indent='\t',sort_keys=True).replace('\n','\n'+'\t'*level)
 changes.append((pos,pos,json.dumps(key)+': '+rendered+',\n'+'\t'*level))
insert_before(mech,'source_gale_stride',current['mechanisms']['source_gale_stride'],2)
insert_before(root_fields,'source_monster_movement',current['source_monster_movement'],1)
_,start,end=root_fields['game_version'];changes.append((start,end,json.dumps(current['game_version'])))
after=base
for start,end,replacement in sorted(changes,reverse=True):after=after[:start]+replacement+after[end:]
parsed=json.loads(after)
canonical=lambda d:json.dumps(d,ensure_ascii=False,separators=(',',':'))
assert canonical(parsed)==canonical(current),'Value/types/key order changed'
p.write_text(after)
proof={'method':'Only three verified insert/replacement spans applied to exact Git baseline; all other original bytes preserved.','base_commit':'a1dd1acf','same_typed_ordered_json':True,'original_sha256':hashlib.sha256(base_bytes).hexdigest(),'previous_format_sha256':hashlib.sha256(before.encode()).hexdigest(),'final_sha256':hashlib.sha256(after.encode()).hexdigest(),'modified_fields':['game_version','mechanisms.source_gale_stride','source_monster_movement'],'before_bytes':len(before.encode()),'after_bytes':len(after.encode())}
(root/'docs/qa/v074-reference/catalog-format-preservation.json').write_text(json.dumps(proof,indent=2)+'\n');print(proof)
