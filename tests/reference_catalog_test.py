#!/usr/bin/env python3
"""Offline deliverable checks: exhaustive links/assets, geometry, no network dependencies."""
import importlib.util
import json
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'docs/reference'
class Inspector(HTMLParser):
    def __init__(self):
        super().__init__(); self.ids=[]; self.links=[]; self.assets=[]; self.viewbox=None; self.node_ids=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a:self.ids.append(a['id'])
        if tag=='a':self.links.append(a.get('href',''))
        if tag in ['img','script','link']:
            url=a.get('src',a.get('href',''))
            if url:self.assets.append(url)
        if tag=='svg' and a.get('id')=='passive-map':self.viewbox=list(map(float,a['viewbox'].split()))
        if 'data-node' in a:self.node_ids.append(a['data-node'])

def main():
    source=(REF/'index.html').read_text()
    inspector=Inspector(); inspector.feed(source)
    data=json.loads((REF/'catalog.json').read_text())
    assert not [x for x,n in Counter(inspector.ids).items() if n>1], 'Duplicate document IDs'
    assert not [x for x in inspector.links if x.startswith('#') and x[1:] not in inspector.ids], 'Broken internal links'
    assert not [x for x in inspector.assets if '://' in x or x.startswith('//')], 'Network-dependent resource'
    for asset in inspector.assets:assert (REF/asset).is_file(), 'Missing asset '+asset
    for cat in ['skills','supports','equipment','affixes','fixed_items','jewels','jewel_affixes','passives','mechanisms','monsters']:
        for key in data[cat]:assert f'{cat}-{key}' in inspector.ids, 'Unbrowsable entry '+key
    assert set(inspector.node_ids)==set(data['passives']), 'Tree omits a runtime node'
    x,y,w,h=inspector.viewbox
    for node in data['passives'].values():
        nx,ny=node['position'];assert x+19<=nx<=x+w-19 and y+19<=ny<=y+h-19, 'Tree clips node'
    for sample in data['special_coverage'].values():
        for s in sample['connected']['active_sources'].values():
            cx,cy=s['position'];r=s['radius'];assert x<=cx-r and cx+r<=x+w and y<=cy-r and cy+r<=y+h, 'Tree clips coverage circle'
    script=(REF/'reference.js').read_text()
    for unsupported in ['fetch(', 'XMLHttpRequest', 'import(', 'localStorage', 'sessionStorage']:
        assert unsupported not in script, 'Offline script includes external/persistent dependency '+unsupported
    assert 'font-size:16px' in (REF/'reference.css').read_text()
    spec=importlib.util.spec_from_file_location('generator',ROOT/'tools/build_reference.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    art=json.loads((REF/'art/manifest.json').read_text())
    assert art['status']=='complete'
    assert len(inspector.assets)==len(art['entries']), 'Runtime artwork missing from an entry'
    assert module.build(data,art)==source, 'Generated HTML is stale'
    assert module.build(data,art)==module.build(data,art), 'Nondeterministic generator'
    print(f'Reference catalog: {len(inspector.ids)} unique anchors, {len(inspector.links)} links, {len(inspector.assets)} local images; complete geometry and deterministic HTML passed')
if __name__=='__main__':main()
