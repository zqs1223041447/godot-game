#!/usr/bin/env python3
"""Deterministic connected path samples; runtime independently verifies these. No raw source assets."""
import json,collections,random,math,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[1];cfg=json.load(open(ROOT/'data/passive_balance.json'));defs=cfg['definitions'];caps=cfg['player_passive_caps'];base=cfg['reference_base']
sectors=['ember','grove','tide','gale','aegis','prism'];counts=[1,2,4,6,8,9];nodes={'origin':{'neighbors':set(),'stats':{},'type':'start'}}
small=[['ember_power','ember_fervor','ember_power'],['grove_vitality','grove_guard','grove_vitality'],['tide_capacity','tide_flow','tide_capacity'],['gale_alacrity','gale_stride','gale_alacrity'],['aegis_capacity','aegis_recovery','aegis_capacity'],['prism_vigor','prism_reserve','prism_recovery']]
def nid(s,r,i):return f'{s}_{r}_{i}'
def link(a,b):nodes[a]['neighbors'].add(b);nodes[b]['neighbors'].add(a)
for si,s in enumerate(sectors):
 for r,c in enumerate(counts,1):
  for i in range(c):
   kind='socket' if (r,i) in [(3,0),(5,3)] else 'notable' if (r,i) in [(3,2),(4,3),(5,6),(6,4)] else 'small'
   id=nid(s,r,i);mech=cfg['node_overrides'].get(id, f'{s}_mastery' if kind=='notable' else small[si][(r+i)%3]);
   nodes[id]={'type':kind,'stats':{} if kind=='socket' else defs[mech]['stats'],'neighbors':set(),'mechanism':None if kind=='socket' else mech}
for r,c in enumerate(counts,1):
 ring=[nid(s,r,i) for s in sectors for i in range(c)]
 for a,b in zip(ring,ring[1:]+ring[:1]):link(a,b)
for s in sectors:
 link('origin',nid(s,1,0))
 for r in range(2,7):
  for i in range(counts[r-1]):link(nid(s,r,i),nid(s,r-1,min(counts[r-2]-1,int((i+.5)*counts[r-2]/counts[r-1]))))
def total(ids):
 out=collections.defaultdict(float)
 for id in ids:
  for stat,v in nodes[id]['stats'].items():out[stat]+=v
 return {s:base.get(s,0)+min(out[s],caps[s]) for s in caps}
def metrics(s):
 d=s['damage']/18;g=s['global_increased'];p=s['projectile_increased'];e=s['elemental_increased'];a=s['area_increased'];sp=s['attack_speed']/1.7
 return {'basic_dps':d*(1+g+p)*sp,'tornado_arrow':d*(1+g+p+.4*e),'elemental_projectile':d*(1+g+p+e),'explosion':d*(1+g+a+e),'ehp':(s['max_health']+s['max_shield'])/180,'movement':s['move_speed']/240,'mana_sustain':s['mana_regen']/9,'shield_recovery':s['shield_regen']/13}
weights={
 'offense':{'damage':1/18,'attack_speed':1/1.7,'global_increased':1,'projectile_increased':.8,'elemental_increased':.5,'area_increased':.35},
 'defense':{'max_health':1/180,'max_shield':1/180,'shield_regen':.2/13,'move_speed':.05/240},
 'hybrid':{'damage':.5/18,'attack_speed':.5/1.7,'global_increased':.5,'projectile_increased':.35,'elemental_increased':.25,'area_increased':.2,'max_health':.5/180,'max_shield':.5/180,'shield_regen':.1/13},
 'mana':{'max_mana':.4/100,'mana_regen':1/9,'max_shield':.1/60},
 'speed':{'move_speed':1/240,'attack_speed':.5/1.7},
 'elemental':{'damage':1/18,'global_increased':1,'projectile_increased':.7,'elemental_increased':1,'area_increased':.6},
}
cases=[]
for pts in [12,24,48,96,180]:
 for mode,w in weights.items():
  for si,s in enumerate(sectors):
   allocated=['origin'];frontier={nid(s,1,0)}
   for step in range(pts):
    before=total(allocated);best=None;best_score=-1
    for candidate in sorted(frontier):
     # Look ahead to a target through an actual shortest unallocated route.
     # Candidate selection includes a discounted one-hop onward benefit.
     add=total(allocated+[candidate]);score=sum((add[k]-before[k])*v for k,v in w.items())
     future=max([sum(nodes[n]['stats'].get(k,0)*v for k,v in w.items()) for n in nodes[candidate]['neighbors'] if n not in allocated] or [0])
     score+=.25*future
     if score>best_score:best=candidate;best_score=score
    allocated.append(best);frontier.update(nodes[best]['neighbors']);frontier-=set(allocated)
   cases.append({'id':f'{mode}_{s}_{pts}','profile':mode,'points':pts,'allocation_order':allocated[1:],'metrics':metrics(total(allocated))})
 # deterministic connected random allocations broaden regression beyond optimizing heuristics
 for seed in range(12):
  rng=random.Random(20261002+seed);allocated=['origin'];frontier=set(nodes['origin']['neighbors'])
  for step in range(pts):
   n=rng.choice(sorted(frontier));allocated.append(n);frontier.update(nodes[n]['neighbors']);frontier-=set(allocated)
  cases.append({'id':f'random_{seed}_{pts}','profile':'random','points':pts,'allocation_order':allocated[1:],'metrics':metrics(total(allocated))})
bounds={12:{'basic_dps':1.8,'elemental_projectile':1.7,'explosion':1.7,'ehp':1.65},24:{'basic_dps':2.6,'elemental_projectile':2.1,'explosion':2.1,'ehp':2.1},48:{'basic_dps':3.1,'elemental_projectile':2.5,'explosion':2.5,'ehp':2.35},96:{'basic_dps':3.4,'elemental_projectile':2.6,'explosion':2.6,'ehp':2.35},180:{'basic_dps':3.4,'elemental_projectile':2.6,'explosion':2.6,'ehp':2.35}}
summary={}
violations=[]
for pts in bounds:
 rows=[c for c in cases if c['points']==pts];mx={k:max(c['metrics'][k] for c in rows) for k in rows[0]['metrics']};summary[pts]=mx
 print(pts,{k:round(v,4) for k,v in mx.items()})
 for k,maxv in bounds[pts].items():
  if mx[k]>maxv+1e-6: violations.append((pts,k,mx[k],maxv))
if violations: raise SystemExit('ENVELOPE FAIL: '+repr(violations))
artifact={'schema_version':1,'policy_version':cfg['balance_revision'],'seed':20261002,'method':'Connected legal one-point allocations, six optimization weight profiles from each of six first branches, plus twelve seeded randomized builds per point tier. A regression sample, not an exhaustive optimum proof. Gear and jewels excluded to isolate talent budget.','bounds':bounds,'summary':summary,'cases':cases}
(ROOT/'tests/passive_balance_cases.json').write_text(json.dumps(artifact,ensure_ascii=False,indent=2)+'\n')
# Count reachable minimum costs; preserved graph means radial depth equals minimum distance.
dist={'origin':0};q=collections.deque(['origin'])
while q:
 n=q.popleft()
 for m in nodes[n]['neighbors']:
  if m not in dist:dist[m]=dist[n]+1;q.append(m)
print('overrides', {n:dist[n] for n in cfg['node_overrides']})
print('placements',dict(collections.Counter(n['mechanism'] for n in nodes.values() if n.get('mechanism'))))
print('full tree caps',total(list(nodes)))
