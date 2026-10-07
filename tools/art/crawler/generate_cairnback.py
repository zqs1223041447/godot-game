"""Cairnback, an original articulated ruin-rock quadruped.
Blender 4.3+ CPU: blender -b -t 4 --python generate_cairnback.py -- --all
Then package: python3 generate_cairnback.py --pack
Optional --sample (256px three-quarter) or --test (four contract frames).
No purchased/downloaded assets. 144 rigid-joint animation frames, RGBA, no floor.
"""
import sys, os
if '--pack' in sys.argv:
 from PIL import Image, ImageDraw
 import json, hashlib
 out=os.path.dirname(os.path.abspath(__file__))
 with open(os.path.join(out,'atlas_metadata.json')) as f: data=json.load(f)
 assert not data['test_only'] and len(data['frames'])==144, 'A complete 144-frame render is required'
 atlas=Image.new('RGBA',(2048,1728),(0,0,0,0));bounds=[]
 for rec in data['frames']:
  idx=rec['index'];im=Image.open(os.path.join(out,'frames',f'{idx:03d}.png')).convert('RGBA')
  assert im.size==(128,192)
  alpha=im.getchannel('A');bbox=alpha.getbbox();assert bbox is not None
  assert bbox[0]>0 and bbox[1]>0 and bbox[2]<128 and bbox[3]<192, (idx,'clipped alpha',bbox)
  rec['alpha_bounds_px']=list(bbox);rec['body_size_px']=[bbox[2]-bbox[0],bbox[3]-bbox[1]]
  rec['visual_top_anchor_px']=[64,bbox[1]]
  rec['alpha_bounds_8_px']=list(alpha.point(lambda a:255 if a>=8 else 0).getbbox())
  bounds.append(bbox);atlas.alpha_composite(im,((idx%16)*128,(idx//16)*192))
 atlas.save(os.path.join(out,'crawler_atlas.png'),optimize=True)
 data['atlas_size_px']=[2048,1728];data['atlas_sha256']=hashlib.sha256(open(os.path.join(out,'crawler_atlas.png'),'rb').read()).hexdigest()
 data['all_frame_alpha_bounds_px']=[min(b[0] for b in bounds),min(b[1] for b in bounds),max(b[2] for b in bounds),max(b[3] for b in bounds)]
 data['alpha_body_height_range_px']=[min(b[3]-b[1] for b in bounds),max(b[3]-b[1] for b in bounds)]
 data['alpha_body_width_range_px']=[min(b[2]-b[0] for b in bounds),max(b[2]-b[0] for b in bounds)]
 data['recommended_display_scale']=0.64
 data['qa']={'all_frames_present':True,'all_frames_rgba':True,'all_frames_unclipped':True,'shared_anchor':True,'baked_floor_or_shadow':False}
 with open(os.path.join(out,'atlas_metadata.json'),'w') as f:json.dump(data,f,ensure_ascii=False,indent=2)
 sheet=Image.new('RGBA',(1024,220),(29,34,30,255));draw=ImageDraw.Draw(sheet)
 for d,label in enumerate(data['direction_order']):
  im=Image.open(os.path.join(out,'frames',f'{d*18:03d}.png')).convert('RGBA');sheet.alpha_composite(im,(d*128,16));draw.text((d*128+10,8),f'{d} {label}',fill=(232,223,193,255))
 sheet.convert('RGB').save(os.path.join(out,'direction_contact_sheet.png'))
 print('PACKED', data['atlas_size_px'],'ALPHA',data['all_frame_alpha_bounds_px'],'HEIGHT',data['alpha_body_height_range_px'])
 sys.exit(0)
import bpy, math, random, os, json
from mathutils import Vector
from math import sin,cos,pi
OUT=os.path.dirname(os.path.abspath(__file__))
random.seed(18)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for d in bpy.data.materials: bpy.data.materials.remove(d)

def mat_stone(name,colors,scale=3.7,rough=.84):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;n.clear()
 out=n.new('ShaderNodeOutputMaterial');bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['Roughness'].default_value=rough
 tex=n.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=scale;tex.inputs['Detail'].default_value=2;tex.inputs['Roughness'].default_value=.65
 ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
 for i,col in enumerate(colors):
  e=ramp.color_ramp.elements[0] if i==0 else ramp.color_ramp.elements.new(i/(len(colors)-1));e.position=i/(len(colors)-1);e.color=(*col,1)
 l.new(tex.outputs['Fac'],ramp.inputs[0]);l.new(ramp.outputs[0],bs.inputs['Base Color']);l.new(bs.outputs[0],out.inputs[0]);return m
stone=mat_stone('Weathered blue slate | broad hand-painted value',[(.086,.123,.119),(.201,.246,.226),(.328,.365,.295)],2.3)
plate=mat_stone('Carved limestone armour | warm broken planes',[(.20,.235,.19),(.385,.425,.335),(.57,.57,.425)],3.4)
edge=mat_stone('Fresh warm chipped edges',[(.35,.35,.27),(.54,.525,.385)],5)
moss=mat_stone('Dry moss patina',[(.095,.12,.038),(.23,.28,.085),(.34,.36,.11)],8)
joint=mat_stone('Dark recessed stone joints',[(.0384,.0504,.044),(.0736,.096,.076)],4)
bronze=mat_stone('Tarnished old bronze bindings',[(.115,.10,.044),(.26,.205,.083),(.39,.30,.11)],4,.5)
bs=bronze.node_tree.nodes.get('Principled BSDF');bs.inputs['Metallic'].default_value=.58
black=mat_stone('Deep eye sockets',[(.025,.03,.02),(.05,.055,.026)],3)
eye=bpy.data.materials.new('Small amber spirit eyes');eye.diffuse_color=(.65,.245,.025,1);eye.use_nodes=True;p=eye.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(.85,.32,.02,1);p.inputs['Roughness'].default_value=.35;p.inputs['Emission Color'].default_value=(1,.19,.005,1);p.inputs['Emission Strength'].default_value=.75

def empty(name,loc=(0,0,0),parent=None):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=loc;o.parent=parent;return o
root=empty('CAIRNBACK_root',(0,0,-.18))

def mesh(name,verts,faces,mat,parent=None,bevel=.04):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);o.data.materials.append(mat);o.parent=parent
 if bevel:
  m=o.modifiers.new('Sculpted chipped edge','BEVEL');m.width=bevel;m.segments=2
  m=o.modifiers.new('Weighted broad face normals','WEIGHTED_NORMAL');m.keep_sharp=True;m.weight=30
 return o

def chunk(name,loc,scale,mat,parent=None,seed=0,bevel=.035,rot=(0,0,0),n=8):
 rng=random.Random(seed);verts=[]
 # Hand-shaped block/rock: angular broad middle, gently tapered chamfered cap.
 rings=[(-1,.47),(-.75,.89),(-.1,1.0),(.57,.89),(1,.48)]
 jig=[rng.uniform(.90,1.10) for i in range(n)]
 for ri,(z,r) in enumerate(rings):
  for i in range(n):
   a=2*pi*i/n+pi/n;rr=r*jig[i];verts.append((scale[0]*rr*cos(a),scale[1]*rr*sin(a),scale[2]*(z+(.055*sin(i*2.8+seed) if ri not in (0,4) else 0))))
 faces=[tuple(range(n-1,-1,-1))]
 for j in range(len(rings)-1):
  for i in range(n): a=j*n+i;b=j*n+(i+1)%n;faces.append((a,b,b+n,a+n))
 faces.append(tuple(range((len(rings)-1)*n,len(rings)*n)))
 o=mesh(name,verts,faces,mat,parent,bevel);o.location=loc;o.rotation_euler=rot;return o

def slab(name,outline,depth,loc,mat,parent=None,rot=(0,0,0),bevel=.035):
 n=len(outline);v=[(x,y,z) for z in (-depth/2,depth/2) for x,y in outline];f=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
 f +=[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 o=mesh(name,v,f,mat,parent,bevel);o.location=loc;o.rotation_euler=rot;return o

def cuff(name,loc,radius,depth,mat,parent,rot=(0,0,0),ratio=.8):
 n=10;verts=[]
 for z,r in [(-depth/2,radius),(-depth/2,radius*.81),(depth/2,radius*.81),(depth/2,radius)]:
  for i in range(n):a=2*pi*i/n;verts.append((r*cos(a),r*sin(a)*ratio,z))
 faces=[]
 for j in range(4):
  for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,((j+1)%4)*n+(i+1)%n,((j+1)%4)*n+i))
 o=mesh(name,verts,faces,mat,parent,.012);o.location=loc;o.rotation_euler=rot;return o
body=empty('body_sway',(0,.17,1.05),root)
chunk('Deep barrel torso',(0,0,.19),(.68,.72,.53),stone,body,11,.06,rot=(.06,0,0),n=10)
chunk('Low belly keel',(0,-.22,-.04),(.46,.62,.29),joint,body,18,.025)
# Massive overlapping scapula, separate silhouette from the small low head.
for s in [-1,1]:
 chunk('Broad hewn shoulder '+str(s),(s*.56,-.38,.41),(.39,.47,.39),plate,body,42+s,.052,rot=(.16,s*.20,s*-.14))
 slab('Shoulder crown flake '+str(s),[(-.22,-.29),(.14,-.34),(.30,-.08),(.23,.30),(-.13,.36),(-.31,.04)],.105,(s*.59,-.40,.72),edge,body,rot=(.13,s*.25,0),bevel=.03)
 slab('Shoulder moss '+str(s),[(-.16,-.12),(.02,-.19),(.14,-.05),(.10,.11),(-.12,.08)],.017,(s*.65,-.38,.79),moss,body,rot=(.11,s*.25,0),bevel=.005)
# Armour spine follows crouched back rather than tall humanoid silhouette.
for i,(y,z,w,d) in enumerate([(-.17,.66,.40,.27),(.18,.64,.48,.31),(.49,.49,.44,.30),(.69,.29,.30,.25)]):
 slab('Overlapping dorsal carapace %d'%i,[(-w,-d),(.35*w,-1.05*d),(w,-.42*d),(.91*w,.76*d),(.0,1.15*d),(-.88*w,.70*d)],.16,(0,y,z),plate if i%2 else stone,body,rot=(-.15-i*.07,0,.025*(-1)**i),bevel=.043)
 if i in [1,3]:slab('Moss on dorsal plate %d'%i,[(-.15,-.07),(.02,-.10),(.18,.07),(.05,.17),(-.11,.11)],.018,(-.09,y,z+.095),moss,body,rot=(-.15-i*.07,0,0),bevel=.004)
# Truncated copper brace across the rear back, sparse readable accent.
cuff('Ancient broken back binding',(0,.40,.35),.535,.12,bronze,body,rot=(pi/2,0,0),ratio=.73)
# Head, lowered and projecting forward.
head=empty('head_nod',(0,-.74,.28),body)
chunk('Faceted broad skull',(0,-.15,0),(.40,.42,.31),stone,head,78,.04,rot=(.05,0,0))
chunk('Heavy underslung muzzle',(0,-.42,-.13),(.30,.29,.17),plate,head,82,.036)
chunk('Broad lower jaw',(0,-.38,-.29),(.28,.26,.09),joint,head,94,.027)
# Eye sockets are angled toward front; tiny emissive slivers under massive angular brows.
for s in [-1,1]:
 chunk('Inset eye well '+str(s),(s*.232,-.449,.055),(.126,.053,.072),black,head,15,.01,rot=(0,s*.1,s*-.22))
 chunk('Amber eye '+str(s),(s*.232,-.49,.064),(.074,.018,.030),eye,head,15,.008,rot=(0,0,s*-.22))
 chunk('Chiselled brow '+str(s),(s*.221,-.411,.145),(.218,.123,.105),plate,head,39+s,.035,rot=(0,s*-.12,s*-.19))
 # Stone tusk corners carry silhouette without giant fantasy spikes.
 chunk('Muzzle stone fang '+str(s),(s*.285,-.51,-.185),(.073,.106,.12),edge,head,12+s,.022,rot=(-.17,s*-.24,0))
slab('Skull crown engraved keystone',[(-.20,-.21),(.18,-.22),(.26,.03),(.09,.21),(-.21,.15)],.078,(0,-.13,.267),edge,head,rot=(.06,0,0),bevel=.024)
slab('Broken crown moss',[(-.08,-.08),(.08,-.035),(.10,.05),(-.02,.10)],.011,(-.08,-.10,.314),moss,head,bevel=.003)
# Carved forehead cleavage: a dark seam between broad planes.
slab('Forehead chisel cut',[(-.015,-.17),(.012,-.17),(.024,.09),(-.007,.14)],.008,(.075,-.20,.313),joint,head,bevel=.001)
limbs={}
for side in [-1,1]:
 for front in [True,False]:
  label=('front' if front else 'rear')+('_L' if side<0 else '_R')
  hip=(side*(.58 if front else .48),-.39 if front else .65,.19 if front else -.12)
  limb=empty(label+'_swing',hip,body);limbs[label]=limb
  if front:
   chunk(label+' shoulder joint',(0,0,-.13),(.25,.26,.25),joint,limb,11+side,.03)
   chunk(label+' powerful upper arm',(side*.08,-.04,-.31),(.29,.31,.38),stone,limb,21+side,.04,rot=(-.13,side*-.15,0))
   fore=empty(label+'_elbow',(side*.14,-.13,-.50),limb)
   chunk(label+' forearm armour',(side*.04,-.13,-.10),(.28,.37,.30),plate,fore,55+side,.04,rot=(.19,0,side*.10))
   cuff(label+' bronze wrist',(side*.04,-.19,-.28),.256,.083,bronze,fore,rot=(.17,0,0),ratio=1.20)
   paw=empty(label+'_paw',(side*.05,-.28,-.415),fore)
   chunk(label+' broad paw',(0,-.075,.025),(.32,.38,.17),stone,paw,69+side,.041)
   for t in range(3):
    chunk(label+' squat toe '+str(t),((t-1)*.175,-.35,-.005),(.10,.17,.10),plate,paw,90+t+side,.021,rot=(0,0,(t-1)*-.06))
    chunk(label+' worn claw '+str(t),((t-1)*.175,-.47,-.025),(.052,.09,.052),edge,paw,25+t,.009)
  else:
   chunk(label+' rear haunch',(side*.02,.035,-.11),(.33,.36,.35),stone,limb,111+side,.045,rot=(-.20,side*.13,0))
   chunk(label+' knee plate',(side*.13,-.085,-.30),(.24,.27,.27),plate,limb,116+side,.036)
   chunk(label+' heel',(side*.10,.08,-.47),(.18,.23,.18),joint,limb,129+side,.021)
   paw=empty(label+'_paw',(side*.13,-.03,-.62),limb)
   chunk(label+' broad hind foot',(0,-.12,.04),(.27,.35,.17),stone,paw,125+side,.03)
   for t in range(3):chunk(label+' hind claw '+str(t),((t-1)*.145,-.39,.015),(.075,.13,.075),edge,paw,26+t,.015)
# The weighted tail is small but identifies the animal nature in rear view.
tail=empty('tail_sway',(0,.80,-.07),body)
chunk('Stone tail root',(0,.20,-.10),(.22,.37,.20),stone,tail,185,.035,rot=(.3,0,0))
chunk('Tail end wedge',(0,.48,-.18),(.18,.23,.135),plate,tail,188,.029)
# Turn stance just slightly toward the camera; direction basis remains local -Y.
# Ground is intentionally absent: genuine RGBA transparency and stable contact baseline.
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=64;scene.cycles.use_denoising=False
scene.render.resolution_x=256;scene.render.resolution_y=256;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.film_transparent=True
scene.world.color=(.27,.29,.31);scene.world.use_nodes=True;scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.50,.57,.66,1);scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.65

