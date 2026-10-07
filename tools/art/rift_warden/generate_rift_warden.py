"""Original Rift Warden / ancient stone gatekeeper. No downloaded assets.
Blender 4.3+: blender -b -t 3 --python generate_rift_warden.py -- --sample --out DIR
Final: blender -b -t 3 --python generate_rift_warden.py -- --all --out DIR
Package: python3 generate_rift_warden.py --pack --out DIR
Camera fixed 55 degrees, front -Y, 8 directions, 144 native RGBA sprites.
"""
import os, sys, json, math, argparse
from pathlib import Path
argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
ap=argparse.ArgumentParser();ap.add_argument('--out',default=str(Path(__file__).resolve().parent));ap.add_argument('--sample',action='store_true');ap.add_argument('--all',action='store_true');ap.add_argument('--preview',action='store_true');ap.add_argument('--pack',action='store_true');ap.add_argument('--indices',default='');args=ap.parse_args(argv)
OUT=Path(args.out).resolve();OUT.mkdir(parents=True,exist_ok=True)
if args.pack:
 from PIL import Image,ImageDraw,ImageChops
 import hashlib
 manifest=json.loads((OUT/'rift_warden_manifest.json').read_text());atlas=Image.new('RGBA',(2048,1728));boxes=[]
 for row in manifest['frames']:
  im=Image.open(OUT/row['file']).convert('RGBA');assert im.size==(128,192)
  a=im.getchannel('A');b=a.getbbox();assert b and b[0]>0 and b[1]>0 and b[2]<128 and b[3]<192,(row['index'],b)
  row['alpha_bounds_px']=list(b);row['alpha_bounds_8_px']=list(a.point(lambda v:255 if v>=8 else 0).getbbox());row['visual_top_anchor_px']=[64,b[1]];boxes.append(b)
  x,y,w,h=row['atlas_rect'];atlas.alpha_composite(im,(x,y));assert ImageChops.difference(im,atlas.crop((x,y,x+w,y+h))).getbbox() is None
 atlas.save(OUT/'rift_warden_atlas.png',optimize=True)
 manifest['all_frame_alpha_bounds_px']=[min(b[0] for b in boxes),min(b[1] for b in boxes),max(b[2] for b in boxes),max(b[3] for b in boxes)]
 manifest['body_height_range_px']=[min(b[3]-b[1] for b in boxes),max(b[3]-b[1] for b in boxes)];manifest['body_width_range_px']=[min(b[2]-b[0] for b in boxes),max(b[2]-b[0] for b in boxes)]
 manifest['idle_body_height_range_px']=[min(r['alpha_bounds_px'][3]-r['alpha_bounds_px'][1] for r in manifest['frames'] if r['animation']=='idle'),max(r['alpha_bounds_px'][3]-r['alpha_bounds_px'][1] for r in manifest['frames'] if r['animation']=='idle')];manifest['source_generator_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
 manifest['atlas_sha256']=hashlib.sha256((OUT/'rift_warden_atlas.png').read_bytes()).hexdigest();manifest['qa']={'all_144_frames_present':True,'unclipped':True,'RGBA':True,'native_pixels_match_atlas':True,'fixed_world_origin_anchor':True,'baked_ground_shadow':False}
 (OUT/'rift_warden_manifest.json').write_text(json.dumps(manifest,indent=2))
 sheet=Image.new('RGBA',(1024,390),(49,54,43,255));dr=ImageDraw.Draw(sheet)
 for d,name in enumerate(manifest['direction_order']):
  im=Image.open(OUT/f'frames/rift_warden_{d*18:03d}.png');sheet.alpha_composite(im,(d*128,20));dr.text((d*128+5,6),f'{d} {name}',fill='#ebe0c3')
  small=im.resize((92,138),Image.Resampling.LANCZOS);sheet.alpha_composite(small,(d*128+16,225))
 dr.text((6,211),'Bottom: 0.72 world display scale; shared anchor = (64, 158)',fill='#ebe0c3');sheet.convert('RGB').save(OUT/'rift_warden_direction_contact.png')
 anim=Image.new('RGBA',(1024,3*210),(49,54,43,255));draw=ImageDraw.Draw(anim)
 for r,(name,n,off) in enumerate([('idle',4,0),('walk',8,4),('attack',6,12)]):
  for f in range(n):
   im=Image.open(OUT/f'frames/rift_warden_{36+off+f:03d}.png');anim.alpha_composite(im,(128*f,r*210+18));draw.text((128*f+5,r*210+4),f'{name} {f}',fill='#ebe0c3')
 anim.convert('RGB').save(OUT/'rift_warden_animation_contact.png');print('PACKED',manifest['all_frame_alpha_bounds_px'],manifest['body_height_range_px']);sys.exit(0)
import bpy,random
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
from math import sin,cos,pi
random.seed(217)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials):bpy.data.materials.remove(m)
def material(name,colors,rough=.8,metal=0,scale=5):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;bs=n.get('Principled BSDF');bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
 tex=n.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=scale;tex.inputs['Detail'].default_value=2.2
 ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=(*colors[0],1);ramp.color_ramp.elements[1].color=(*colors[-1],1)
 if len(colors)>2:ramp.color_ramp.elements.new(.50).color=(*colors[1],1)
 l.new(tex.outputs['Fac'],ramp.inputs[0]);l.new(ramp.outputs[0],bs.inputs['Base Color']);return m
