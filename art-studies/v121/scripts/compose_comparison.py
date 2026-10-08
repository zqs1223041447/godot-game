"""Compose the requested technical art comparison from our Blender renders.
The existing environment PNG is read-only; this output is explicitly not an in-game screenshot.
"""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,math,hashlib,os
import numpy as np
R=Path(__file__).resolve().parents[1];renders=R/'renders'
scene_path=Path(os.environ.get('V121_BACKGROUND',R.parent/'v118/qa/sparse-assembly.png')).expanduser()
source_sha=hashlib.sha256(scene_path.read_bytes()).hexdigest()
background=Image.open(scene_path).convert('RGBA');assert background.size==(1280,720)
body=Image.open(renders/'ranger-actual-body.png').convert('RGBA');raw=Image.open(renders/'ranger-actual-shadow-raw.png').convert('RGBA');assert body.size==raw.size==background.size
report=json.loads((R/'reports/assembly-report.json').read_text())
# Match the environment export's 0.8% shadow alpha-floor correction, with a finite conservative
# receiving footprint from the posed 3D bounds, fixed sun direction, and a 24px soft-edge margin.
E=report['environment_settings'];a,b,c=next(l for l in E['lights'] if l['type']=='SUN')['rotation_euler']
Rx=np.array([[1,0,0],[0,math.cos(a),-math.sin(a)],[0,math.sin(a),math.cos(a)]]);Ry=np.array([[math.cos(b),0,math.sin(b)],[0,1,0],[-math.sin(b),0,math.cos(b)]]);Rz=np.array([[math.cos(c),-math.sin(c),0],[math.sin(c),math.cos(c),0],[0,0,1]])
ray=Rz@Ry@Rx@np.array([0,0,-1]);lo=report['pose']['min'];hi=report['pose']['max'];px=[]
for x in [lo[0],hi[0]]:
 for y in [lo[1],hi[1]]:
  for z in [lo[2],hi[2]]:
   v=np.array([x,y,z]);q=v-ray*(v[2]/ray[2]);px.append((640+q[0]*1280/27,360-q[1]*1280/27*math.sin(math.radians(55))))
pad=24;rect=[math.floor(min(v[0] for v in px))-pad,math.floor(min(v[1] for v in px))-pad,math.ceil(max(v[0] for v in px))+pad,math.ceil(max(v[1] for v in px))+pad]
al=np.asarray(raw.getchannel('A')).astype(float)/255;al=np.maximum(0,(al-.008)/.992);mask=np.zeros_like(al);mask[rect[1]:rect[3],rect[0]:rect[2]]=1;al*=mask
shadow=Image.new('RGBA',raw.size,(0,0,0,0));shadow.putalpha(Image.fromarray(np.uint8(np.rint(np.clip(al,0,1)*255))));shadow.save(renders/'ranger-actual-shadow.png')
body_bbox=body.getchannel('A').getbbox();body.crop(body_bbox).save(renders/'ranger-actual-body-crop.png')
# Translate, without scaling, the isolated body/shadow to an unobstructed place on the path.
foot_source=(640,360);foot_destination=(710,550);offset=tuple(b-a for a,b in zip(foot_source,foot_destination))
scene=background.copy();scene.alpha_composite(shadow,offset);scene.alpha_composite(body,offset)
board=Image.new('RGBA',(1680,800),(24,29,29,255));board.alpha_composite(scene,(0,64));d=ImageDraw.Draw(board)
font_path='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';font_bold='/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'
f=lambda size:ImageFont.truetype(font_path,size);fb=lambda size:ImageFont.truetype(font_bold,size)
cream=(231,227,212);muted=(165,175,163);gold=(196,173,123)
d.text((26,14),'真实 3D 游侠 · 原尺度对照',font=fb(26),fill=cream)
d.text((830,23),'独立美术样板 / 静态预备姿 / 尚未接入游戏',font=f(17),fill=muted)
d.line((1280,64,1280,784),fill=(60,68,61),width=1)
x=1304
d.text((x,82),'与环境一致的投影',font=fb(22),fill=cream)
for y,line in [(120,'55° 正交 · 47.4074 源像素/米'),(152,'模型静置体高 1.80m'),(184,'竖直体高标尺投影 48.95px'),(222,'姿态外轮廓约 30 × 62px'),(251,'抗锯齿外框为 32 × 64px')]:d.text((x,y),line,font=f(18),fill=muted)
d.text((x,298),'4 倍最近邻放大',font=fb(20),fill=cream)
# Use a background-inclusive source crop so this inset honestly shows the exact actual-size result.
crop_rect=(foot_destination[0]-48,foot_destination[1]-68,foot_destination[0]+48,foot_destination[1]+20)
inset=scene.crop(crop_rect).resize((384,352),Image.Resampling.NEAREST);board.alpha_composite(inset,(1290,335));d.rectangle((1290,335,1673,686),outline=(65,74,62),width=1)
d.text((x,708),'左图保持原始 1280 × 720 像素',font=f(17),fill=muted)
d.text((x,739),'投影体高 ≠ 含前后深度的轮廓高',font=f(16),fill=gold)
# A small label identifies the placed figure without altering its silhouette.
d.text((752,544),'1×',font=fb(17),fill=cream)
board.convert('RGB').save(renders/'ranger-actual-scale-comparison.png')
summary={'background_read_only':str(scene_path),'background_sha256_before':source_sha,'background_sha256_after':hashlib.sha256(scene_path.read_bytes()).hexdigest(),'body_canvas_pixels':list(body.size),'alpha_nonzero_bounds':list(body_bbox),'alpha_nonzero_size':[body_bbox[2]-body_bbox[0],body_bbox[3]-body_bbox[1]],'source_foot_pixel':foot_source,'comparison_foot_pixel':foot_destination,'integer_translation_only':offset,'sprite_scale':1,'comparison_scene_region':[0,64,1280,720],'inset_scale':4,'inset_filter':'nearest','shadow_method':'neutral-black alpha overlay; (a - .008)/.992, conservative sun-projected AABB crop + 24px; approximation on flat ground','shadow_crop':rect,'sun_ray_direction':ray.tolist(),'limits':['This is a technical composite, not a gameplay screenshot. No production background or game asset changed.','No neighboring-object cast shadow, dynamic relighting or engine-scale validation is implied.']}
assert summary['background_sha256_before']==summary['background_sha256_after']
(R/'reports/comparison-report.json').write_text(json.dumps(summary,indent=2))
print(json.dumps(summary,indent=2))
