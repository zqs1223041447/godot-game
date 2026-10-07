"""Pack Blender-authored RGBA frames without resampling or per-frame recentering."""
from PIL import Image, ImageDraw, ImageChops
from pathlib import Path
import json, hashlib, csv, zipfile
OUT=Path(__file__).resolve().parent
meta=json.loads((OUT/'atlas_metadata.json').read_text())
assert not meta['test_only'] and len(meta['frames'])==144, '144 finalized frames required'
assert len({f['index'] for f in meta['frames']})==144
atlas=Image.new('RGBA',(2048,1728),(0,0,0,0));bounds=[];hashes=[]
for rec in sorted(meta['frames'],key=lambda r:r['index']):
 idx=rec['index'];im=Image.open(OUT/rec['file']);assert im.mode=='RGBA' and im.size==(128,192)
 a=im.getchannel('A');b=a.getbbox();assert b is not None
 assert b[0]>0 and b[1]>0 and b[2]<128 and b[3]<192, (idx,'clipping',b)
 assert rec['foot_anchor_px']==[64.0,158.0],(idx,'origin drift',rec['foot_anchor_px'])
 rec['alpha_bounds_px']=list(b);rec['alpha_bounds_8_px']=list(a.point(lambda p:255 if p>=8 else 0).getbbox());rec['body_size_px']=[b[2]-b[0],b[3]-b[1]];rec['visual_top_anchor_px']=[64,b[1]];bounds.append(b)
 hashes.append(hashlib.sha256(im.tobytes()).hexdigest());dest=((idx%16)*128,(idx//16)*192);atlas.alpha_composite(im,dest)
 crop=atlas.crop((*dest,dest[0]+128,dest[1]+192));assert ImageChops.difference(im,crop).getbbox() is None
atlas.save(OUT/'brute_atlas.png',optimize=True)
meta.update({'atlas_size_px':[2048,1728],'all_frame_alpha_bounds_px':[min(b[0] for b in bounds),min(b[1] for b in bounds),max(b[2] for b in bounds),max(b[3] for b in bounds)],'alpha_body_height_range_px':[min(b[3]-b[1] for b in bounds),max(b[3]-b[1] for b in bounds)],'alpha_body_width_range_px':[min(b[2]-b[0] for b in bounds),max(b[2]-b[0] for b in bounds)],'unique_render_count':len(set(hashes)),'atlas_sha256':hashlib.sha256((OUT/'brute_atlas.png').read_bytes()).hexdigest(),'source_files':['generate_heavy_guard.py','pack_heavy_guard.py','heavy_guard.blend','heavy_guard_atlas_source.blend'],'qa':{'all_frames_present':True,'all_frames_rgba':True,'all_frames_unclipped':True,'shared_world_ground_anchor':True,'native_frame_pixels_preserved':True,'has_baked_floor_or_shadow':False}})
reference=next(r for r in meta['frames'] if r['index']==36)
meta['scale_reference']={'reference_frame_index':36,'reference_direction':'S','reference_animation':'idle','reference_body_height_px':reference['body_size_px'][1],'target_world_body_height':70,'recommended_uniform_scale':round(70/reference['body_size_px'][1],6),'semantics':'Multiply Sprite2D source pixels uniformly into world units; parent may choose final scale after game QA.'}
# Frame native bounds and world origin are separate, allowing a stable collision/shadow anchor.
(OUT/'atlas_metadata.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2))
with (OUT/'frame_table.csv').open('w',newline='') as f:
 w=csv.writer(f);w.writerow(['index','direction','animation','frame','origin_x','origin_y','alpha_left','alpha_top','alpha_right','alpha_bottom','head_x','head_y'])
 for r in meta['frames']:w.writerow([r['index'],r['direction'],r['animation'],r['frame'],*r['foot_anchor_px'],*r['alpha_bounds_px'],*r['head_top_anchor_px']])
background=(56,64,53,255)
sheet=Image.new('RGBA',(1024,320),background);draw=ImageDraw.Draw(sheet)
for d,name in enumerate(meta['direction_order']):
 im=Image.open(OUT/'frames'/f'{d*18:03d}.png').convert('RGBA');sheet.alpha_composite(im,(d*128,17));draw.text((d*128+8,6),f'{d}: {name}',fill=(235,226,202,255))
 # Approximately 45px body: same coherent whole-frame downscale for every direction.
 display_factor=meta['scale_reference']['recommended_uniform_scale']*.65
 small=im.resize((round(128*display_factor),round(192*display_factor)),Image.Resampling.LANCZOS);sheet.alpha_composite(small,(d*128+(128-small.width)//2,220))
draw.text((8,206),'Top: 128x192 source | Bottom: world scale 0.729 x zoom 0.65, S body approximately 45px',fill=(235,226,202,255));sheet.convert('RGB').save(OUT/'direction_contact_sheet.png')
# S-facing all three animation loops in their contractual sequence.
sheet=Image.new('RGBA',(8*128,3*218),background);draw=ImageDraw.Draw(sheet)
for row,(name,off,count) in enumerate([('idle',0,4),('walk',4,8),('attack',12,6)]):
 for frame in range(count):
  idx=2*18+off+frame;im=Image.open(OUT/'frames'/f'{idx:03d}.png');sheet.alpha_composite(im,(frame*128,row*218+18));draw.text((frame*128+7,row*218+5),f'{name} {frame}',fill=(235,226,202,255))
sheet.convert('RGB').save(OUT/'animation_contact_sheet.png')
# Visual motion preview, only proof contact sheet background; atlas remains transparent.
for name,off,count in [('idle',0,4),('walk',4,8),('attack',12,6)]:
 frames=[]
 for f in range(count):
  canvas=Image.new('RGBA',(128,192),background);canvas.alpha_composite(Image.open(OUT/'frames'/f'{18+off+f:03d}.png'));frames.append(canvas.convert('RGB'))
 frames[0].save(OUT/f'{name}_preview.gif',save_all=True,append_images=frames[1:],duration=83,loop=0,disposal=2)
print('PACKED',meta['atlas_size_px'],'ALPHA',meta['all_frame_alpha_bounds_px'],'HEIGHT',meta['alpha_body_height_range_px'],'UNIQUE',meta['unique_render_count'])