stone=material('Warm grey aged shrine stone',[(.16,.155,.125),(.30,.30,.24),(.44,.43,.34)],scale=3)
maskstone=material('Worn pale limestone face',[(.29,.285,.22),(.48,.47,.36),(.62,.59,.44)],scale=4)
edge=material('Chipped exposed stone ridges',[(.33,.30,.22),(.58,.53,.37)],scale=6)
dark=material('Deep stone joints and engraved channels',[(.026,.031,.019),(.068,.073,.041)],scale=5)
bronze=material('Old burnished copper bronze',[(.105,.065,.022),(.24,.145,.047),(.39,.26,.095)],.52,.65,5)
patina=material('Subdued green verdigris copper',[(.070,.113,.062),(.15,.195,.095)],.79,.25,5)
cloth=material('Deep olive worn ceremonial mantle',[(.041,.061,.022),(.095,.125,.043),(.16,.18,.065)],.93,0,8)
trim=material('Tarnished gold thread and woven edging',[(.135,.09,.02),(.30,.23,.063)],.75,.22,6)
eye=material('Small amber spirit core',[(.65,.25,.012),(.95,.53,.052)],.34,.22,5);bs=eye.node_tree.nodes.get('Principled BSDF');bs.inputs['Emission Color'].default_value=(1,.20,.005,1);bs.inputs['Emission Strength'].default_value=.5

def empty(name,loc=(0,0,0),parent=None):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=loc;o.parent=parent;return o
root=empty('RIFT_WARDEN_root')

def mesh(name,verts,faces,mat,parent=None,bevel=.035):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);o.data.materials.append(mat);o.parent=parent
 if bevel:
  b=o.modifiers.new('Worn bevels','BEVEL');b.width=bevel;b.segments=2
  n=o.modifiers.new('Weighted broad carved planes','WEIGHTED_NORMAL');n.keep_sharp=True;n.weight=40
 return o

def chunk(name,loc,scale,mat,parent=None,seed=0,rot=(0,0,0),bevel=.028,n=8):
 rng=random.Random(seed);vs=[];rings=[(-1,.61),(-.74,.94),(.55,1),(1,.65)];jig=[rng.uniform(.94,1.055) for _ in range(n)]
 for z,r in rings:
  for i in range(n):
   a=2*pi*(i+.5)/n;vs.append((scale[0]*r*jig[i]*cos(a),scale[1]*r*jig[i]*sin(a),scale[2]*z))
 fs=[tuple(range(n-1,-1,-1))]
 for j in range(3):
  for i in range(n):a=j*n+i;b=j*n+(i+1)%n;fs.append((a,b,b+n,a+n))
 fs.append(tuple(range(3*n,4*n)));o=mesh(name,vs,fs,mat,parent,bevel);o.location=loc;o.rotation_euler=rot;return o