def area(name,loc,power,size,color):
 d=bpy.data.lights.new(name,'AREA');o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.location=loc;d.energy=power;d.shape='DISK';d.size=size;d.color=color;o.rotation_euler=(Vector((0,0,.7))-o.location).to_track_quat('-Z','Y').to_euler()
area('Warm white upper left key',(-3,-4,7),550,4.0,(1,.90,.73));area('Cool soft stone bounce',(4,2,5),220,5,(.64,.76,1))
d=bpy.data.cameras.new('Ortho55');cam=bpy.data.objects.new('Ortho55',d);bpy.context.collection.objects.link(cam);scene.camera=cam
az=math.radians(30);elev=math.radians(55);distance=10;target=Vector((0,0,.64));cam.location=target+Vector((sin(az)*cos(elev),-cos(az)*cos(elev),sin(elev)))*distance;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=3.52;d.shift_y=.0
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.1
scene.render.filepath=os.path.join(OUT,'cairnback_sample.png');scene.render.image_settings.color_depth='8';scene.render.fps=12
scene['asset_name']='Cairnback / 遗迹岩甲兽';scene['model_forward']='-Y';scene['camera_elevation_degrees']=55;scene['sprite_contract_pending']=True
# Contact position is exposed for later exact frame-anchor contract.
scene['root_ground_z']=0.;scene['render_resolution']=256

