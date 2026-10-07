"""Original Hearthward sentinel: Blender 4.3+ procedural rigid-joint model.
Sample: blender -b -t 3 --python generate_heavy_guard.py -- --sample
Atlas:  blender -b -t 3 --python generate_heavy_guard.py -- --all
Pack: python3 pack_heavy_guard.py
No downloaded models; fixed orthographic 55-degree camera; world-fixed key.
"""
import bpy, math, random, os, sys, json, time
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
from math import sin, cos, pi
OUT=os.path.dirname(os.path.abspath(__file__));random.seed(106)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials):bpy.data.materials.remove(m)

def painted(name,colors,scale=3,rough=.82,metal=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;n.clear()
 out=n.new('ShaderNodeOutputMaterial');p=n.new('ShaderNodeBsdfPrincipled');p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
 coord=n.new('ShaderNodeTexCoord');noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=scale;noise.inputs['Detail'].default_value=2;noise.inputs['Roughness'].default_value=.65
 ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
 for i,col in enumerate(colors):
  e=ramp.color_ramp.elements[0] if i==0 else ramp.color_ramp.elements.new(i/(len(colors)-1));e.position=i/(len(colors)-1);e.color=(*col,1)
 l.new(coord.outputs['Generated'],noise.inputs['Vector']);l.new(noise.outputs['Fac'],ramp.inputs[0]);l.new(ramp.outputs[0],p.inputs['Base Color']);l.new(p.outputs[0],out.inputs[0]);return m
stone=painted('OLD LIMESTONE broad brushed planes',[(.17,.205,.175),(.30,.335,.275),(.48,.48,.355)],3.0)
lightstone=painted('WORN WARM STONE cut edges',[(.29,.31,.24),(.48,.48,.35),(.60,.57,.40)],3.2)
slate=painted('DEEP GREEN GREY stone core',[(.055,.085,.081),(.12,.165,.145),(.225,.26,.20)],2.7)
dark=painted('DARK RECESSES weathered crevices',[(.017,.027,.023),(.039,.055,.043)],2)
bronze=painted('OLD COPPER brushed umber verdigris',[(.11,.072,.027),(.27,.165,.058),(.42,.285,.106)],4,.66,.38)
copperedge=painted('RUBBED COPPER old warm edge',[(.20,.118,.04),(.40,.265,.095),(.51,.37,.16)],4,.59,.42)
moss=painted('SPARSE DRY MOSS',[(.08,.11,.025),(.17,.22,.058),(.27,.29,.073)],6)
cloth=painted('DUSTY OXBLOOD old ceremonial tabard',[(.07,.024,.013),(.16,.055,.021),(.24,.103,.047)],4,.94)
spirit=painted('DULL AMBER small inset stones',[(.39,.16,.018),(.69,.34,.045)],3,.56)

def empty(name,loc=(0,0,0),parent=None):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=loc;o.parent=parent;return o
root=empty('HEARTHWARD_root')

def mesh(name,verts,faces,mat,parent,bevel=.035):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);o.data.materials.append(mat);o.parent=parent
 if bevel:
  m=o.modifiers.new('Weather-softened broad chips','BEVEL');m.width=bevel;m.segments=2
  m=o.modifiers.new('Weighted carved planes','WEIGHTED_NORMAL');m.keep_sharp=True;m.weight=35
 return o

def block(name,loc,half,mat,parent,bevel=.045,rot=(0,0,0),taper=1,seed=0):
 # Rectangular handmade block with unequal chamfer corners; never a sphere.
 x,y,z=half;cut=.19
 outline=[(-1+cut,-1),(1-cut,-1),(1,-1+cut),(1,1-cut),(1-cut,1),(-1+cut,1),(-1,1-cut),(-1,-1+cut)]
 rng=random.Random(seed);j=[rng.uniform(.92,1.065) for _ in outline];verts=[]
 for zi,s in [(-z,taper),(z,1)]:
  for i,(xx,yy) in enumerate(outline):verts.append((xx*x*s*j[i],yy*y*s*j[i],zi))
 faces=[tuple(range(7,-1,-1)),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
 o=mesh(name,verts,faces,mat,parent,bevel);o.location=loc;o.rotation_euler=rot;return o

def slab(name,outline,depth,loc,mat,parent,rot=(0,0,0),bevel=.027):
 n=len(outline);v=[(x,y,z) for z in (-depth/2,depth/2) for x,y in outline];f=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 o=mesh(name,v,f,mat,parent,bevel);o.location=loc;o.rotation_euler=rot;return o

def strap(name,p1,p2,width,depth,mat,parent):
 a,b=Vector(p1),Vector(p2);o=block(name,(a+b)/2,(width/2,depth/2,(b-a).length/2),mat,parent,.009);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o

def rivet(name,loc,rad,mat,parent):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=10,ring_count=5,radius=1,location=(0,0,0));o=bpy.context.object;o.name=name;o.parent=parent;o.location=loc;o.scale=(rad,rad*.4,rad);o.data.materials.append(mat);return o