def slab(name,outline,depth,loc,mat,parent=None,rot=(0,0,0),bevel=.02):
 # outline in X,Z; thickness in Y. Front surface is negative Y.
 n=len(outline);vs=[(x,y,z) for y in [-depth/2,depth/2] for x,z in outline];fs=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 o=mesh(name,vs,fs,mat,parent,bevel);o.location=loc;o.rotation_euler=rot;return o

def ring(name,loc,r,depth,mat,parent,ratio=1,rot=(0,0,0)):
 n=10;vs=[]
 for z,rr in [(-depth/2,r),(-depth/2,r*.79),(depth/2,r*.79),(depth/2,r)]:
  for i in range(n):a=2*pi*i/n;vs.append((rr*cos(a),rr*sin(a)*ratio,z))
 fs=[]
 for j in range(4):
  for i in range(n):fs.append((j*n+i,j*n+(i+1)%n,((j+1)%4)*n+(i+1)%n,((j+1)%4)*n+i))
 o=mesh(name,vs,fs,mat,parent,.012);o.location=loc;o.rotation_euler=rot;return o

def strip(name,coords,width,mat,parent):
 # small bevelled raised/inset chisel line; deliberately bold enough for final sprite
 vs=[]
 for x,y,z in coords:vs.extend([(x-width/2,y,z),(x+width/2,y,z)])
 return mesh(name,vs,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(len(coords)-1)],mat,parent,0)
body=empty('torso_motion',(0,0,1.55),root)
chunk('Long narrow central waist',(0,0,.38),(.46,.35,.65),dark,body,1,bevel=.055)
chunk('Angular carved chest',(0,-.015,1.00),(.70,.42,.67),stone,body,2,bevel=.062)
chunk('Low belt stone keystone',(0,-.055,.23),(.53,.35,.20),bronze,body,3,bevel=.038)
# Breastplate is three broad staggered chevrons, not a modern chest machine.
for i in range(3):
 z=1.31-i*.27;w=.57-i*.055
 slab('Ancient pectoral overlapping chevron '+str(i),[(-w,.10),(-.13,.12),(0,-.06),(.13,.12),(w,.10),(w*.83,-.13),(0,-.32),(-w*.83,-.13)],.095,(0,-.38,z),bronze if i==0 else stone,body,bevel=.025)
# Octagonal recessed core, small warm accent.
ring('Etched bronze heart bezel',(0,-.494,1.15),.185,.065,bronze,body,rot=(pi/2,0,0));chunk('Inset amber heart',(0,-.525,1.15),(.105,.044,.135),eye,body,24,bevel=.017)
for s in [-1,1]:
 # Shoulders are long, stepped slabs with copper caps; elbow width remains below crown/shoulder signature.
 chunk('Recessed shoulder stone '+str(s),(s*.70,.005,1.29),(.31,.33,.29),dark,body,9+s)
 for i in range(3):
  slab('Layered shrine shoulder '+str(s)+' '+str(i),[(-.31,.08),(-.23,.21),(.22,.23),(.39,.06),(.28,-.19),(-.28,-.15)],.54,(s*(.70+.055*i),.025,1.55-.17*i),bronze if i==0 else stone,body,rot=(0,s*.12,s*-.06),bevel=.034)
 # Large ceremonial rivets, sparse.
 chunk('Shoulder front antique stud '+str(s),(s*.79,-.29,1.54),(.082,.04,.079),patina,body,seed=4+s,bevel=.01)
 # Front cloth stoles, with bevelled irregular torn ends, hang long to shin.
 outline=[(-.15,0),(.15,.012),(.16,-1.28),(.11,-1.70),(-.02,-1.60),(-.12,-1.74),(-.18,-1.16)]
 stole=slab('Long dark olive ritual stole '+str(s),outline,.043,(s*.40,-.36,.99),cloth,body,rot=(0,s*-.065,0),bevel=.009)
 # Thin gold vertical embroidered tracks sit on fabric, avoiding broad gold sheets.
 for dx in [-.108,.102]:strip('Old gold woven stole line '+str(s)+str(dx),[(s*.40+dx,-.386,.87),(s*.40+dx*.92,-.40,.29),(s*.40+dx*1.12,-.398,-.39),(s*.40+dx*.88,-.381,-.60)],.021,trim,body)
 # Carved skirt plate provides separate stone outline between fabric.
 slab('Flared long hip tablet '+str(s),[(-.14,0),(.18,.03),(.23,-.68),(.08,-.86),(-.18,-.69)],.14,(s*.50,.0,.30),stone,body,rot=(0,s*-.17,0),bevel=.032)
