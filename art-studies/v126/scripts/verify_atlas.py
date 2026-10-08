"""Read-only atlas/metadata check, including decoded-pixel provenance; no engine run."""
import ast,hashlib,json,math,os
from pathlib import Path
from PIL import Image
P=Path(os.environ.get('V126_OUTPUT_DIR',Path(__file__).resolve().parents[1])).resolve()
m=json.loads((P/'atlas/ranger_v126.json').read_text());audit=json.loads((P/'reports/atlas-audit.json').read_text());cfg=json.loads((P/'reports/render-config.json').read_text())
required={'schema_version','coordinate_space','texture_path','direction_count','world_units_per_source_pixel','frames_per_direction','fps','clips','contact_shadow_half_size_world','frames','provenance'}
assert set(m)==required and m['schema_version']==1 and m['coordinate_space']=='world'
assert m['texture_path']=='res://art-studies/v126/atlas/ranger_v126.png'
assert m['direction_count']==8 and m['frames_per_direction']==45<=64 and m['fps']==12
assert m['clips']=={'idle':[0,30],'walk':[30,9],'attack':[39,6]}
assert len(m['frames'])==360 and len(audit['records'])==256
assert abs(m['world_units_per_source_pixel']*.65-.5)<1e-12
assert m['provenance']['walk_source_indices']==[0,2,4,5,7,9,11,12,14]
assert m['provenance']['attack_source_frames']==[23,25.5,28,30.5,33,38]
path=P/'atlas/ranger_v126.png';assert hashlib.sha256(path.read_bytes()).hexdigest()==audit['atlas_sha256']
with Image.open(path) as im:
 assert im.mode=='RGBA' and im.size==(2560,3584)
 for row in audit['records']:
  x,y,w,h=row['region'];crop=im.crop((x,y,x+w,y+h));assert crop.size==(160,224)
  assert hashlib.sha256(crop.tobytes()).hexdigest()==row['rgba_pixels_sha256']
  b=crop.getchannel('A').getbbox();assert b and b[0]>0 and b[1]>0 and b[2]<160 and b[3]<224
 for f in m['frames']:
  assert set(f)=={'region','foot'} and f['foot']==[80,174]
  x,y,w,h=f['region'];assert all(isinstance(v,int) for v in f['region']) and w==160 and h==224 and x>=0 and y>=0 and x+w<=im.width and y+h<=im.height
for d in range(8):
 fs=m['frames'][d*45:(d+1)*45]
 for i in range(10):assert fs[i*3]==fs[i*3+1]==fs[i*3+2]
 assert len({tuple(f['region']) for f in fs[:30]})==10
for p in (P/'scripts').glob('*.py'):ast.parse(p.read_text(),filename=p.name)
for p in (P/'licenses').glob('*.txt'):assert 'CC0 1.0 Universal' in p.read_text()
assert (P/'.gdignore').is_file()
print('PASS:256 unique decoded-RGBA regions match source hashes;360refs/45perdirection,12fps,Idle30/Walk9/Attack6,8directions,160x224fixed cells/root80,174,scale,alpha margins,licenses and syntax verified. Dynamic/game acceptance not performed.')