# Coarse angular stone volumes, with offset cross sections and broad planes.
# Uneven radii create anatomical bends; these are not scaled primitive boxes.
def rock(name,loc,half,mat,parent,seed=0,rot=(0,0,0),curve=.0,profile=None):
 rng=random.Random(seed);n=9;x,y,z=half
 if profile is None:profile=[(-1,.48,.61,0),(-.68,.86,.89,-curve*.35),(-.03,1,1,-curve),(.63,.84,.83,-curve*.32),(1,.48,.48,curve*.12)]
 j=[rng.uniform(.88,1.13) for i in range(n)];v=[]
 for zi,rx,ry,cy in profile:
  for i in range(n):
   a=2*pi*i/n+pi/(2*n);v.append((x*rx*cos(a)*j[i],y*ry*sin(a)*j[i]+cy,z*zi+(.025*sin(i*2.7+seed) if abs(zi)<1 else 0)))
 f=[tuple(range(n-1,-1,-1))]
 for r in range(len(profile)-1):
  for i in range(n):a=r*n+i;b=r*n+(i+1)%n;f.append((a,b,b+n,a+n))
 f.append(tuple(range((len(profile)-1)*n,len(profile)*n)))
 o=mesh(name,v,f,mat,parent,.018);o.location=loc;o.rotation_euler=rot;return o

def cuff(name,loc,rx,ry,depth,mat,parent,rot=(0,0,0)):
 n=12;v=[]
 for z,r in [(-depth/2,1),(-depth/2,.84),(depth/2,.84),(depth/2,1)]:
  for i in range(n):a=2*pi*i/n;v.append((rx*r*cos(a),ry*r*sin(a),z))
 f=[]
 for row in range(4):
  for i in range(n):f.append((row*n+i,row*n+(i+1)%n,((row+1)%4)*n+(i+1)%n,((row+1)%4)*n+i))
 o=mesh(name,v,f,mat,parent,.012);o.location=loc;o.rotation_euler=rot;return o