# Back mantle: folded panels, long and asymmetric with central split. Not a hoop or aura.
for s in [-1,1]:
 vs=[];rows=[(1.53,.36,.48),(1.20,.46,.57),(.65,.53,.59),(.0,.59,.60),(-.77,.66,.55),(-1.08,.72,.45)]
 for i,(z,y,w) in enumerate(rows):
  for j in range(4):
   x=s*(.04+j*w/3);vs.append((x,y+(.065 if j%2 else -.015),z+(-.06 if i==5 and j%2 else 0)))
 fs=[]
 for i in range(5):
  for j in range(3):a=i*4+j;fs.append((a,a+1,a+5,a+4))
 mantle=mesh('Split moss olive rear mantle '+str(s),vs,fs,cloth,body,0);sol=mantle.modifiers.new('Heavy woven thickness','SOLIDIFY');sol.thickness=.034
 # Broad copper clasp high on rear, small below folded fabric.
 slab('Mantle back clasp '+str(s),[(-.08,.12),(.08,.12),(.10,-.11),(0,-.17),(-.10,-.11)],.075,(s*.29,.424,1.39),bronze,body,bevel=.014)
# Stone neck and elongated mask are tucked under a broken architectural crown.
chunk('Ancient neck column',(0,0,1.69),(.235,.22,.26),dark,body,91,bevel=.02)
head=empty('mask_nod',(0,-.015,2.01),body)
chunk('Elongated solemn stone head',(0,.01,.09),(.43,.32,.48),stone,head,25,bevel=.04)
slab('Great sculpted face mask',[(-.32,.38),(.32,.38),(.37,.09),(.27,-.25),(0,-.46),(-.26,-.28),(-.37,.07)],.16,(0,-.30,.08),maskstone,head,rot=(.14,0,0),bevel=.039)
# Stone geometric nose, brow ridge, recessed eyes, beard channels.
slab('Long faceted central nose',[(-.07,.25),(.065,.25),(.09,-.02),(0,-.09),(-.09,-.02)],.105,(0,-.411,.10),edge,head,rot=(.14,0,0),bevel=.018)
for s in [-1,1]:
 chunk('Hollow temple eye '+str(s),(s*.186,-.408,.175),(.118,.025,.056),dark,head,66,rot=(.14,0,s*-.12),bevel=.007)
 chunk('Faint amber eye slit '+str(s),(s*.183,-.43,.183),(.069,.014,.013),eye,head,66,bevel=.004)
 slab('Heavy angular carved brow '+str(s),[(-.15,.035),(.16,.045),(.11,-.035),(-.12,-.04)],.08,(s*.18,-.395,.265),stone,head,rot=(.12,s*.1,s*-.11),bevel=.013)
 slab('Stepped cheek relief '+str(s),[(-.085,.11),(.09,.065),(.055,-.15),(-.015,-.22)],.047,(s*.254,-.397,-.023),edge,head,rot=(.16,s*.20,0),bevel=.011)
