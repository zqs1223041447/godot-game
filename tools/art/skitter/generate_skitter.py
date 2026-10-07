"""Original six-legged Featherback Skitter. Procedural sculpted meshes only.
Blender 4.3.2 CPU: blender -b -t 3 --python generate_skitter.py -- --sample
After approval: --all ; package via python3 generate_skitter.py --pack
"""
import os,sys,json,math,hashlib
OUT=os.path.dirname(os.path.abspath(__file__))
if '--pack' in sys.argv:
 from PIL import Image,ImageDraw,ImageChops
 meta=json.load(open(OUT+'/atlas_metadata.json'));assert len(meta['frames'])==144 and not meta['test_only'];assert sorted(r['index'] for r in meta['frames'])==list(range(144))
 atlas=Image.new('RGBA',(2048,1728));bounds=[]
 for r in meta['frames']:
  im=Image.open(OUT+'/frames/%03d.png'%r['index']).convert('RGBA');assert im.size==(128,192)
  a=im.getchannel('A');b=a.getbbox();assert b and b[0]>0 and b[1]>0 and b[2]<128 and b[3]<192,(r['index'],b)
  r['alpha_bounds_px']=list(b);r['alpha_bounds_8_px']=list(a.point(lambda v:255 if v>=8 else 0).getbbox());bounds.append(b)
  at=((r['index']%16)*128,(r['index']//16)*192);atlas.paste(im,at)
  assert all(mx==0 for mn,mx in ImageChops.difference(atlas.crop((at[0],at[1],at[0]+128,at[1]+192)),im).getextrema())
 atlas.save(OUT+'/skitter_atlas.png',optimize=True)
 meta['all_frame_alpha_bounds_px']=[min(b[0] for b in bounds),min(b[1] for b in bounds),max(b[2] for b in bounds),max(b[3] for b in bounds)]
 meta['alpha_body_width_range_px']=[min(b[2]-b[0] for b in bounds),max(b[2]-b[0] for b in bounds)]
 meta['alpha_body_height_range_px']=[min(b[3]-b[1] for b in bounds),max(b[3]-b[1] for b in bounds)]
 meta['atlas_sha256']=hashlib.sha256(open(OUT+'/skitter_atlas.png','rb').read()).hexdigest()
 meta['qa']={'all_144_rgba_frames':True,'all_frames_unclipped':True,'shared_ground_anchor':[64,142],'baked_ground_or_shadow':False,'tiles_match_native_frames':True,'animation_damage_events':False}
 meta['qa']['rgba_all_channel_pixel_equality']=True
 meta['display_scale_note']='0.59 is provisional; parent integration chooses a uniform scale from measured silhouette bounds and target 40–45 world units.'
 if os.path.exists(OUT+'/blend_verification.json'):
  verified=json.load(open(OUT+'/blend_verification.json'));meta['qa']['ground_anchor_measured_px']=verified['ground_anchor_projection_px'];meta['qa']['six_foot_two_eye_model_verified']=verified['foot_count']==6 and verified['eye_count']==2
 json.dump(meta,open(OUT+'/atlas_metadata.json','w'),indent=2,ensure_ascii=False)
 sheet=Image.new('RGBA',(1024,224),(29,34,30,255));dr=ImageDraw.Draw(sheet)
 for d,name in enumerate(meta['direction_order']):
  sheet.alpha_composite(Image.open(OUT+'/frames/%03d.png'%(18*d)),(128*d,20));dr.text((128*d+10,7),str(d)+' '+name,fill=(236,224,196))
 sheet.convert('RGB').save(OUT+'/direction_contact_sheet.png')
 print('PACKED',meta['all_frame_alpha_bounds_px'],meta['alpha_body_height_range_px']);sys.exit(0)
import bpy
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
from math import sin,cos,pi
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials):bpy.data.materials.remove(m)
def mat(name,cols,scale=3.7,rough=.8,metal=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;n.clear()
 out=n.new('ShaderNodeOutputMaterial');bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
 tex=n.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=scale;tex.inputs['Detail'].default_value=2;tex.inputs['Roughness'].default_value=.65
 ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
 for i,col in enumerate(cols):
  e=ramp.color_ramp.elements[0] if i==0 else ramp.color_ramp.elements.new(i/(len(cols)-1));e.position=i/(len(cols)-1);e.color=(*col,1)
 l.new(tex.outputs['Fac'],ramp.inputs[0]);l.new(ramp.outputs[0],bs.inputs['Base Color']);l.new(bs.outputs[0],out.inputs[0]);return m
skin=mat('Supple muted jade hide',[(.042,.071,.054),(.115,.175,.122),(.22,.28,.19)],3.7)
feather=mat('Swept sage shell feathers',[(.16,.21,.17),(.34,.39,.29),(.47,.49,.35)],4)
featherdeep=mat('Old dark grey green rear feathers',[(.055,.084,.066),(.12,.18,.125),(.23,.29,.20)],4)
edge=mat('Dry pale feather margins',[(.30,.33,.23),(.47,.48,.33),(.57,.54,.38)],5)
dark=mat('Soft dark seams',[(.026,.042,.028),(.066,.089,.05)],4)
bronze=mat('Sparse old copper guards',[(.10,.081,.032),(.235,.164,.056),(.32,.239,.096)],4,.54,.55)
pale=mat('Hornlike foot paddles',[(.26,.28,.18),(.48,.47,.30)],5)
eye=mat('Tiny living amber eyes',[(.62,.215,.012),(.90,.42,.047)],5,.35)
p=eye.node_tree.nodes.get('Principled BSDF');p.inputs['Emission Color'].default_value=(1,.24,.005,1);p.inputs['Emission Strength'].default_value=.32

def empty(name,loc=(0,0,0),parent=None):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=loc;o.parent=parent;return o
root=empty('SKITTER_root');body=empty('body_sway',(0,0,.94),root);head=empty('head_nod',(0,-.43,.01),body)

def mesh(name,v,f,m,parent=None,smooth=True,sub=0):
 me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);o.data.materials.append(m);o.parent=parent
 for p in me.polygons:p.use_smooth=smooth
 if sub:mod=o.modifiers.new('Subtle sculpt smoothing','SUBSURF');mod.levels=sub;mod.render_levels=sub
 return o
# Cross-section lofts have individually art-directed dorsal and ventral volume.
def torso(name,rings,m,parent,sections=16):
 v=[];f=[]
 for y,w,top,bot,z in rings:
  for i in range(sections):
   a=2*pi*i/sections;s=sin(a);v.append((w*cos(a),y,z+s*(top if s>=0 else bot)))
 f.append(tuple(range(sections-1,-1,-1)))
 for j in range(len(rings)-1):
  for i in range(sections):a=j*sections+i;b=j*sections+(i+1)%sections;f.append((a,b,b+sections,a+sections))
 f.append(tuple(range((len(rings)-1)*sections,len(rings)*sections)));return mesh(name,v,f,m,parent,True,1)
# Narrow pinched thorax, long tapered abdomen, no spherical primitive assemblies.
torso('Narrow vaulted thorax',[(-.51,.055,.035,.035,0),(-.40,.18,.14,.115,0),(-.26,.27,.225,.14,0),(-.03,.255,.21,.14,0),(.19,.195,.16,.12,-.01),(.27,.08,.075,.07,-.01)],skin,body)
torso('Long segmented abdomen',[(.12,.12,.10,.08,0),(.30,.25,.16,.125,-.025),(.52,.28,.18,.125,-.03),(.76,.20,.12,.08,-.045),(1.02,.065,.05,.03,-.08),(1.10,.01,.008,.008,-.08)],skin,body)
# Leaf-feather is a swept dorsal plate, flat ventral, raised central ridge, tapered hooked tip.
def leaf(name,path,widths,heights,m,parent):
 v=[];f=[];N=8
 for (x,y,z),w,h in zip(path,widths,heights):
  # sculpted convex dorsal profile, knife-like edges, shallow underside
  sec=[(-w,0),(-w*.66,h*.63),(0,h),(w*.66,h*.63),(w,0),(w*.60,-h*.22),(0,-h*.30),(-w*.60,-h*.22)]
  for xx,zz in sec:v.append((x+xx,y,z+zz))
 f=[tuple(range(N-1,-1,-1))]
 for j in range(len(path)-1):
  for i in range(N):a=j*N+i;b=j*N+(i+1)%N;f.append((a,b,b+N,a+N))
 f.append(tuple(range((len(path)-1)*N,len(path)*N)));return mesh(name,v,f,m,parent,True,1)
# Three overlapping shield-feathers emphasize streamlining and segmentation.
for i,(y,w,z) in enumerate([(-.22,.235,.17),(.08,.25,.155),(.39,.245,.135)]):
 leaf('Dorsal swept feather %d'%i,[(0,y-.17,z),(0,y-.09,z+.025),(0,y+.11,z),(0,y+.39,z-.065),(0,y+.48,z-.10)],[w*.50,w,w*.89,w*.30,.006],[.045,.10,.095,.035,.006],[feather,edge,featherdeep][i],body)
 # A single narrow median ridge creates readable planes rather than decorative noisy lines.
 leaf('Dorsal old copper inset %d'%i,[(0,y-.10,z+.12),(0,y+.02,z+.115),(0,y+.17,z+.070)],[.017,.021,.004],[.003,.008,.002],bronze if i==0 else feather,body)
# Outboard paired vanes swept back, small enough to preserve a slim racing animal.
for side in [-1,1]:
 for i in range(3):
  y=-.12+i*.24;x=side*(.16+i*.015);z=.10-i*.024
  leaf(('Left' if side<0 else 'Right')+' folded flank vane %d'%i,[(x,y-.10,z),(x+side*.105,y+.08,z+.02),(x+side*.16,y+.37,z-.035),(x+side*.20,y+.65,z-.11)],[.052,.095,.076,.003],[.045,.08,.047,.003],featherdeep if i==2 else feather,body)
# Tail pennant split into three small overlapping feathers.
for i in [-1,0,1]:
 leaf('Tail feather %d'%i,[(i*.04,.67,-.015),(i*.095,.89,-.025),(i*.16,1.22,-.09)],[.035,.067,.003],[.04,.065,.003],edge if i==0 else feather,body)
# Wedge-shaped head with a broad forehead and a soft beaked muzzle.
torso('Distinct curious head',[(-.66,.035,.035,.025,-.075),(-.60,.13,.072,.07,-.03),(-.48,.215,.14,.09,.01),(-.30,.20,.155,.115,.03),(-.16,.13,.105,.075,.025),(-.11,.06,.05,.035,0)],skin,head)
leaf('Forehead swept crown',[(0,-.58,.055),(0,-.40,.175),(0,-.22,.18),(0,-.04,.09)],[.025,.125,.108,.003],[.01,.036,.04,.004],feather,head)
# Oval inset eyes are small custom eight-ring meshes, nested under protective eyebrows.
for side in [-1,1]:
 eyeob=torso('Recessed amber eye '+str(side),[(-.08,.004,.004,.004,0),(-.065,.030,.028,.028,0),(0,.041,.039,.039,0),(.045,.024,.027,.027,0),(.055,.004,.004,.004,0)],eye,head,12)
 eyeob.location=(side*.17,-.47,.080);eyeob.rotation_euler=(0,side*-.15,side*-.55)
 leaf('Brow frond '+str(side),[(side*.11,-.52,.13),(side*.18,-.43,.173),(side*.18,-.22,.14)],[.024,.037,.004],[.024,.034,.003],edge,head)
 leaf('Small cheek vane '+str(side),[(side*.15,-.34,.01),(side*.22,-.24,.025),(side*.25,-.06,.035)],[.045,.060,.003],[.018,.025,.003],feather,head)
# Gentle whisker-like antennae remain short; no horns or menacing mouthparts.
for side in [-1,1]:
 leaf('Backward sensory frond '+str(side),[(side*.08,-.25,.17),(side*.12,-.07,.255),(side*.15,.11,.22)],[.015,.022,.002],[.013,.02,.002],skin,head)
# Small age-worn copper collar side guards, explicitly not a full mechanical exoskeleton.
for side in [-1,1]:
 leaf('Ancient copper throat guard '+str(side),[(side*.11,-.44,.08),(side*.165,-.36,.13),(side*.15,-.20,.14)],[.034,.045,.014],[.022,.028,.004],bronze,body)
# Six long articulated legs. Loft geometry is sculpted to keep tendons and bent joints legible.
def leg_segment(name,length,radii,m):
 rings=[(0,radii[0]),(.07,radii[1]),(.30,radii[2]),(.70,radii[3]),(.93,radii[4]),(1,radii[5])];v=[];f=[];N=10
 for t,r in rings:
  for i in range(N):
   a=2*pi*i/N;v.append((r*cos(a),r*.72*sin(a)+.045*sin(pi*t),t*length))
 f=[tuple(range(N-1,-1,-1))]
 for j in range(len(rings)-1):
  for i in range(N):a=j*N+i;b=j*N+(i+1)%N;f.append((a,b,b+N,a+N))
 f.append(tuple(range((len(rings)-1)*N,len(rings)*N)));return mesh(name,v,f,m,root,True,1)
legs=[]
for side in [-1,1]:
 for j in range(3):
  tag=('L' if side<0 else 'R')+str(j);hip=Vector((side*[.22,.245,.205][j],[-.31,.035,.35][j],.925))
  foot=Vector((side*[.83,.99,.79][j],[-.81,.08,.91][j],.025))
  upper=leg_segment(tag+' curved upper leg',1,[.024,.083,.078,.060,.067,.030],skin)
  lower=leg_segment(tag+' tapered spring shank',1,[.030,.062,.060,.036,.025,.012],skin)
  joint=leg_segment(tag+' dark flexible knee seam',1,[.030,.069,.071,.066,.047,.028],dark)
  pad=leaf(tag+' soft horn foot',[(0,-.12,.025),(0,-.025,.04),(0,.075,.05)],[.009,.057,.035],[.009,.021,.011],pale,root)
  kneeguard=leaf(tag+' knee feather',[(0,-.06,0),(0,.0,.03),(0,.15,-.005)],[.014,.054,.005],[.011,.033,.002],feather,root)
  legs.append({'side':side,'j':j,'hip':hip,'foot':foot,'upper':upper,'lower':lower,'joint':joint,'pad':pad,'guard':kneeguard})
def orient(o,a,b):
 vec=b-a;o.location=a;o.rotation_euler=vec.to_track_quat('Z','Y').to_euler();o.scale=(1,1,vec.length)
def pose(direction,anim,frame):
 root.rotation_euler.z=math.radians(90-45*direction);body.location=(0,0,.94);body.rotation_euler=(0,0,0);head.rotation_euler=(0,0,0)
 p=2*pi*frame/(4 if anim=='idle' else 8);lunge=0
 if anim=='idle':body.location.z+=.009*sin(p);head.rotation_euler.x=.015*sin(p+.4)
 elif anim=='walk':body.location.z+=.018*cos(2*p);body.rotation_euler.y=.028*sin(p);head.rotation_euler.x=.035*cos(2*p)
 else:
  lunge=[0,-.08,.17,.25,.11,0][frame];body.location.y-=lunge;body.location.z+=[0,-.035,.018,-.035,-.02,0][frame];body.rotation_euler.x=[0,-.08,.055,.13,.05,0][frame];head.rotation_euler.x=[0,-.10,.04,.19,.08,0][frame]
 bpy.context.view_layer.update()
 for L in legs:
  side=L['side'];j=L['j'];foot=L['foot'].copy();hip=body.matrix_local@(L['hip']-Vector((0,0,.94)))
  if anim=='walk':
   ph=p+(pi if ((side==1 and j in (0,2)) or (side==-1 and j==1)) else 0)
   foot.y+=.16*cos(ph);foot.z+=.115*max(0,sin(ph))
  elif anim=='attack':
   if j==0:foot.y-=lunge*.74;foot.z+=[0,.045,.10,.025,.02,0][frame]
   elif j==2:foot.y+=lunge*.16
  knee=(hip+foot)*.5;knee.x+=side*[.17,.16,.16][j];knee.y+=[-.11,.10,.17][j];knee.z+=.24
  orient(L['upper'],hip,knee);orient(L['lower'],knee,foot);orient(L['joint'],knee,knee+(foot-knee)*.16)
  L['pad'].location=foot;L['pad'].rotation_euler=(0,0,side*[-.30,.08,.20][j]);L['guard'].location=knee;L['guard'].rotation_euler=(.42,side*.48,0)
 bpy.context.view_layer.update()
# Match accepted slate-and-bronze reference: AgX, broad warm key, cool bounce, matte surfaces.
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=56;scene.cycles.use_denoising=False;scene.render.threads_mode='FIXED';scene.render.threads=3
scene.cycles.max_bounces=4;scene.cycles.diffuse_bounces=2;scene.cycles.glossy_bounces=2
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.image_settings.color_depth='8';scene.render.film_transparent=True;scene.render.fps=12
scene.world.use_nodes=True;scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.50,.57,.66,1);scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.65
def area(name,loc,power,size,color):
 d=bpy.data.lights.new(name,'AREA');o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.location=loc;d.energy=power;d.shape='DISK';d.size=size;d.color=color;o.rotation_euler=(Vector((0,0,.7))-o.location).to_track_quat('-Z','Y').to_euler()
