"""Read byte ranges from the verified official glTF buffer; retain original authored meshes.
No remote scripts are executed. Limit canopy to the first 120k original leaf triangles.
"""
import json,urllib.request,hashlib,struct,copy
from pathlib import Path
R=Path(__file__).resolve().parent;A='tree_small_02';D=R/'assets'/A
manifest=json.load(open(R/'sources'/f'{A}-files.json'));entry=manifest['gltf']['1k']['gltf'];g=json.load(open(R/'sources/tree_small_02_original.gltf.json'));url=entry['include']['tree_small_02.bin']['url'];records=[]
def ranged(start,length):
 end=start+length-1;q=urllib.request.Request(url,headers={'User-Agent':'dot-environment-sample/1.0','Range':f'bytes={start}-{end}'})
 with urllib.request.urlopen(q,timeout=45) as f:
  if f.status!=206:raise RuntimeError('Server does not support bounded range request; stopped without full buffer download')
  b=f.read(length+1);cr=f.headers.get('Content-Range')
 if len(b)!=length:raise RuntimeError('Unexpected range size')
 records.append({'url':url,'range':[start,end],'bytes':length,'content_range':cr,'sha256':hashlib.sha256(b).hexdigest()});print('RANGE',start,length,flush=True);return b
p=g['meshes'][0]['primitives'][1];a=g['accessors'][p['indices']];v=g['bufferViews'][a['bufferView']];count=120000*3
leaf_indices=ranged(v['byteOffset'],count*4);ix=struct.unpack('<'+'I'*count,leaf_indices);n=max(ix)+1
print('Selected leaves vertices',n,'of',g['accessors'][5]['count'],flush=True)
if n>220000:raise RuntimeError('Selected prefix references too much vertex data; stop before large download')
buffer=bytearray();newviews=copy.deepcopy(g['bufferViews']);newaccess=copy.deepcopy(g['accessors'])
for i,v in enumerate(g['bufferViews']):
 if i==9:b=leaf_indices;newaccess[9]['count']=count
 elif 5<=i<=8:
  stride=12 if i in [5,6] else 8;b=ranged(v['byteOffset'],n*stride);newaccess[i]['count']=n
 else:b=ranged(v['byteOffset'],v['byteLength'])
 while len(buffer)%4:buffer+=b'\0'
 newviews[i]['byteOffset']=len(buffer);newviews[i]['byteLength']=len(b);buffer+=b
# Recompute position accessor extents for the retained prefix.
a=newaccess[5];v=newviews[5];xyz=list(struct.iter_unpack('<fff',buffer[v['byteOffset']:v['byteOffset']+v['byteLength']]));a['min']=[min(v[i] for v in xyz) for i in range(3)];a['max']=[max(v[i] for v in xyz) for i in range(3)]
g['bufferViews']=newviews;g['accessors']=newaccess;g['buffers']=[{'uri':'tree_small_02_selected.bin','byteLength':len(buffer)}];g['nodes'][0]['name']='tree_small_02_branch_frame_subset';g['extras']={'source':'https://polyhaven.com/a/tree_small_02','modification':'Original trunk and branches plus prefix of 120000 leaf triangles; selected bounded official byte ranges.'}
(D/'tree_small_02_selected.bin').write_bytes(buffer);(D/'tree_small_02_selected.gltf').write_text(json.dumps(g));(R/'sources/tree-range-downloads.json').write_text(json.dumps(records,indent=2));print('Selected buffer MB',len(buffer)/1e6)