strip('Downturned chisel mouth',[(-.11,-.411,-.112),(0,-.437,-.142),(.11,-.411,-.112)],.026,dark,head)
for x in [-.12,0,.12]:strip('Vertical ancient beard groove '+str(x),[(x,-.397,-.18),(x*.57,-.362,-.28),(x*.28,-.327,-.34)],.017,dark,head)
# Discontinuous broken crown, 5 separate stone/copper prongs and lower temple rail.
ring('Broken copper crown circlet',(0,.006,.39),.433,.115,bronze,head,ratio=.80)
for i,(x,y,h,lean) in enumerate([(-.38,.01,.64,-.18),(-.24,.23,.76,-.12),(0,.29,.56,.02),(.24,.23,.69,.13),(.38,.00,.47,.22)]):
 slab('Broken architectural crown prong '+str(i),[(-.075,0),(.079,0),(.063,h*.65),(.01,h),(-.055,h*.89)],.135,(x,y,.35),stone if i%2 else bronze,head,rot=(0,lean,0),bevel=.022)
 slab('Crown inset relief '+str(i),[(-.016,.06),(.016,.06),(.02,h*.67),(-.018,h*.73)],.015,(x,y-.078,.35),patina,head,rot=(0,lean,0),bevel=.004)
# Thick jointed legs and broad carved bare-stone feet.
legs={};feet={};arms={};elbows={}
for s in [-1,1]:
 leg=empty('leg_swing_'+str(s),(s*.35,.02,1.55),root);legs[s]=leg
 chunk('Segmented stone thigh '+str(s),(0,0,-.34),(.28,.29,.40),stone,leg,80+s,rot=(0,s*-.04,0),bevel=.04)
 chunk('Dark articulated knee '+str(s),(0,-.005,-.71),(.205,.22,.20),dark,leg,100+s)
 chunk('Carved kneecap '+str(s),(0,-.18,-.68),(.25,.13,.23),bronze,leg,20+s,bevel=.025)
 chunk('Long stone greave '+str(s),(0,.025,-1.02),(.25,.25,.35),stone,leg,27+s,bevel=.04)
 slab('Shin carved central panel '+str(s),[(-.14,.20),(.14,.20),(.11,-.22),(0,-.29),(-.11,-.22)],.056,(0,-.224,-1.01),maskstone,leg,bevel=.025)
 ring('Old copper ankle rim '+str(s),(0,.01,-1.30),.249,.095,bronze,leg,ratio=1.05)
 foot=empty('foot_'+str(s),(0,-.13,-1.43),leg);feet[s]=foot
 chunk('Great grounded stone foot '+str(s),(0,-.08,.02),(.32,.44,.14),stone,foot,65+s,bevel=.038)
 for t in range(3):chunk('Weathered carved toe '+str(s)+' '+str(t),((t-1)*.18,-.40,-.005),(.092,.14,.095),maskstone,foot,10+t+s,bevel=.021)
 # Arms hang low, hand silhouette made from five stone digits.
 arm=empty('arm_swing_'+str(s),(s*.83,.015,1.37),body);arms[s]=arm
 chunk('Massive stone upper arm '+str(s),(s*.055,.01,-.36),(.285,.28,.40),stone,arm,87+s,rot=(0,s*-.09,0),bevel=.045)
 elbow=empty('elbow_'+str(s),(s*.09,.005,-.72),arm);elbows[s]=elbow
 chunk('Ancient elbow joint '+str(s),(0,.025,.025),(.20,.22,.20),dark,elbow,45+s,bevel=.027)
 chunk('Great tapering stone forearm '+str(s),(s*.015,-.035,-.275),(.325,.29,.36),stone,elbow,55+s,bevel=.045)
 slab('Forearm long copper relief '+str(s),[(-.15,.23),(.15,.23),(.17,-.11),(0,-.31),(-.17,-.11)],.085,(s*.015,-.28,-.255),bronze,elbow,bevel=.027)
 slab('Forearm green patina inlay '+str(s),[(-.035,.17),(.035,.17),(.04,-.12),(0,-.19),(-.04,-.12)],.02,(s*.015,-.33,-.255),patina,elbow,bevel=.006)
 ring('Stone wrist copper binding '+str(s),(0,-.02,-.55),.258,.105,bronze,elbow)
 chunk('Giant weathered palm '+str(s),(0,-.045,-.72),(.285,.23,.25),stone,elbow,81+s,bevel=.035)
 for t in range(4):chunk('Separate stone finger '+str(s)+' '+str(t),((t-1.5)*.13,-.125,-.915),(.072,.122,.16),maskstone,elbow,37+t,rot=(.12,0,0),bevel=.022)
 chunk('Broad inward curled thumb '+str(s),(-s*.26,-.155,-.68),(.11,.16,.16),stone,elbow,99+s,rot=(.18,-s*.34,0),bevel=.024)