area('Fixed warm upper left key',(-3,-4,8),550,4.0,(1,.90,.73));area('Soft cool bounce',(4,2,5),220,5,(.64,.76,1))
d=bpy.data.cameras.new('Fixed Ortho55');cam=bpy.data.objects.new('Fixed Ortho55',d);bpy.context.collection.objects.link(cam);scene.camera=cam
el=math.radians(55);cam.location=(0,-10*cos(el),10*sin(el));cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=2.75
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.1
scene['asset_name']='Featherback Skitter / 甲羽掠行体';scene['model_forward']='-Y';scene['camera_elevation_degrees']=55;scene['root_ground_z']=0.;scene['no_animation_damage_events']=True
pose(1,'idle',0)
if '--sample' in sys.argv:
 scene.render.resolution_x=256;scene.render.resolution_y=256;scene.render.resolution_percentage=100;d.ortho_scale=3.1;d.shift_y=.055
 scene.render.filepath=OUT+'/skitter_sample.png';bpy.ops.wm.save_as_mainfile(filepath=OUT+'/skitter.blend');bpy.ops.render.render(write_still=True)
 json.dump({'sample':'skitter_sample.png','rgba':True,'camera_elevation':55,'direction':'SE','threads':3,'floor_or_shadow':False},open(OUT+'/sample_info.json','w'),indent=2);sys.exit(0)