def footshape(name,parent,mat,seed):
 # Broad slanted forefoot and narrow rounded heel, carved from one mass.
 outline=[(-.14,.36),(.15,.34),(.23,.15),(.24,-.08),(.35,-.33),(.29,-.56),(.11,-.67),(-.17,-.64),(-.34,-.46),(-.30,-.19),(-.22,.02),(-.22,.23)]
 n=len(outline);v=[(x,y,-.11) for x,y in outline]
 for i,(x,y) in enumerate(outline):v.append((x*.88,y*.90,.15+.035*sin(i*2.2+seed)))
 v += [(0,-.05,.26),(0,-.38,.225)]
 f=[tuple(range(n-1,-1,-1))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 for i in range(n):f.append((n+i,n+(i+1)%n,2*n+(1 if outline[i][1]<-.23 else 0)))
 f += [(n+3,2*n,2*n+1),(n+9,2*n+1,2*n)]
 return mesh(name,v,f,mat,parent,.028)

pelvis=empty('pelvis_weight',(0,0,1.30),root)
rock('Narrow load-bearing stone hips',(0,.03,.0),(.50,.34,.34),slate,pelvis,7,curve=.08)
cuff('Worn old copper girdle',(0,-.01,.14),.51,.345,.15,bronze,pelvis,rot=(.05,0,.05))
rock('Weathered stone belt clasp',(-.09,-.347,.12),(.14,.072,.17),lightstone,pelvis,5)
slab('Torn old ceremony tabard',[(-.20,.31),(.23,.32),(.22,-.35),(.06,-.46),(-.07,-.36),(-.18,-.42)],.026,(0,-.312,-.26),cloth,pelvis,rot=(pi/2,0,.04),bevel=.008)
chest=empty('chest_breath',(0,.04,.37),pelvis)
# The spine arches behind the narrowing waist; upper torso has sloped trapezius.
rock('Arched massive stone ribcage',(0,.025,.35),(.77,.46,.68),slate,chest,23,profile=[(-1,.49,.58,-.05),(-.65,.73,.86,.015),(-.03,1,1,.045),(.60,.91,.94,.10),(1,.55,.60,.14)])
# Two unequal curved hewn pectoral plates, with an oblique broken seam.
rock('Left great pectoral stone',(-.295,-.318,.47),(.42,.19,.40),stone,chest,33,rot=(.09,-.10,-.15),curve=.035)
rock('Right broken pectoral stone',(.285,-.31,.45),(.405,.18,.34),lightstone,chest,81,rot=(.11,.19,.20),curve=.05)
rock('Low sloped abdomen stone',(0,-.281,-.05),(.43,.14,.29),stone,chest,91,rot=(.12,.05,.10),curve=.045)
# One discontinuous copper binding, not a matrix of rectangular armour panels.
strap('Oblique old copper harness',(-.49,-.454,.83),(.25,-.447,.08),.066,.023,bronze,chest)
rock('Copper worn harness boss',(-.08,-.491,.42),(.08,.033,.09),copperedge,chest,41)
rock('Upper hunched back shoulder mass',(0,.30,.57),(.62,.27,.46),stone,chest,18,rot=(.18,0,.035),curve=-.05)
rock('Lower broken back plate',(.04,.373,.00),(.43,.125,.27),stone,chest,64,rot=(.20,0,-.13))
block('Back old copper clasp',(-.12,.514,.23),(.10,.023,.17),bronze,chest,.014,rot=(0,0,-.2))
rock('Forward sloping neck',(0,-.03,1.00),(.27,.245,.25),slate,chest,42,rot=(-.25,0,0))
head=empty('head_watch',(0,-.18,1.13),chest);head.rotation_euler.x=-.36
# A forward-set ancient stone helmet/face, never a cubic robot head.
rock('Hewn angular helmet',(0,.03,.17),(.375,.32,.39),bronze,head,55,curve=.05,profile=[(-1,.62,.74,0),(-.62,.92,.94,-.025),(0,1,1,.01),(.58,.87,.89,.055),(1,.49,.58,.07)])
rock('Deep visor hollow',(0,-.288,.071),(.291,.071,.107),dark,head,4)
for sign in [-1,1]:
 rock('Deep amber eye '+str(sign),(sign*.128,-.351,.085),(.057,.017,.027),spirit,head,5)
 rock('Slanted carved brow '+str(sign),(sign*.167,-.313,.227),(.212,.116,.095),lightstone,head,15+sign,rot=(0,sign*.14,sign*-.11))
 rock('Broken stone cheek '+str(sign),(sign*.235,-.225,-.082),(.128,.122,.162),stone,head,34+sign,rot=(.09,sign*.17,sign*.06))
rock('Carved long nose',(0,-.372,.025),(.064,.077,.164),lightstone,head,2,rot=(-.12,0,.025))
rock('Deep tapered stone chin',(0,-.214,-.18),(.21,.131,.125),slate,head,19,rot=(.12,0,0))
rock('Worn low stone crown ridge',(-.035,.053,.526),(.10,.244,.09),stone,head,50,rot=(-.08,0,-.09))
slab('Small helmet moss patch',[(-.09,-.075),(.06,-.11),(.12,.025),(.055,.082),(-.085,.06)],.012,(-.14,.105,.486),moss,head,rot=(0,-.12,0),bevel=.003)
arms={};elbows={};legs={};knees={};feet={}
for sign,label in [(-1,'L'),(1,'R')]:
 arm=empty(label+'_shoulder',(sign*.79,.065,.73),chest);arms[label]=arm;arm.rotation_euler.x=-.09;arm.rotation_euler.y=-sign*.085
 rock(label+' recessed shoulder',(sign*.015,.007,-.03),(.235,.256,.274),dark,arm,6+sign)
 # Deliberately unequal shell masses: missing front bite on R, high rear L.
 if label=='L':
  outline=[(-.36,-.23),(-.13,-.40),(.16,-.35),(.35,-.18),(.38,.11),(.16,.41),(-.14,.44),(-.39,.20)]
  depth=.36;off=(sign*.11,.03,.17);rot=(-.18,sign*.21,-.12)
 else:
  outline=[(-.35,-.31),(-.07,-.43),(.10,-.34),(.095,-.21),(.37,-.14),(.43,.16),(.16,.36),(-.17,.33),(-.35,.13)]
  depth=.27;off=(sign*.12,-.04,.13);rot=(.15,sign*.29,.07)
 slab(label+' asymmetric shoulder shell',outline,depth,off,stone if label=='L' else lightstone,arm,rot=rot,bevel=.052)
 rock(label+' lower shoulder wedge',(sign*.165,-.085,-.087),(.322,.328,.161),stone,arm,24+sign,rot=(.20,sign*.21,0))
 strap(label+' old copper shoulder stitch',(sign*.08,-.319,.265),(sign*.22,-.350,-.01),.070,.032,bronze,arm)
 if label=='L':slab('Sparse high shoulder moss',[(-.10,-.06),(.08,-.11),(.17,.025),(.035,.13),(-.15,.065)],.012,(-.11,.10,.36),moss,arm,rot=rot,bevel=.003)
 # Each limb is a bent irregular multi-section hewn volume, with muscular taper.
 rock(label+' curved massive upper arm',(sign*.048,.01,-.413),(.252,.28,.39),slate,arm,61+sign,curve=.082,rot=(.06,sign*-.08,0),profile=[(-1,.59,.57,-.015),(-.6,.91,.85,-.038),(0,1,1,-.095),(.65,.90,.88,-.06),(1,.57,.64,0)])
 rock(label+' upper arm stone facing',(sign*.077,-.203,-.38),(.215,.126,.285),stone,arm,81+sign,curve=.055,rot=(.09,sign*.10,sign*.05))
 elbow=empty(label+'_elbow',(sign*.082,-.038,-.735),arm);elbows[label]=elbow;elbow.rotation_euler.x=-.18
 rock(label+' sunk elbow joint',(0,0,.055),(.202,.229,.195),dark,elbow,31+sign)
 rock(label+' bowed heavy forearm',(sign*.055,-.025,-.245),(.324,.301,.35),stone,elbow,24+sign,curve=.085,rot=(.10,sign*-.08,0),profile=[(-1,.62,.63,-.015),(-.66,.83,.84,-.041),(-.04,1,1,-.09),(.68,.85,.80,-.04),(1,.55,.56,.008)])
 rock(label+' forearm worn crest',(sign*.058,-.229,-.17),(.225,.135,.26),lightstone,elbow,77+sign,rot=(.12,sign*.08,-sign*.10),curve=.025)
 cuff(label+' narrow copper wrist',(sign*.073,-.064,-.476),.25,.252,.095,bronze,elbow,rot=(.11,0,sign*.07))
 hand=empty(label+'_fist',(sign*.077,-.105,-.627),elbow)
 rock(label+' great clenched stone hand',(0,-.038,.008),(.275,.248,.201),slate,hand,21+sign,rot=(.11,0,-sign*.13))
 for finger in range(3):rock(label+' blunt curved finger '+str(finger),((finger-1)*.149,-.178,-.054),(.079,.121,.135),stone,hand,50+finger,rot=(.15,0,(finger-1)*-.09))
 rock(label+' folded stone thumb',(-sign*.222,-.127,.066),(.088,.129,.118),lightstone,hand,81,rot=(-.18,sign*.30,0))
 # Bent planted legs, with the knee visibly forward and the heel tucked back.
 leg=empty(label+'_hip',(sign*.365,.018,-.205),pelvis);legs[label]=leg;leg.rotation_euler.x=-.19
 rock(label+' muscular stone thigh',(sign*.03,.04,-.204),(.283,.28,.32),slate,leg,31+sign,curve=.055,rot=(.12,sign*-.07,0))
 rock(label+' oblique thigh plate',(sign*.066,-.177,-.145),(.235,.155,.285),stone,leg,47+sign,rot=(.18,sign*.14,-sign*.12),curve=.025)
 knee=empty(label+'_knee',(0,.006,-.435),leg);knees[label]=knee;knee.rotation_euler.x=.36
 rock(label+' sunk knee joint',(0,0,.02),(.206,.225,.158),dark,knee,4+sign)
 rock(label+' round hewn knee shield',(0,-.212,.03),(.246,.145,.207),lightstone,knee,55+sign,rot=(.14,0,sign*.09))
 rock(label+' slanted lower leg',(0,.044,-.246),(.237,.231,.262),slate,knee,61+sign,curve=-.045,profile=[(-1,.66,.70,0),(-.6,.88,.88,.03),(.14,1,1,.055),(.66,.76,.88,.02),(1,.53,.60,0)])
 cuff(label+' shin copper binding',(0,.045,-.27),.232,.238,.065,bronze,knee,rot=(.08,0,.07))
 foot=empty(label+'_foot',(0,-.025,-.478),knee);feet[label]=foot;foot.rotation_euler.x=-.17;foot.rotation_euler.z=-sign*.10
 footshape(label+' broad forefoot and round heel',foot,stone,21+sign)
 rock(label+' worn forward instep',(0,-.14,.132),(.253,.30,.15),lightstone,foot,41+sign,rot=(.10,0,sign*.07))
 for toe in [-1,1]:rock(label+' large split front toe '+str(toe),(toe*.156,-.515,-.014),(.142,.187,.113),slate,foot,31+toe,rot=(0,0,-toe*.14))
 cuff(label+' partial old heel binding',(0,.186,.082),.202,.137,.07,bronze,foot,rot=(.05,0,0))

scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=64;scene.cycles.use_denoising=False;scene.cycles.max_bounces=4;scene.cycles.diffuse_bounces=2;scene.cycles.glossy_bounces=2
scene.render.threads_mode='FIXED';scene.render.threads=3;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.image_settings.color_depth='8';scene.render.film_transparent=True;scene.render.fps=12
scene.world.use_nodes=True;scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.50,.57,.66,1);scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.65