# Render contract uses a stationary camera and lights; only subject rotates.
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=40;scene.cycles.use_denoising=False;scene.cycles.max_bounces=4;scene.cycles.diffuse_bounces=2;scene.cycles.glossy_bounces=2;scene.render.threads_mode='FIXED';scene.render.threads=3
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.image_settings.color_depth='8';scene.render.film_transparent=True;scene.render.fps=12
scene.world.use_nodes=True;bg=scene.world.node_tree.nodes.get('Background');bg.inputs['Color'].default_value=(.50,.57,.66,1);bg.inputs['Strength'].default_value=.58
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.1

def area(name,loc,power,size,col):
 d=bpy.data.lights.new(name,'AREA');o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.location=loc;d.energy=power;d.shape='DISK';d.size=size;d.color=col;o.rotation_euler=(Vector((0,0,1.9))-o.location).to_track_quat('-Z','Y').to_euler()
area('Fixed upper left warm key',(-3,-4,8),600,4,(1,.90,.73));area('Soft front sky fill',(3,-4,4),165,5,(.68,.79,1));area('Gentle rear stone bounce',(3,4,6),100,5,(.72,.81,1))
cd=bpy.data.cameras.new('Fixed ortho55');cam=bpy.data.objects.new('Fixed ortho55',cd);bpy.context.collection.objects.link(cam);scene.camera=cam
camdir=Vector((0,-cos(math.radians(55)),sin(math.radians(55))));cam.rotation_euler=(-camdir).to_track_quat('-Z','Y').to_euler();up=cam.rotation_euler.to_quaternion()@Vector((0,1,0));cd.type='ORTHO';cd.sensor_fit='VERTICAL';cd.ortho_scale=5.2;cam.location=up*(cd.ortho_scale*(158/192-.5))+camdir*12
tracked=[body,head,*legs.values(),*arms.values(),*elbows.values(),*feet.values()];base={o.name:(o.location.copy(),o.rotation_euler.copy()) for o in tracked}

def pose(direction,anim,f):
 root.rotation_euler=(0,0,math.radians(90-45*direction))
 for o in tracked:o.location=base[o.name][0];o.rotation_euler=base[o.name][1]
 if anim=='idle':
  breathe=sin(2*pi*f/4);body.location.z+=.016*breathe;head.rotation_euler.x=.025*breathe
  for s in [-1,1]:arms[s].rotation_euler.x=.014*breathe;elbows[s].rotation_euler.x=-.018*breathe
 elif anim=='walk':
  phase=2*pi*f/8;stride=sin(phase);bob=.028*(1-cos(2*phase));body.location.z+=bob;body.rotation_euler.z=.027*stride
  for s in [-1,1]:
   leg=legs[s];ang=s*stride*.19;leg.rotation_euler.x=ang
   # Offset foot contact analytically; the fixed origin never changes.
   zlow=min((math.sin(ang)*y+math.cos(ang)*z+1.55) for y in [-.67,.25] for z in [-1.55,-1.35]);leg.location.z+=max(0,-zlow)+.045*max(0,cos(phase+(0 if s==1 else pi)))
   arms[s].rotation_euler.x=-s*stride*.16;elbows[s].rotation_euler.x=-.045*max(0,-s*stride)
  head.rotation_euler.x=.025
 elif anim=='attack':
  # Existing attack duration only: slow two-arm windup, emphatic forward slam, recovery.
  arm=[-.08,-.4,-1.5,-.35,-.12,0][f];bend=[.0,-.025,-.05,.27,.15,0][f];drop=[0,0,.03,-.22,-.09,0][f]
  body.rotation_euler.x=bend;body.location.z+=drop;head.rotation_euler.x=-bend*.4
  for s in [-1,1]:
   arms[s].rotation_euler.x=arm;arms[s].rotation_euler.y=s*[0,0,.08,.035,0,0][f];elbows[s].rotation_euler.x=[-.08,-2.15,-1.32,-.08,0,0][f]
 bpy.context.view_layer.update()

