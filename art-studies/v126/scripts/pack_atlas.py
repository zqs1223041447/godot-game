"""Pack the fixed256 authored renders into one texture and45refs/direction.
No source rescaling: PNG RGBA pixels are copied1:1 into atlas cells.
"""
from pathlib import Path
import json,hashlib,math,os
from PIL import Image,ImageDraw,ImageFont
P=Path(os.environ.get('V126_OUTPUT_DIR',Path(__file__).resolve().parents[1])).resolve()
cfg=json.loads((P/'reports/render-config.json').read_text());W,H=cfg['cell_size'];root=cfg['root_anchor_px'];directions=cfg['direction_order'];columns=16
atlas=Image.new('RGBA',(columns*W,16*H),(0,0,0,0));records=[];physical={};alpha=[]
for d,name in enumerate(directions):
 for state,offset in [('idle',0),('walk',10),('attack',26)]:
  for i,fr in enumerate(cfg['source_frames'][state]):
   file=P/'frames'/state/name/f'{i:02d}.png';im=Image.open(file).convert('RGBA');assert im.size==(W,H)
   n=d*32+offset+i;x=(n%columns)*W;y=(n//columns)*H;b=im.getchannel('A').getbbox();assert b and b[0]>0 and b[1]>0 and b[2]<W and b[3]<H,(state,name,i,b)
   atlas.paste(im,(x,y));physical[(name,state,i)]={'region':[x,y,W,H],'foot':[round(root[0]),round(root[1])]}
   records.append({'direction':name,'state':state,'source_index':i,'source_frame':fr,'region':[x,y,W,H],'source_png_sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'rgba_pixels_sha256':hashlib.sha256(im.tobytes()).hexdigest(),'alpha_bounds_px':list(b)})
   alpha.append(b)
assert len(records)==256
atlas_path=P/'atlas/ranger_v126.png';atlas.save(atlas_path)
walk_indices=[round(i*16/9) for i in range(9)]
assert walk_indices==[0,2,4,5,7,9,11,12,14]
frames=[]
for name in directions:
 frames.extend(physical[(name,'idle',i)] for i in range(10) for _ in range(3))
 frames.extend(physical[(name,'walk',i)] for i in walk_indices)
 frames.extend(physical[(name,'attack',i)] for i in range(6))
assert len(frames)==8*45
fit=.7436822466639094
meta={'schema_version':1,'coordinate_space':'world','texture_path':'res://art-studies/v126/atlas/ranger_v126.png','direction_count':8,'world_units_per_source_pixel':1/(2*.65),'frames_per_direction':45,'fps':12,'clips':{'idle':[0,30],'walk':[30,9],'attack':[39,6]},'contact_shadow_half_size_world':[32,10],'frames':frames,'provenance':{'study':'v126 Ranger8direction authored atlas','runtime_integration':'Research artifact only. No production runtime changed. .gdignore prevents automatic import. Texture path must be mapped when authorized integration occurs.','source_geometry':'Final v12313original meshes and skinned shoulder bridge, from isolated v125scene','source_scene_sha256':cfg['source_blend_sha256'],'direction_order':directions,'direction_yaw_degrees':cfg['direction_yaw_degrees'],'source_display_density':2,'cell_size':[W,H],'fixed_root_anchor_px':[round(root[0]),round(root[1])],'nominal_camera_zoom':.65,'camera_elevation_degrees':55,'world_scale_contract':'1/(2*0.65) world units per source pixel; at0.65camera gives0.5display pixels per source pixel','global_fps':12,'logical_clip_seconds':{'idle':2.5,'walk':.75,'attack':.5},'physical_unique_frames_per_direction':{'idle':10,'walk':16,'attack':6},'logical_references_per_direction':{'idle':30,'walk':9,'attack':6},'idle_repeat_each_source':3,'walk_source_indices':walk_indices,'walk_source_phases':[i/16 for i in walk_indices],'walk_full_source_phases':[i/16 for i in range(16)],'walk_original_fitted_east_cycle_seconds':fit,'walk_cycle_error_percent':(.75/fit-1)*100,'walk_blend':{'walk':.8,'jog':.2,'walk_phase_offset':.19375,'jog_phase_offset':.11607142659474393},'walk_clock_limit':'Elapsed-time at12fps, not distance-driven. East timing mismatch~0.85%; diagonal/depth projected stride differs. No perfect foot-lock claim.','attack_source_frames':cfg['source_frames']['attack'],'attack_sampling':cfg['attack_sampling_note'],'attack_events':'Recovery-only visuals. Existing0.5s presentation cue clock is independent; release, damage, collision, cooldown untouched.','static_review':'Initial8directionf23stills inspected; full export static sheets inspected separately','dynamic_game_acceptance':'Not accepted by this artifact-only task','shadow':'No ground/shadow baked into alpha. Existing runtime root-centered ellipse stays independent.'}}
(P/'atlas/ranger_v126.json').write_text(json.dumps(meta,indent=2)+'\n')
# Verify all cropped atlas RGBA bytes exactly reproduce each final input render.
with Image.open(atlas_path) as verify:
 for r in records:
  x,y,w,h=r['region'];crop=verify.crop((x,y,x+w,y+h));assert hashlib.sha256(crop.tobytes()).hexdigest()==r['rgba_pixels_sha256']
report={'unique_render_count':256,'atlas_size':list(atlas.size),'atlas_bytes':atlas_path.stat().st_size,'atlas_sha256':hashlib.sha256(atlas_path.read_bytes()).hexdigest(),'atlas_region_rgba_matches_all_source_frames':True,'logical_frames_per_direction':45,'logical_frame_refs_total':360,'maximum_allowed_per_direction':64,'global_fps':12,'direction_count':8,'root_anchor':[round(root[0]),round(root[1])],'all_alpha_within_uniform_cells':True,'minimum_alpha_margin_px':min(min(b[0],b[1],W-b[2],H-b[3]) for b in alpha),'records':records}
(P/'reports/atlas-audit.json').write_text(json.dumps(report,indent=2)+'\n')
# Bounded actual-size review: all8directions at idle0,walk4,attack0,attack5.
fontpath='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';font=ImageFont.truetype(fontpath,11) if Path(fontpath).exists() else ImageFont.load_default();cw=W//2+24;rh=H//2+36
sheet=Image.new('RGB',(cw*8,rh*4+42),(26,31,28));dr=ImageDraw.Draw(sheet);dr.text((12,10),'v126 / actual-size source review / fixed root / no baked shadow',font=font,fill=(232,229,211))
for rr,(state,i) in enumerate([('idle',0),('walk',4),('attack',0),('attack',5)]):
 for dd,name in enumerate(directions):
  im=Image.open(P/'frames'/state/name/f'{i:02d}.png').convert('RGBA').resize((W//2,H//2),Image.Resampling.NEAREST);x=dd*cw+12;y=42+rr*rh+20;sheet.paste(im,(x,y),im);dr.text((x,y-15),f'{name.upper()} {state}{i:02d}',font=font,fill=(232,229,211));cx=x+round(root[0]/2);cy=y+round(root[1]/2);dr.line((cx-3,cy,cx+3,cy),fill=(226,179,83));dr.line((cx,cy-3,cx,cy+3),fill=(226,179,83))
sheet.save(P/'samples/final-8direction-review.png')
print(json.dumps({k:report[k] for k in report if k!='records'},indent=2))