def area(name,loc,power,size,color):
 d=bpy.data.lights.new(name,'AREA');o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.location=loc;d.energy=power;d.shape='DISK';d.size=size;d.color=color;o.rotation_euler=(Vector((0,0,1.7))-o.location).to_track_quat('-Z','Y').to_euler()
area('WORLD fixed warm upper-left key',(-3,-4,8),650,4,(1,.90,.73));area('WORLD cool broad bounce',(4,2,5),220,5,(.64,.76,1))
camera_data=bpy.data.cameras.new('Orthographic55');cam=bpy.data.objects.new('Orthographic55',camera_data);bpy.context.collection.objects.link(cam);scene.camera=cam;cam.data.type='ORTHO';cam.data.sensor_fit='VERTICAL';cam.data.ortho_scale=5.0
el=math.radians(55);cam.location=(0,-10*cos(el),10*sin(el));cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler()
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.1
scene['asset_name']='Hearthward / 遗迹重甲守卫';scene['model_forward']='-Y';scene['camera_elevation_degrees']=55;scene['key_light_world_position']=[-3,-4,8];scene['no_baked_floor_or_shadow']=True
# Model feet begin at -0.115. Translate the entire rigid hierarchy once so stance is on z=0.
bpy.context.view_layer.update();low=min((o.matrix_world@v.co).z for o in bpy.data.objects if o.type=='MESH' for v in o.data.vertices);root.location.z=-low
base={o.name:(o.location.copy(),o.rotation_euler.copy()) for o in [root,pelvis,chest,head,*arms.values(),*elbows.values(),*legs.values(),*knees.values(),*feet.values()]}

