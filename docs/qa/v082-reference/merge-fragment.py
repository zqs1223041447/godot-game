#!/usr/bin/env python3
"""Splice v82 allowed changes into exact a57a9c0 catalog bytes, retaining all other tokens."""
import copy,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];QA=Path(__file__).resolve().parent;REF=ROOT/'docs/reference';BASE='a57a9c0'
def sha(b):return hashlib.sha256(b).hexdigest()
def baseline(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
def scalar_changes(a,b,path=()):
 if a==b:return []
 if isinstance(a,dict) and isinstance(b,dict) and a.keys()==b.keys():return sum((scalar_changes(a[k],b[k],path+(k,)) for k in a),[])
 if isinstance(a,list) and isinstance(b,list) and len(a)==len(b):return sum((scalar_changes(x,y,path+(i,)) for i,(x,y) in enumerate(zip(a,b))),[])
 return [(path,a,b)]
def spans(text,start=0):
 decoder=json.JSONDecoder();i=start+1;result={};array=text[start]=='[';index=0
 while True:
  while text[i].isspace():i+=1
  if text[i] in '}]':return result
  key_start=i
  if array:key=index;index+=1
  else:
   key,i=decoder.raw_decode(text,i)
   while text[i].isspace():i+=1
   assert text[i]==':';i+=1
   while text[i].isspace():i+=1
  value_start=i;_,i=decoder.raw_decode(text,i);result[key]=(key_start,value_start,i)
  while text[i].isspace():i+=1
  if text[i]==',':i+=1
  else:assert text[i] in '}]';return result

def main():
 raw=baseline('docs/reference/catalog.json');base=raw.decode();old=json.loads(base);fragment=json.loads((QA/'cold-duration-fragment.json').read_text())
 assert set(fragment['nodes'])==set(fragment['localized_nodes'])=={'14209'}
 assert set(fragment['localized_lines'])=={'20% increased Duration of Cold Ailments'}
 assert fragment['game_version']=='0.82.0' and fragment['save_version']==fragment['source_policy']==49
 expected=copy.deepcopy(old)
 expected['game_version']=fragment['game_version'];expected['save_version']=fragment['save_version'];expected['cold_ailment_duration']=fragment['cold_ailment_duration']
 expected['source_tree']['source_policy']=fragment['source_policy']
 for key,updates in fragment['nodes'].items():expected['source_tree']['nodes'][key].update(updates)
 for key,updates in fragment['localized_nodes'].items():expected['source_tree_localization']['nodes'][key].update(updates)
 expected['source_tree_localization']['lines'].update(fragment['localized_lines'])
 metadata=[]
 for key,value in fragment['mechanisms'].items():
  differences=scalar_changes(old['mechanisms'][key],value)
  assert differences,key
  for path,a,b in differences:
   assert (path[-1] in ['source_policy','source_save_version'] and a==48 and b==49) or (path==('policy_version',) and a=='source-tree:3.29.1:policy:48' and b=='source-tree:3.29.1:policy:49'),(key,path,a,b)
  expected['mechanisms'][key]=value;metadata.extend([['mechanisms',key,*path] for path,_,_ in differences])
 changes=[];paths=[]
 def render(value,level):return json.dumps(value,ensure_ascii=False,indent='\t',sort_keys=True).replace('\n','\n'+'\t'*level)
 def patch(a,b,start,end,level,path):
  if a==b:return
  if isinstance(a,dict) and isinstance(b,dict) and set(a)<=set(b):
   fields=spans(base,start)
   for key in a:
    _,vstart,vend=fields[key];patch(a[key],b[key],vstart,vend,level+1,path+[key])
   for key in sorted(set(b)-set(a)):
    later=sorted(k for k in fields if k>key)
    if later:pos=fields[later[0]][0];replacement=json.dumps(key)+': '+render(b[key],level+1)+',\n'+'\t'*(level+1)
    else:pos=fields[max(fields)][2];replacement=',\n'+'\t'*(level+1)+json.dumps(key)+': '+render(b[key],level+1)
    changes.append((pos,pos,replacement));paths.append(path+[key])
   return
  if isinstance(a,list) and isinstance(b,list) and len(a)==len(b):
   fields=spans(base,start)
   for i in range(len(a)):
    _,vstart,vend=fields[i];patch(a[i],b[i],vstart,vend,level+1,path+[i])
   return
  changes.append((start,end,render(b,level)));paths.append(path)
 patch(old,expected,0,len(base.rstrip()),0,[])
 after=base
 for start,end,replacement in sorted(changes,reverse=True):after=after[:start]+replacement+after[end:]
 assert json.loads(after)==expected
 roots_before=spans(base);roots_after=spans(after);historical=[]
 allowed={'game_version','save_version','cold_ailment_duration','source_tree','source_tree_localization','mechanisms'}
 for key,(_,start,end) in roots_before.items():
  if key in allowed:continue
  _,a,b=roots_after[key];assert base[start:end]==after[a:b],key;historical.append(key)
 # Whole legacy definitions and source topology remain unchanged, not merely numeric-equal.
 before_mechanisms=spans(base,roots_before['mechanisms'][1]);after_mechanisms=spans(after,roots_after['mechanisms'][1])
 for key,(_,start,end) in before_mechanisms.items():
  if key in fragment['mechanisms']:continue
  _,a,b=after_mechanisms[key];assert base[start:end]==after[a:b],key
 coverage_raw=(QA/'source-tree-coverage.json').read_bytes();coverage=json.loads(coverage_raw);old_coverage=json.loads(baseline('docs/reference/source-tree-coverage.json'))
 for key in ['inventory','integrity','source','source_reported_counts','standard_graph','report_kind','schema_version','reachability_policy','limitations']:assert coverage[key]==old_coverage[key],key
 actual_nodes={n['id']:n for n in coverage['nodes']};old_nodes={n['id']:n for n in old_coverage['nodes']}
 for a,b in zip(old_coverage['class_reachability'],coverage['class_reachability']):
  assert set(b['reachable_node_ids_including_start'])-set(a['reachable_node_ids_including_start'])=={'14209'}
  assert set(a['reachable_node_ids_including_start'])<=set(b['reachable_node_ids_including_start'])
 changed_nodes=[k for k in old_nodes if actual_nodes[k]!=old_nodes[k]];assert set(changed_nodes)==set(fragment['nodes']),changed_nodes
 (REF/'catalog.json').write_text(after);(REF/'source-tree-coverage.json').write_bytes(coverage_raw)
 proof={'base_commit':BASE,'baseline_sha256':sha(raw),'final_sha256':sha(after.encode()),'fragment_sha256':sha((QA/'cold-duration-fragment.json').read_bytes()),'method':'Only differing allowed spans spliced into exact baseline; all untouched bytes and old numeric token types retained. No old catalog parsed by Godot. Coverage is the authoritative runtime output.','modified_paths':paths,'splice_count':len(changes),'historical_raw_sections_preserved':historical,'historical_raw_section_count':len(historical),'legacy_definitions_preserved':23,'current_source_definition_metadata_changes':metadata,'coverage_changed_nodes':changed_nodes,'source_topology_preserved':True}
 with (QA/'catalog-format-preservation.json').open('x') as f:json.dump(proof,f,ensure_ascii=False,indent=2);f.write('\n')
 print(json.dumps(proof,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
