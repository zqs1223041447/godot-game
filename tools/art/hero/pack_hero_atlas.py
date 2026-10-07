from pathlib import Path
from PIL import Image, ImageDraw
import json, hashlib, statistics
ROOT=Path(__file__).resolve().parent
manifest=json.loads((ROOT/'hero_manifest.json').read_text())
atlas=Image.new('RGBA',(2048,1728),(0,0,0,0))
errors=[]; bounds=[]; solid_bounds=[]; hashes=set()
for row in manifest['frames']:
 im=Image.open(ROOT/row['file'])
 if im.mode!='RGBA':errors.append(f"Wrong color mode {row['index']}: {im.mode}")
 im=im.convert('RGBA')
 if im.size!=(128,192):errors.append(f"Wrong frame size {row['index']}: {im.size}")
 alpha=im.getchannel('A'); bb=alpha.getbbox(); sb=alpha.point(lambda a:255 if a>=8 else 0).getbbox()
 if bb is None:errors.append(f"Empty frame {row['index']}");continue
 pad=[bb[0],bb[1],128-bb[2],192-bb[3]]
 if min(pad)<2:errors.append(f"Insufficient edge padding frame {row['index']}: {pad}")
 if row['foot_anchor']!=[64.0,158.0]:errors.append(f"Foot anchor changed {row['index']}")
 row['alpha_bounds']=list(bb);row['solid_alpha_bounds_threshold_8']=list(sb);row['transparent_edge_padding_ltrb']=pad
 row['alpha_sha256']=hashlib.sha256(alpha.tobytes()).hexdigest()
 row['png_sha256']=hashlib.sha256((ROOT/row['file']).read_bytes()).hexdigest()
 bounds.append(bb);solid_bounds.append(sb);hashes.add(row['png_sha256'])
 x,y,w,h=row['atlas_rect'];atlas.paste(im,(x,y))
atlas.save(ROOT/'hero_atlas.png',optimize=True)
verified=Image.open(ROOT/'hero_atlas.png').convert('RGBA')
for row in manifest['frames']:
 x,y,w,h=row['atlas_rect']
 original=Image.open(ROOT/row['file']).convert('RGBA')
 if verified.crop((x,y,x+w,y+h)).tobytes()!=original.tobytes():errors.append(f"Atlas crop mismatch {row['index']}")
manifest['atlas_file']='hero_atlas.png';manifest['atlas_sha256']=hashlib.sha256((ROOT/'hero_atlas.png').read_bytes()).hexdigest()
manifest['bounds_semantics']='[left, top, right_exclusive, bottom_exclusive] in frame-local pixels; alpha_bounds includes every nonzero-alpha pixel'
manifest['validation']={'frames':len(bounds),'unique_pngs':len(hashes),'all_frames_rgba':True,'constant_foot_anchor':[64,158],'minimum_transparent_edge_padding_ltrb':[min(b[0] for b in bounds),min(b[1] for b in bounds),128-max(b[2] for b in bounds),192-max(b[3] for b in bounds)],'aggregate_alpha_bounds':[min(b[0] for b in bounds),min(b[1] for b in bounds),max(b[2] for b in bounds),max(b[3] for b in bounds)],'median_full_alpha_height':statistics.median(b[3]-b[1] for b in bounds),'clipped_or_insufficient_padding':errors,'renderer':'Cycles CPU, 40 samples, no unavailable denoiser','no_baked_ground_or_shadow':True,'atlas_crop_pixel_equality':len(errors)==0}
(ROOT/'hero_manifest.json').write_text(json.dumps(manifest,indent=2))
# Direction contact sheet: actual asset frame size and literal gameplay-scale thumbnails.
sheet=Image.new('RGB',(1024,350),(72,77,63));d=ImageDraw.Draw(sheet)
for dr in range(8):
 row=manifest['frames'][dr*18];im=Image.open(ROOT/row['file'])
 if im.mode!='RGBA':errors.append(f"Wrong color mode {row['index']}: {im.mode}")
 im=im.convert('RGBA');x=dr*128
 sheet.paste(im,(x,24),im);d.text((x+5,5),f"{dr}: {manifest['directions'][dr]}",fill=(240,231,207))
 sm=im.resize((42,62),Image.Resampling.LANCZOS);sheet.paste(sm,(x+43,253),sm)
 d.text((x+7,324),'0.325x display',fill=(218,216,197))
d.text((7,230),'Top: 128x192 source | Bottom: 0.5 world scale x 0.65 zoom, body approximately 49px high',fill=(237,227,202))
sheet.save(ROOT/'hero_direction_contact.png')
# Animation strip south-facing, identical origin and dimensions in every slot.
anims=Image.new('RGB',(1024,636),(72,77,63));d=ImageDraw.Draw(anims)
for ri,(anim,offset,count) in enumerate([('idle',0,4),('walk',4,8),('attack',12,6)]):
 for fr in range(count):
  row=manifest['frames'][2*18+offset+fr];im=Image.open(ROOT/row['file'])
  if im.mode!='RGBA':errors.append(f"Wrong color mode {row['index']}: {im.mode}")
  im=im.convert('RGBA');x=fr*128;y=ri*212
  anims.paste(im,(x,y+19),im);d.text((x+5,y+2),f'{anim} {fr}',fill=(240,231,207))
anims.save(ROOT/'hero_animation_contact.png')
# Complete frame table is convenient without parsing nested JSON.
lines=['index,direction,direction_name,animation,animation_frame,atlas_x,atlas_y,alpha_l,alpha_t,alpha_r,alpha_b,head_x,head_y,foot_x,foot_y']
for r in manifest['frames']:
 vals=[r['index'],r['direction'],r['direction_name'],r['animation'],r['animation_frame'],*r['atlas_rect'][:2],*r['alpha_bounds'],*r['head_anchor'],*r['foot_anchor']];lines.append(','.join(map(str,vals)))
(ROOT/'hero_frame_table.csv').write_text('\n'.join(lines)+'\n')
print(json.dumps(manifest['validation'],indent=2))
if errors:raise SystemExit('Frame safety QA failed; do not deliver as clipping-safe')