def pose(direction,animation,frame):
 for name,(loc,rot) in base.items():o=bpy.data.objects[name];o.location=loc.copy();o.rotation_euler=rot.copy()
 root.rotation_euler.z=math.radians(90-45*direction)
 if animation=='idle':
  p=2*pi*frame/4;chest.rotation_euler.x=.009*sin(p);chest.location.z+=.009*sin(p);head.rotation_euler.z=.012*sin(p+.5)
  for label,s in [('L',-1),('R',1)]:arms[label].rotation_euler.x+=.018*sin(p+s*.4)
 elif animation=='walk':
  p=2*pi*frame/8;stride=sin(p);pelvis.location.z+=.018*(1-cos(2*p));pelvis.rotation_euler.y=.030*stride;chest.rotation_euler.z=.025*stride
  for label,s in [('L',-1),('R',1)]:
   a=.17*stride*s;legs[label].rotation_euler.x+=a;knees[label].rotation_euler.x+=max(0,-a)*.20;feet[label].rotation_euler.x+=-a-max(0,-a)*.20
   legs[label].location.z+=.062*max(0,cos(p+(pi if s==-1 else 0)))
   arms[label].rotation_euler.x+=-a*.72;elbows[label].rotation_euler.x+=-.04*max(0,-stride*s)
  head.rotation_euler.z=-.018*stride
 elif animation=='attack':
  # Grounded shoulder windup, great forward arm sweep, impact compression, recovery.
  lean=[0,-.055,.045,.09,.04,0][frame];swing=[0,-.20,.29,.40,.18,0][frame]
  chest.rotation_euler.x=lean;chest.rotation_euler.z=[0,-.045,.02,.055,.018,0][frame];pelvis.location.z += [0,.013,-.025,-.052,-.020,0][frame]
  for label,s in [('L',-1),('R',1)]:
   arms[label].rotation_euler.x+=-swing*(1 if label=='R' else .74);arms[label].rotation_euler.y+=s*[0,.025,-.025,-.02,-.01,0][frame];elbows[label].rotation_euler.x+=[0,-.12,-.10,-.06,-.02,0][frame]
  head.rotation_euler.x=-.36-lean*.35
 bpy.context.view_layer.update()
 # Preserve genuine contacts, never use frame-dependent screen cropping.
 for label in ['L','R']:
  objects=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(label+' ') and ('forefoot' in o.name or 'instep' in o.name or 'toe' in o.name or 'heel binding' in o.name)]
  low=min((o.matrix_world@v.co).z for o in objects for v in o.data.vertices)
  if low<0:legs[label].location.z-=low
 bpy.context.view_layer.update()

