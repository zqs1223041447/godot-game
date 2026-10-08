#!/usr/bin/env python3
"""Decode glTF/BIN working-copy animation accessors; execute no package content."""
from pathlib import Path
import json,hashlib,numpy as np
R=Path(__file__).resolve().parents[1];M=json.loads((R/'reports/source-manifest.json').read_text())
p=Path(M['asset_paths']['Female_Peasant_Body'])
if not p.exists():p=R/'work_sources'/next(f['entry'] for f in M['files'] if f['entry'].endswith('/Female_Peasant_Body.gltf'))
g=json.loads(p.read_text());buffers=[(p.parent/b['uri']).read_bytes() for b in g['buffers']]
def accessor(i):
 a=g['accessors'][i];assert 'sparse' not in a;v=g['bufferViews'][a['bufferView']];typ={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']];n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];dt=np.dtype(typ);stride=v.get('byteStride',dt.itemsize*n)
 return np.ndarray((a['count'],n),dtype=dt,buffer=buffers[v['buffer']],offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(stride,dt.itemsize)).copy()
a=next(a for a in g['animations'] if a['name']=='Jog_Fwd_Loop');channels=[]
for c in a['channels']:
 sampler=a['samplers'][c['sampler']];values=accessor(sampler['output']);times=accessor(sampler['input']).reshape(-1)
 channels.append({'node':g['nodes'][c['target']['node']]['name'],'path':c['target']['path'],'sample_count':len(times),'time_range_seconds':[float(times.min()),float(times.max())],'maximum_component_range':float(np.ptp(values.astype(float),axis=0).max())})
r={'working_gltf':str(p),'bin_sha256':hashlib.sha256(buffers[0]).hexdigest(),'source_bin_sha256':next(f['source_sha256'] for f in M['files'] if f['entry'].endswith('/Female_Peasant_Body.bin')),'animation_name':a['name'],'channel_count':len(channels),'samples_per_channel':sorted(set(c['sample_count'] for c in channels)),'varying_channels':sum(c['maximum_component_range']>0 for c in channels),'maximum_channel_component_range':max(c['maximum_component_range'] for c in channels),'channels':channels,'conclusion':'Constant T-pose; clip name is not evidence of jogging motion.'}
assert r['bin_sha256']==r['source_bin_sha256'] and r['channel_count']==195 and r['varying_channels']==0
(R/'reports/source-jog-working-copy-recheck.json').write_text(json.dumps(r,indent=2));print({k:v for k,v in r.items() if k!='channels'})
