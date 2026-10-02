#!/usr/bin/env python3
"""Verify normalized numeric facts, optionally against the exact pinned GGG file.
Default is offline. --source verifies every original occurrence and source SHA256.
--fetch-source saves public data locally for review; raw GGG data is not packaged.
"""
import argparse, collections, hashlib, json, pathlib, urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--source',type=pathlib.Path);ap.add_argument('--fetch-source',type=pathlib.Path);args=ap.parse_args()
registry=json.loads((ROOT/'data/poe_passive_registry.json').read_text());cfg=json.loads((ROOT/'data/passive_balance.json').read_text());manifest=registry['source']
assert cfg['source']==manifest
mods=registry['modifiers'];ids={x['modifier_id']:x for x in mods};assert len(ids)==len(mods)==2974
statuses=collections.Counter(x['status'] for x in mods);assert dict(statuses)==registry['coverage']['unique_status'];assert statuses['supported_archetype']==98
assert sum(len(x['source_refs']) for x in mods)==5357
allrefs=[]
for row in mods:
 assert len(row['source_text_sha256'])==64
 assert row['modifier_id']=='poe1_'+row['source_text_sha256'][:16]
 assert row['status'] in ['unsupported','supported_archetype']
 assert not any(k in row for k in ['icon','position','name','raw_text','flavourText','reminderText'])
 if row['status']=='unsupported':assert row.get('reason')
 else:assert row['family'] in registry['families']
 for ref in row['source_refs']:allrefs.append((ref['kind'],ref['id'],ref['stat_index']))
assert len(set(allrefs))==len(allrefs)
for definition in cfg['definitions'].values():
 calculated=collections.defaultdict(float)
 for ref in definition['source_refs']:
  src=ids[ref['modifier_id']];assert src['status']=='supported_archetype';assert src['source_value']==ref['source_value'];assert src['source_mode']==ref['source_mode'];assert ref['source_node'] in src['source_refs']
  calculated[ref['target_stat']]+=ref['source_value']*(.01 if ref['source_mode']=='increased' else 1)*ref['scale']*(ref['reference_base'] if ref['reference_base'] is not None else 1)
 assert calculated.keys()==definition['stats'].keys()
 for stat,value in calculated.items():assert abs(value-definition['stats'][stat])<1e-8
if args.fetch_source:
 args.fetch_source.parent.mkdir(parents=True,exist_ok=True)
 content=urllib.request.urlopen(manifest['data_url']).read()
 assert hashlib.sha256(content).hexdigest()==manifest['data_sha256']
 args.fetch_source.write_bytes(content);args.source=args.fetch_source
if args.source:
 content=args.source.read_bytes();assert len(content)==manifest['data_bytes'];assert hashlib.sha256(content).hexdigest()==manifest['data_sha256']
 data=json.loads(content);masters={}
 for node in data['nodes'].values():
  for effect in node.get('masteryEffects',[]):
   if str(effect['effect']) in masters:assert masters[str(effect['effect'])]==effect['stats']
   masters[str(effect['effect'])]=effect['stats']
 assert len(data['nodes'])==3390 and len(masters)==353
 count=0
 for row in mods:
  for ref in row['source_refs']:
   lines=data['nodes'][ref['id']].get('stats',[]) if ref['kind']=='node' else masters[ref['id']]
   text=lines[ref['stat_index']];assert hashlib.sha256(text.encode()).hexdigest()==row['source_text_sha256'];count+=1
 assert count==5357
 print(f'PASS: pinned raw source SHA256 and all {count} modifier occurrences verified')
else:print('PASS: offline registry coverage, references, and calibrated formulas; original source bytes not re-fetched')