def anchor_at(x,y):
 cam.data.shift_x=0;cam.data.shift_y=0;bpy.context.view_layer.update();q=world_to_camera_view(scene,cam,Vector((0,0,0)));cam.data.shift_y=.1;bpy.context.view_layer.update();q2=world_to_camera_view(scene,cam,Vector((0,0,0)));cam.data.shift_y=(q.y-(1-y/scene.render.resolution_y))/((q.y-q2.y)/.1);bpy.context.view_layer.update()

def bounds():
 xs=[];ys=[];ppu=scene.render.resolution_y/cam.data.ortho_scale;origin=world_to_camera_view(scene,cam,Vector((0,0,0)));ox=origin.x*scene.render.resolution_x;oy=(1-origin.y)*scene.render.resolution_y
 for o in bpy.data.objects:
  if o.type=='MESH' and not o.hide_render:
   for v in o.data.vertices:
    w=o.matrix_world@v.co;xs.append(ox+w.x*ppu);ys.append(oy-(w.y*sin(el)+w.z*cos(el))*ppu)
 return [min(xs),min(ys),max(xs),max(ys)]

def head_anchor():
 points=[]
 for o in bpy.data.objects:
  if o.type!='MESH':continue
  ancestor=o.parent
  while ancestor is not None and ancestor!=head:ancestor=ancestor.parent
  if ancestor==head:points.extend(o.matrix_world@v.co for v in o.data.vertices)
 top=max(points,key=lambda point:point.z)
 q=world_to_camera_view(scene,cam,top)
 return [round(q.x*128,3),round((1-q.y)*192,3)]

if '--sample' in sys.argv:
 scene.render.resolution_x=256;scene.render.resolution_y=256;cam.data.ortho_scale=4.4;anchor_at(128,188);pose(1,'idle',0)
 scene.render.filepath=os.path.join(OUT,'heavy_guard_sample.png');bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'heavy_guard.blend'));bpy.ops.render.render(write_still=True)
 json.dump({'sample':'heavy_guard_sample.png','resolution':[256,256],'ground_origin':[0,0,0],'foot_anchor_px':[128,188],'camera_elevation_degrees':55,'camera_ortho_scale':cam.data.ortho_scale,'direction':1,'body_projected_bounds':bounds(),'key_position':[-3,-4,8],'cycles_threads':3,'denoising':False},open(os.path.join(OUT,'sample_metadata.json'),'w'),indent=2)
 print('HEAVY_GUARD_SAMPLE_READY',bounds(),flush=True);sys.exit(0)

scene.render.resolution_x=128;scene.render.resolution_y=192;scene.cycles.samples=40;cam.data.ortho_scale=4.85;anchor_at(64,158)
contract=[]
for d in range(8):
 for anim,offset,count in [('idle',0,4),('walk',4,8),('attack',12,6)]:
  for f in range(count):contract.append((d*18+offset+f,d,anim,f))