def anchors():
 p=world_to_camera_view(scene,cam,Vector((0,0,0)));top=world_to_camera_view(scene,cam,head.matrix_world@Vector((0,.23,1.11)))
 return {'foot_anchor_px':[round(p.x*128,4),round((1-p.y)*192,4)],'head_anchor_px':[round(top.x*128,3),round((1-top.y)*192,3)]}
scene['asset_id']='rift_warden';scene['model_forward']='-Y';scene['foot_origin']=[0.,0.,0.];scene['fixed_key_position']=[-3.,-4.,8.];scene['original_procedural_model']=True
if args.sample:
 scene.render.resolution_x=256;scene.render.resolution_y=256;scene.cycles.samples=64;cd.ortho_scale=4.35;cam.location=up*1.56+camdir*12;pose(1,'idle',0);scene.render.filepath=str(OUT/'rift_warden_sample_256.png');bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'rift_warden.blend'));bpy.ops.render.render(write_still=True);print('SAMPLE_READY',OUT);sys.exit(0)
scene.render.resolution_x=128;scene.render.resolution_y=192;scene.render.resolution_percentage=100
names=['E','SE','S','SW','W','NW','N','NE'];rows=[]
for d in range(8):
 for anim,n,off in [('idle',4,0),('walk',8,4),('attack',6,12)]:
  for f in range(n):
   idx=d*18+off+f;rows.append({'index':idx,'direction':d,'direction_name':names[d],'animation':anim,'animation_frame':f,'atlas_rect':[(idx%16)*128,(idx//16)*192,128,192],'file':f'frames/rift_warden_{idx:03d}.png'})
selected=rows
if args.preview:selected=[rows[d*18+f] for d in range(8) for f in [0,10,14,15]]
if args.indices:selected=[rows[i] for i in map(int,args.indices.split(','))]
(OUT/'frames').mkdir(exist_ok=True)
for row in rows:
 pose(row['direction'],row['animation'],row['animation_frame']);row.update(anchors())
 if row not in selected:continue
 scene.render.filepath=str(OUT/row['file']);scene.frame_set(row['index']+1);bpy.ops.render.render(write_still=True);print('WARDEN_FRAME',row['index'],row['foot_anchor_px'],flush=True)
manifest={'asset_id':'rift_warden','display_name':'Rift Warden / 断冠遗迹守门者','source_files':['generate_rift_warden.py','rift_warden.blend'],'frame_size_px':[128,192],'atlas_size_px':[2048,1728],'atlas_columns':16,'atlas_rows':9,'fps':12,'direction_order':names,'direction_yaw_degrees':[90-45*d for d in range(8)],'animation_offsets':{'idle':0,'walk':4,'attack':12},'animation_counts':{'idle':4,'walk':8,'attack':6},'frame_index_formula':'direction * 18 + animation_offset + animation_frame','foot_anchor_px':[64,158],'foot_anchor_world':[0,0,0],'recommended_world_scale':.72,'camera':{'elevation_degrees':55,'projection':'orthographic','ortho_scale':5.2,'sensor_fit':'VERTICAL','fixed_camera':True},'render':{'engine':'Cycles CPU','samples':40,'threads':3,'denoising':False,'key_position':[-3,-4,8],'transparent':True,'ground_plane':False,'baked_floor_shadow':False},'art':{'silhouette':'Tall ancient stone mask, broken architectural crown, stepped copper-stone shoulders, long split olive mantle and stoles, massive stone hands and feet','palette':'warm grey limestone, old copper, deep olive fabric, small amber core','new_attack_logic':False,'external_assets':False},'frames':rows}
(OUT/'rift_warden_manifest.json').write_text(json.dumps(manifest,indent=2));pose(2,'idle',0);scene.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'rift_warden.blend'));print('WARDEN_DONE',OUT,flush=True)
