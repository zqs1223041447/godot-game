#!/usr/bin/env python3
"""Check authoritative v78 export, display and exact historical preservation. No damage engine."""
import hashlib,json,math,re,subprocess
from html.parser import HTMLParser
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];QA=Path(__file__).resolve().parent;REF=ROOT/'docs/reference';BASE='07922581'
def sha(b):return hashlib.sha256(b).hexdigest()
def baseline(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
def near(a,b):assert math.isfinite(a) and abs(a-b)<=max(1e-10,abs(b)*1e-11),(a,b)
def spans(text,start=0):
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
class Page(HTMLParser):
 def __init__(self):super().__init__();self.ids=[];self.links=[];self.assets=[];self.values=[];self.active=None
 def handle_starttag(self,tag,attrs):
  attrs=dict(attrs)
  if 'id' in attrs:self.ids.append(attrs['id'])
  if 'href' in attrs:self.links.append(attrs['href'])
  if 'src' in attrs:self.assets.append(attrs['src'])
  if 'data-elemental-path' in attrs:
   self.values.append([attrs['data-elemental-path'],float(attrs['data-value']),'']);self.active=len(self.values)-1
 def handle_data(self,text):
  if self.active is not None:self.values[self.active][2]+=text
 def handle_endtag(self,tag):
  if tag=='strong':self.active=None

def main():
 raw=(REF/'catalog.json').read_text();data=json.loads(raw);oldraw=baseline('docs/reference/catalog.json').decode();old=json.loads(oldraw)
 rule=data['elemental_conversion'];fragment=json.loads((QA/'elemental-fragment.json').read_text());proof=json.loads((QA/'catalog-format-preservation.json').read_text())
 assert data['game_version']=='0.78.0' and data['save_version']==data['source_tree']['source_policy']==rule['source_policy']==rule['minimum_save_version']==48
 assert rule['equipment_vocabulary']==46 and rule['point_budget']==27 and rule['level']==23 and rule['class_id']==3
 assert len(rule['normal_route'])==25 and len(set(rule['normal_route']))==25
 assert data['elemental_conversion']==fragment['elemental_conversion']
 assert set(data)==set(old)|{'elemental_conversion'}
 before=spans(oldraw);after=spans(raw)
 for key in proof['historical_raw_sections_preserved']:
  _,a,b=before[key];_,c,d=after[key];assert oldraw[a:b]==raw[c:d],key
 assert len(proof['current_source_definition_metadata_changes'])==15
 for key in old['mechanisms']:
  a=old['mechanisms'][key];b=data['mechanisms'][key]
  if key in fragment['mechanisms']:
   b={**b,'source_policy':45,'source_save_version':45,'policy_version':'source-tree:3.29.1:policy:45'}
  assert a==b,key
 expected_nodes={'14122','17380','240','37532','38207','44179','54887','56716','58816','60170','63482','7023','8833'}
 assert set(fragment['nodes'])==set(proof['coverage_changed_nodes'])==expected_nodes
 changed=[]
 for key,node in data['source_tree']['nodes'].items():
  previous=old['source_tree']['nodes'][key]
  if node!=previous:
   changed.append(key);assert key in expected_nodes
   for f in previous:
    if f not in ['execution','mastery_choices']:assert previous[f]==node[f],(key,f)
  if key in ['8833','56716']:assert node['execution']['status']=='full' and len(node['execution']['grants'])==2
  for choice in node['mastery_choices']:
   if choice['effect'] in [4116,53046]:assert choice['execution']['status']=='full'
 assert set(changed)==expected_nodes
 for line,state in fragment['localized_lines'].items():
  assert state==data['source_tree_localization']['lines'][line] and state['status']['implemented'] and '暂未实装' not in state['text']
 acceptance=json.loads((ROOT/'docs/qa/v078-gameplay/reference-acceptance.json').read_text());assert acceptance['passed'] and acceptance['failures']==0
 fixture_bytes={};hits=0;target_cases=0;converted_parts=0;burn_rows=0
 selected={'zero':[],'cold':['cold'],'cold-lightning':['cold','lightning'],'fire-cold-lightning':['fire','cold','lightning']}
 for name,entry in rule['examples'].items():
  fixture=(ROOT/entry['fixture']).read_bytes();assert sha(fixture)==entry['fixture_sha256']==acceptance['fixtures'][name+'.json'];fixture_bytes[name]=json.loads(fixture)
  assert entry['whole_build_valid'] and entry['actual_main_fixture'] and entry['read_only_rebuilt'] and entry['save_attempts']==0
  assert entry['talents']['normal_points']==3-len(selected[name]) and entry['progress']['level']==23
  assert entry['stats']['cold_penetration']==entry['stats']['lightning_penetration']==.06
  assert set(entry['casts'])=={'basic','cleave','tornado'}
  for skill,cast in entry['casts'].items():
   compiled=cast['compiled'];assert compiled['ok'];assert set(cast['hits'])==set(compiled['packets'])
   if selected[name]:assert '零抗性、零护甲目标，含穿透' in cast['summary']
   else:assert 'conversion_profile' not in compiled
   for role,hit in cast['hits'].items():
    hits+=1;packet=hit['packet'];assert packet==compiled['packets'][role]
    details=hit['zero_target']['details'];types=[d['type'] for d in details];assert len(types)==len(set(types))
    assert hit['before_defense']=={d['type']:d['before_defense'] for d in details}
    assert hit['zero_target']==hit['targets']['zero']['resolved']
    if role=='secondary':
     assert hit==rule['examples']['zero']['casts'][skill]['hits'][role]
     assert 'conversion' not in packet and 'penetration' not in packet
     assert 'explode_on_flight_end' not in compiled['snapshot']['effects']
    elif selected[name]:
     split=packet['conversion'];assert split['version']==2 and split['requested']==dict.fromkeys(selected[name],.4)
     if len(selected[name])==3:assert split['remaining_base']==0 and 'physical' not in hit['before_defense']
     for detail in details:
      for part in detail['parts']:
       indices=part['modifier_indices'];assert len(indices)==len(set(indices));assert len(indices)==len(part['modifiers'])
       if len(part['lineage'])==2:assert part['lineage']==['physical',detail['type']];converted_parts+=1
    for tid,target in hit['targets'].items():
     target_cases+=1;assert target['settlement']['ok']
     for d in target['resolved']['details']:
      if 'penetration' in d:
       assert d['type'] in ['cold','lightning'] and d['penetration']==.06
       near(d['resistance'],{'zero':-.06,'armour500':-.06,'elemental75':.69,'elemental90':.84,'elemental_floor':-1}[tid])
       near(d['effective_resistance'],target['resistances'].get(d['type'],0))
   for role,burn in compiled.get('burn_profile',{}).get('roles',{}).items():
    near(burn['fire_before_defense'],cast['hits'][role]['before_defense']['fire']);burn_rows+=1
 for name,fixture in fixture_bytes.items():
  for key in fixture:
   if key not in ['talents','revision','locations']:assert fixture[key]==fixture_bytes['zero'][key],(name,key)
  for uid,location in fixture['locations'].items():
   previous=fixture_bytes['zero']['locations'][uid]
   if location!=previous:
    assert uid in ['gear_000005','gear_000006'] and location['kind']==previous['kind']=='bag',(name,uid)
    assert location['page']==previous['page'] and set(location)==set(previous)=={'kind','page','x','y'},(name,uid)
 coverage=json.loads((REF/'source-tree-coverage.json').read_text());prior=json.loads(baseline('docs/reference/source-tree-coverage.json'))
 assert (REF/'source-tree-coverage.json').read_bytes()==(QA/'source-tree-coverage.json').read_bytes()
 for key in ['inventory','integrity','source','source_reported_counts','standard_graph','report_kind','schema_version','reachability_policy','limitations']:assert coverage[key]==prior[key]
 for a,b in zip(prior['class_reachability'],coverage['class_reachability']):
  assert set(b['reachable_node_ids_including_start'])-set(a['reachable_node_ids_including_start'])=={'8833','56716'}
  assert set(a['reachable_node_ids_including_start'])<=set(b['reachable_node_ids_including_start']) and b['reachable_count_excluding_start']==707
 nodes={n['id']:n for n in coverage['nodes']};assert {n['id'] for n in prior['nodes'] if n!=nodes[n['id']]}==expected_nodes
 html=(REF/'index.html').read_text();page=Page();page.feed(html);oldhtml=baseline('docs/reference/index.html').decode();oldpage=Page();oldpage.feed(oldhtml)
 assert len(page.ids)==len(set(page.ids));assert set(page.ids)-set(oldpage.ids)=={'rules-elemental_conversion'};assert set(oldpage.ids)<=set(page.ids)
 for path,actual,label in page.values:
  expected=rule
  for field in path.split('/'):expected=expected[int(field)] if isinstance(expected,list) else expected.get(field,0)
  assert actual==expected,(path,actual,expected);assert label==format(expected,'.12g'),(path,label)
 assert len(page.values)>400
 for link in page.links:
  if link.startswith('#'):assert link[1:] in page.ids,link
  elif link and not link.startswith(('http:','https:','mailto:')):assert (REF/link.split('#')[0]).is_file(),link
 for asset in page.assets:assert not asset.startswith(('http:','https:')) and (REF/asset).is_file(),asset
 def cards(text):return {re.search(r'id="([^"]+)"',m).group(1):m for m in re.findall(r'<article\b.*?</article>',text,re.S)}
 oldcards=cards(oldhtml);newcards=cards(html);allowed={'rules-source_tree','rules-physical_fire_conversion','rules-source_monster_movement','rules-source_monster_damage_life','rules-source_monster_shield_recharge'}|{'source_passives-'+k for k in expected_nodes}|{'mechanisms-'+k for k in fragment['mechanisms']}
 preserved_cards=[];version_only_cards=[]
 for key,value in oldcards.items():
  if key not in allowed:
   expected=value
   if key.startswith('supports-'):expected=expected.replace('运行版本 '+old['game_version'],'运行版本 '+data['game_version'])
   if key=='rules-equipment':expected=expected.replace('当前存档结构 '+str(old['save_version']),'当前存档结构 '+str(data['save_version']))
   assert expected==newcards[key],key
   (preserved_cards if expected==value else version_only_cards).append(key)
 chapter=newcards['rules-elemental_conversion']
 for phrase in ['仅冻结包，当前不触发','当前装备不会触发','27','-0.06','0.84','历史','零抗性、零护甲目标，含穿透']:assert phrase in chapter,phrase
 protected={};pngs=[]
 tree=subprocess.check_output(['git','ls-tree','-r',BASE,'assets','data','docs/reference'],cwd=ROOT,text=True)
 for line in tree.splitlines():
  info,path=line.split('\t',1)
  if path.startswith(('assets/','data/')) or path.endswith('.png') or path in ['docs/reference/reference.css','docs/reference/reference.js','docs/reference/art/manifest.json']:
   payload=(ROOT/path).read_bytes();git_blob=hashlib.sha1(b'blob '+str(len(payload)).encode()+b'\0'+payload).hexdigest();assert git_blob==info.split()[2],path
   protected[path]=sha(payload)
   if path.endswith('.png'):pngs.append(path)
 actual_pngs={str(p.relative_to(ROOT)) for folder in [ROOT/'assets',ROOT/'data',REF] for p in folder.rglob('*.png')};assert actual_pngs==set(pngs)
 result={'passed':True,'baseline_commit':BASE,'actual_main_fixtures':len(fixture_bytes),'fixture_only_bag_position_changes_allowed':['gear_000005','gear_000006'],'all_other_non_talent_revision_fixture_fields_identical':True,'read_only_casts':12,'hit_packets':hits,'target_settlement_cases':target_cases,'conversion_parts':converted_parts,'burn_inputs_match_final_fire':burn_rows,'authoritative_html_values_and_labels':len(page.values),'historical_raw_sections_preserved':proof['historical_raw_section_count'],'old_cards_byte_preserved':len(preserved_cards),'cards_with_only_current_version_label_change':version_only_cards,'source_changed_nodes':sorted(expected_nodes),'new_reachable_nodes_per_class':['8833','56716'],'reachable_non_start_nodes_per_class':707,'current_source_definition_metadata_only_changes':15,'historical_source_actor_snapshots_preserved':True,'protected_file_count':len(protected),'preserved_png_count':len(pngs),'old_html_anchors_preserved':len(oldpage.ids),'new_html_anchors':['rules-elemental_conversion'],'all_links_and_assets_valid':True,'catalog_sha256':sha(raw.encode()),'coverage_sha256':sha((REF/'source-tree-coverage.json').read_bytes()),'html_sha256':sha(html.encode()),'scope':'One narrow runtime export; actual-Main snapshots reconstructed read-only. Historical JSON tokens and old images retained. No Main rerun, browser/native/UI, packaging or release.'}
 with (QA/'v077-preservation.json').open('x') as f:json.dump(result,f,ensure_ascii=False,indent=2);f.write('\n')
 print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