import sys
if '--sample' in sys.argv:
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'cairnback.blend'))
 bpy.ops.render.render(write_still=True)
 sys.exit(0)

import bpy, os, sys, math, json, time
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
OUT=os.path.dirname(os.path.abspath(__file__));FRAMES=os.path.join(OUT,'frames');os.makedirs(FRAMES,exist_ok=True)

scene=bpy.context.scene;root=bpy.data.objects['CAIRNBACK_root'];body=bpy.data.objects['body_sway'];head=bpy.data.objects['head_nod'];tail=bpy.data.objects['tail_sway']
# Center the stance at the fixed contact pivot, preserving geometry and all proportions.
body.location.y = .35
limbs={k:bpy.data.objects[k+'_swing'] for k in ['front_L','front_R','rear_L','rear_R']}
elbows={k:bpy.data.objects[k+'_elbow'] for k in ['front_L','front_R']}
paws={k:bpy.data.objects[k+'_paw'] for k in limbs}
base={o.name:(o.location.copy(),o.rotation_euler.copy()) for o in [body,head,tail,*limbs.values(),*elbows.values(),*paws.values()]}
scene.render.resolution_x=128;scene.render.resolution_y=192;scene.render.resolution_percentage=100
scene.cycles.samples=48;scene.cycles.use_denoising=False;scene.render.threads_mode='FIXED';scene.render.threads=4
scene.cycles.max_bounces=4;scene.cycles.diffuse_bounces=2;scene.cycles.glossy_bounces=2
cam=scene.camera;el=math.radians(55);cam.location=(0,-10*math.cos(el),10*math.sin(el));cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=4.8
# Lighting remains in world space for all directions.
key=bpy.data.objects['Warm white upper left key'];key.location=(-3,-4,8);key.rotation_euler=(Vector((0,0,.7))-key.location).to_track_quat('-Z','Y').to_euler()