allb=[]
for idx,d,anim,f in contract:pose(d,anim,f);allb.append(bounds())
bb=[min(b[0] for b in allb),min(b[1] for b in allb),max(b[2] for b in allb),max(b[3] for b in allb)]
fit=max(1,(64-bb[0])/59,(bb[2]-64)/59,(158-bb[1])/153,(bb[3]-158)/29);cam.data.ortho_scale*=fit*1.008;anchor_at(64,158)
allb=[]
for idx,d,anim,f in contract:pose(d,anim,f);allb.append(bounds())
bb=[min(b[0] for b in allb),min(b[1] for b in allb),max(b[2] for b in allb),max(b[3] for b in allb)]
print('CONTRACT_SCALE',cam.data.ortho_scale,'PROJECTED_BOUNDS',bb,flush=True)
if '--fit-only' in sys.argv:sys.exit(0)
meta={'asset_id':'brute','display_name':'Hearthward / 遗迹重甲守卫','family':'heavy_guard','version':1,'atlas_file':'brute_atlas.png','frame_width':128,'frame_height':192,'columns':16,'rows':9,'frame_count':144,'fps':12,'direction_order':['E','SE','S','SW','W','NW','N','NE'],'animation_offsets':{'idle':0,'walk':4,'attack':12},'animation_frames':{'idle':4,'walk':8,'attack':6},'frame_index':'direction*18 + animation_offset + frame','foot_anchor_px':[64,158],'ground_origin':[0,0,0],'model_forward':'-Y','root_yaw_formula_degrees':'90 - 45 * direction','camera_elevation_degrees':55,'camera_ortho_scale':cam.data.ortho_scale,'camera_sensor_fit':'VERTICAL','camera_position':list(cam.location),'camera_shift_y':cam.data.shift_y,'key_light_position':[-3,-4,8],'lighting_fixed_in_world':True,'transparent':True,'has_baked_shadow':False,'cycles_samples':40,'cycles_threads':3,'denoising':False,'global_projected_bounds':bb,'test_only':'--all' not in sys.argv,'frames':[]}
if '--anchors-only' in sys.argv:
 prior=json.load(open(os.path.join(OUT,'atlas_metadata.json')))
 for rec in prior['frames']:
  pose(rec['direction'],rec['animation'],rec['frame']);rec['head_top_anchor_px']=head_anchor()
 prior['head_top_anchor_semantics']='Projection of highest actual modeled head vertex in world Z for each pose; visual alpha top is separately recorded.'
 json.dump(prior,open(os.path.join(OUT,'atlas_metadata.json'),'w'),ensure_ascii=False,indent=2)
 print('ACTUAL_HEAD_ANCHORS_UPDATED',flush=True);sys.exit(0)
selected=contract if '--all' in sys.argv else [contract[i] for i in [d*18 for d in range(8)]]
os.makedirs(os.path.join(OUT,'frames'),exist_ok=True);start=time.time()
for idx,d,anim,f in selected:
 pose(d,anim,f);scene.render.filepath=os.path.join(OUT,'frames',f'{idx:03d}.png');t=time.time();bpy.ops.render.render(write_still=True)
 foot=world_to_camera_view(scene,cam,Vector((0,0,0)));hp=world_to_camera_view(scene,cam,head.matrix_world@Vector((0,.045,.69)))
 meta['frames'].append({'index':idx,'direction':d,'animation':anim,'frame':f,'file':f'frames/{idx:03d}.png','atlas_rect':[(idx%16)*128,(idx//16)*192,128,192],'foot_anchor_px':[round(foot.x*128,4),round((1-foot.y)*192,4)],'head_top_anchor_px':head_anchor(),'mesh_projected_bounds':bounds(),'render_seconds':round(time.time()-t,3)})
 print('FRAME_DONE',idx,round(time.time()-t,3),flush=True)
meta['total_render_seconds']=round(time.time()-start,3);json.dump(meta,open(os.path.join(OUT,'atlas_metadata.json'),'w'),ensure_ascii=False,indent=2);pose(2,'idle',0);scene['foot_anchor_px']=[64,158];bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'heavy_guard_atlas_source.blend'));print('DONE',meta['total_render_seconds'],flush=True)