scene.render.resolution_x=128;scene.render.resolution_y=192;scene.render.resolution_percentage=100;scene.cycles.samples=40;d.ortho_scale=3.95
# Ground origin is constant at (64,142) for all rotations, all animations, no per-frame cropping.
def anchor_shift():
 d.shift_x=0;d.shift_y=0;bpy.context.view_layer.update();q=world_to_camera_view(scene,cam,Vector((0,0,0)));d.shift_y=.1;bpy.context.view_layer.update();q2=world_to_camera_view(scene,cam,Vector((0,0,0)));d.shift_y=(q.y-(1-142/192))/((q.y-q2.y)/.1);bpy.context.view_layer.update()
def projected_bounds():
 xs=[];ys=[];deps=bpy.context.evaluated_depsgraph_get()
 for o in bpy.data.objects:
  if o.type=='MESH':
   ev=o.evaluated_get(deps);me=ev.to_mesh()
   for v in me.vertices:
    w=ev.matrix_world@v.co;ppu=192/d.ortho_scale;xs.append(64+w.x*ppu);ys.append(142-(w.y*sin(el)+w.z*cos(el))*ppu)
   ev.to_mesh_clear()
 return [min(xs),min(ys),max(xs),max(ys)]
contract=[(dd*18+off+f,dd,ani,f) for dd in range(8) for ani,off,n in [('idle',0,4),('walk',4,8),('attack',12,6)] for f in range(n)]
anchor_shift();bb=[]
for _,dd,ani,f in contract:pose(dd,ani,f);bb.append(projected_bounds())
b=[min(t[0] for t in bb),min(t[1] for t in bb),max(t[2] for t in bb),max(t[3] for t in bb)];fit=max(1,(64-b[0])/59,(b[2]-64)/59,(142-b[1])/136,(b[3]-142)/44);d.ortho_scale*=fit*1.008;anchor_shift()
meta={'asset_id':'skitter','display_name':'Featherback Skitter','source_files':['generate_skitter.py','skitter.blend'],'frame_size_px':[128,192],'atlas_size_px':[2048,1728],'columns':16,'rows':9,'fps':12,'direction_order':['E','SE','S','SW','W','NW','N','NE'],'yaw_formula_degrees':'90 - 45 * direction','animation_offsets':{'idle':0,'walk':4,'attack':12},'animation_counts':{'idle':4,'walk':8,'attack':6},'frame_index_formula':'direction * 18 + offset + frame','anchor_px':[64,142],'camera_elevation_degrees':55,'orthographic_scale':d.ortho_scale,'fixed_key_light_world':[-3,-4,8],'cycles_threads':3,'denoising':False,'no_floor_or_baked_shadow':True,'suggested_world_body_height':45,'recommended_display_scale':.59,'frames':[]}
os.makedirs(OUT+'/frames',exist_ok=True)
chosen=contract if '--all' in sys.argv else [contract[i] for i in [0,18,36,54,72,90,108,126,6,14]]
meta['test_only']='--all' not in sys.argv
pose(1,'idle',0);bpy.ops.wm.save_as_mainfile(filepath=OUT+'/skitter.blend')
for idx,dd,ani,f in chosen:
 pose(dd,ani,f);scene.render.filepath=OUT+'/frames/%03d.png'%idx;bpy.ops.render.render(write_still=True)
 meta['frames'].append({'index':idx,'direction':dd,'animation':ani,'frame':f,'anchor_px':[64,142],'geometry_bounds_px':projected_bounds()})
 json.dump(meta,open(OUT+'/atlas_metadata.json','w'),ensure_ascii=False,indent=2)
print('RENDER_COMPLETE',len(chosen),d.ortho_scale)