def pose(direction,anim,frame):
 for name,(loc,rot) in base.items():o=bpy.data.objects[name];o.location=loc;o.rotation_euler=rot
 root.rotation_euler.z=math.radians(90-45*direction)
 if anim=='idle':
  p=2*math.pi*frame/4;body.location.z += .008*math.sin(p);head.rotation_euler.x=.016*math.sin(p+.7);tail.rotation_euler.z=.018*math.sin(p)
 elif anim=='walk':
  p=2*math.pi*frame/8;body.location.z += .015*math.cos(p*2);body.rotation_euler.y=.025*math.sin(p);head.rotation_euler.x=.022*math.cos(p*2)
  for k,l in limbs.items():
   side=-1 if k.endswith('L') else 1;phase=p+(0 if (k.startswith('front') and side==-1) or(k.startswith('rear') and side==1) else math.pi)
   a=.17*math.sin(phase);lift=.06*max(0,math.cos(phase));l.rotation_euler.x=a;l.location.z+=lift
   if k in elbows:elbows[k].rotation_euler.x=-.08*math.sin(phase)
   paws[k].rotation_euler.x=-a+(.08*math.sin(phase) if k in elbows else 0)
  tail.rotation_euler.z=.055*math.sin(p)
 else:
  # Anticipation, forward two-paw lunge/bite, grounded impact, and recovery.
  yy=[0,.09,-.15,-.18,-.07,0][frame];zz=[0,.025,.015,-.025,-.015,0][frame];nod=[0,-.04,.13,.20,.10,0][frame]
  body.location.y+=yy;body.location.z+=zz;body.rotation_euler.x=[0,-.035,.055,.065,.03,0][frame];head.rotation_euler.x=nod
  for k,l in limbs.items():
   if k.startswith('front'):
    a=[0,.10,-.19,-.12,-.05,0][frame];l.rotation_euler.x=a;elbows[k].rotation_euler.x=-a*.40;paws[k].rotation_euler.x=-a*.60;l.location.z += [0,.035,.04,.025,.015,0][frame]
   else:l.rotation_euler.x=[0,-.04,.07,.08,.03,0][frame]
  tail.rotation_euler.x=-nod*.2
 bpy.context.view_layer.update()
 for k,l in limbs.items():
  toe_meshes=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(k) and ('toe' in o.name or 'claw' in o.name or 'paw' in o.name or 'hind foot' in o.name)]
  low=min((o.matrix_world@v.co).z for o in toe_meshes for v in o.data.vertices)
  if low < 0: l.location.z -= low
 bpy.context.view_layer.update()

def anchor_shift():
 cam.data.shift_x=0;cam.data.shift_y=0;bpy.context.view_layer.update()
 q=world_to_camera_view(scene,cam,Vector((0,0,0)));cam.data.shift_y=.1;bpy.context.view_layer.update();q2=world_to_camera_view(scene,cam,Vector((0,0,0)))
 cam.data.shift_y=(142/192-(1-q.y))/.1*.1 / ((q.y-q2.y)/.1)
 # equivalent stable projection solve: desired camera normalized y=1-142/192.
 cam.data.shift_y=(q.y-(1-142/192)) / ((q.y-q2.y)/.1)
 bpy.context.view_layer.update()

def projection_bounds():
 xs=[];ys=[];ppu=192/cam.data.ortho_scale
 for o in bpy.data.objects:
  if o.type=='MESH' and not o.hide_render:
   for v in o.data.vertices:
    w=o.matrix_world@v.co;xs.append(64+w.x*ppu);ys.append(142-(w.y*math.sin(el)+w.z*math.cos(el))*ppu)
 return [min(xs),min(ys),max(xs),max(ys)]

contract=[]
for d in range(8):
 for anim,offset,count in [('idle',0,4),('walk',4,8),('attack',12,6)]:
  for f in range(count):contract.append((d*18+offset+f,d,anim,f))
# Frame-fit is global: exact mesh vertices, fixed origin, one scale across all 144 frames.
anchor_shift();allb=[]
for idx,d,anim,f in contract:pose(d,anim,f);allb.append(projection_bounds())
bb=[min(b[0] for b in allb),min(b[1] for b in allb),max(b[2] for b in allb),max(b[3] for b in allb)]
fit=max(1,(64-bb[0])/61,(bb[2]-64)/61,(142-bb[1])/139,(bb[3]-142)/47)
cam.data.ortho_scale*=fit*1.006
bb=[64+(bb[0]-64)/(fit*1.006),142+(bb[1]-142)/(fit*1.006),64+(bb[2]-64)/(fit*1.006),142+(bb[3]-142)/(fit*1.006)]
anchor_shift();pose(2,'idle',0)
print('CONTRACT_SCALE',cam.data.ortho_scale,'ALL_PROJECTED_BOUNDS',bb,flush=True)
metadata={'asset':'cairnback','version':1,'atlas_file':'crawler_atlas.png','frame_width':128,'frame_height':192,'columns':16,'rows':9,'frame_count':144,'fps':12,'direction_order':['E','SE','S','SW','W','NW','N','NE'],'animation_offsets':{'idle':0,'walk':4,'attack':12},'animation_frames':{'idle':4,'walk':8,'attack':6},'frame_index':'direction*18 + animation_offset + frame','foot_anchor_px':[64,142],'ground_origin':[0,0,0],'camera_elevation_degrees':55,'camera_ortho_scale':cam.data.ortho_scale,'camera_shift_y':cam.data.shift_y,'model_forward':'-Y','root_yaw_formula_degrees':'90 - 45 * direction','samples':48,'transparent':True,'has_baked_shadow':False,'global_projected_bounds':bb,'test_only':'--all' not in sys.argv,'frames':[]}
selected=contract if '--all' in sys.argv else [contract[i] for i in [36,48,49,50]]
start=time.time()
for idx,d,anim,f in selected:
 pose(d,anim,f);scene.render.filepath=os.path.join(FRAMES,f'{idx:03d}.png');t=time.time();bpy.ops.render.render(write_still=True)
 # Head top is a stable tracking hint for labels, distinct from the contact origin.
 top=world_to_camera_view(scene,cam,head.matrix_world@Vector((0,-.13,.32)))
 metadata['frames'].append({'index':idx,'direction':d,'animation':anim,'frame':f,'head_top_anchor_px':[round(top.x*128,2),round((1-top.y)*192,2)],'render_seconds':round(time.time()-t,3)})
 print('FRAME_DONE',idx,round(time.time()-t,3),flush=True)
metadata['total_render_seconds']=round(time.time()-start,3)
with open(os.path.join(OUT,'atlas_metadata.json'),'w') as f:json.dump(metadata,f,ensure_ascii=False,indent=2)
# Persist final rendering rig without duplicating old intermediate authoring sources.
pose(2,'idle',0);scene['sprite_contract_pending']=False;scene['foot_anchor_px']=[64,142];scene['final_frame_size']=[128,192]
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'cairnback.blend'))
print('DONE',metadata['total_render_seconds'],flush=True)
