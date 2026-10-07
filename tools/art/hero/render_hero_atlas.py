import bpy, math, json, os, sys, runpy
from mathutils import Vector, Matrix
from bpy_extras.object_utils import world_to_camera_view
OUT=os.path.dirname(os.path.abspath(__file__))
os.environ['HERO_MODEL_ONLY']='1'
ctx=runpy.run_path(os.path.join(OUT,'generate_hero.py'))
scene=bpy.context.scene
root=bpy.data.objects['HeroRoot'];root.scale=(.88,.88,1);joints=ctx['joints'];cam=scene.camera
scene.render.resolution_x=128;scene.render.resolution_y=192;scene.render.resolution_percentage=100
scene.cycles.samples=40;scene.cycles.use_denoising=False;scene.render.threads_mode='FIXED';scene.render.threads=3
camdir=Vector((0,-math.cos(math.radians(55)),math.sin(math.radians(55))))
cam.rotation_euler=(-camdir).to_track_quat('-Z','Y').to_euler();up=cam.rotation_euler.to_quaternion()@Vector((0,1,0))
cam.data.sensor_fit='VERTICAL';cam.data.ortho_scale=1.58
cam.location=up*(1.58*(158/192-.5))+camdir*7
key=bpy.data.objects['fixed screen upper left softbox'];key.location=(-3,-4,8);key.rotation_euler=(Vector((0,0,1))-key.location).to_track_quat('-Z','Y').to_euler();key.data.energy=600;key.data.size=4
fill=bpy.data.objects['soft front sky fill'];fill.location=(3,-4,4);fill.rotation_euler=(Vector((0,0,1))-fill.location).to_track_quat('-Z','Y').to_euler();fill.data.energy=165
# Hair remains modeled locks and shoulder plate retains the approved low convex silhouette.
foot=(0,0,0)
head_local=Vector((0,-.028,1.805))

def pivot(p,ax=None,ay=None,az=None):
 m=Matrix.Identity(4)
 for v,a in [(ax,'X'),(ay,'Y'),(az,'Z')]:
  if v is not None:m=m@Matrix.Rotation(v,4,a)
 return Matrix.Translation(p)@m@Matrix.Translation(-Vector(p))

cape=bpy.data.objects['short burgundy traveling cloak'];hem=bpy.data.objects['cape old wool hem']
base_verts=[v.co.copy() for v in cape.data.vertices]
base_hem=[p.co.copy() for p in hem.data.splines[0].bezier_points]

def pose(direction,animation,frame):
 yaw=math.radians(90-45*direction);root.rotation_euler=(0,0,yaw)
 for name,j in joints.items():j.matrix_basis=Matrix.Identity(4)
 joints['head'].matrix_basis=pivot((0,0,1.61),ax=math.radians(-18))
 flutter=0;bodybob=0
 if animation=='idle':
  phase=2*math.pi*frame/4;breath=math.sin(phase)
  joints['chest'].matrix_basis=pivot((0,0,1.03),ax=breath*.012)
  joints['left_arm'].matrix_basis=pivot((.235,0,1.41),ax=breath*.02)
  flutter=breath*.006
 elif animation=='walk':
  phase=2*math.pi*frame/8;stride=math.sin(phase);bodybob=.008*(1-math.cos(phase*2))
  joints['pelvis'].location.z=bodybob
  for side,sgn in [('right',1),('left',-1)]:
   ang=.245*stride*sgn;px=-.12 if side=='right' else .12
   m=pivot((px,0,.92),ax=ang)
   # Minimum of foot underside corners keeps the stance grounded without frame cropping.
   low=min((m@Vector((px,y,.025))).z for y in [-.23,.14])
   lift=.022*max(0,math.cos(phase+(0 if side=='right' else math.pi)))
   m.translation.z+=max(0,.012-low)+lift-bodybob
   joints[side+'_leg'].matrix_basis=m
  joints['right_arm'].matrix_basis=pivot((-.235,0,1.41),ax=-.115*stride)
  joints['left_arm'].matrix_basis=pivot((.235,0,1.41),ax=.14*stride)
  joints['chest'].matrix_basis=pivot((0,0,1.03),az=.025*stride)
  flutter=.018*math.sin(phase+.6)
 elif animation=='attack':
  # Short anticipatory draw, controlled forward cast, then recovery; no effect painted into sprite.
  swing=[-.04,-.07,.02,.24,.13,0][frame]
  lean=[-.008,-.018,.015,.042,.02,0][frame]
  joints['chest'].matrix_basis=pivot((0,0,1.03),ax=lean,az=swing*.13)
  joints['right_arm'].matrix_basis=pivot((-.235,0,1.41),ax=swing,ay=-swing*.28)
  joints['left_arm'].matrix_basis=pivot((.235,0,1.41),ax=-swing*.4)
  joints['head'].matrix_basis=pivot((0,0,1.61),ax=math.radians(-18)-lean*.4)
  flutter=swing*.08
 for v,base in zip(cape.data.vertices,base_verts):
  t=max(0,min(1,(1.48-base.z)/.68));v.co=base+Vector((flutter*t*math.sin(base.x*15),flutter*t*.6,0))
 for p,base in zip(hem.data.splines[0].bezier_points,base_hem):p.co=base+Vector((flutter*math.sin(base.x*15),flutter*.6,0))
 bpy.context.view_layer.update()

def anchors():
 f=world_to_camera_view(scene,cam,Vector(foot)); hp=joints['head'].matrix_world@head_local;h=world_to_camera_view(scene,cam,hp)
 return {'foot_anchor':[round(f.x*128,4),round((1-f.y)*192,4)],'head_anchor':[round(h.x*128,3),round((1-h.y)*192,3)]}

names=['east','southeast','south','southwest','west','northwest','north','northeast']
frames=[]
for direction in range(8):
 for anim,count,offset in [('idle',4,0),('walk',8,4),('attack',6,12)]:
  for f in range(count):
   idx=direction*18+offset+f;frames.append({'index':idx,'direction':direction,'direction_name':names[direction],'animation':anim,'animation_frame':f,'atlas_rect':[(idx%16)*128,(idx//16)*192,128,192],'file':f'frames/hero_{idx:03d}.png'})
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
preview='--preview' in args
selected=[frames[i] for i in [d*18+f for d in range(8) for f in [0,10,13,15]]] if preview else frames
repair='--repair' in args
if repair:
 prior=json.load(open(os.path.join(OUT,'hero_manifest.json')))
 frames=prior['frames']
 requested=set(map(int,args[args.index('--repair')+1].split(',')))
 selected=[r for r in frames if r['index'] in requested]
os.makedirs(os.path.join(OUT,'frames'),exist_ok=True)
for row in selected:
 pose(row['direction'],row['animation'],row['animation_frame']);row.update(anchors());scene.frame_set(row['index']+1)
 scene.render.filepath=os.path.join(OUT,row['file']);bpy.ops.render.render(write_still=True)
 print('HERO_RENDERED',row['index'],row['foot_anchor'],row['head_anchor'],flush=True)
if preview:
 with open(os.path.join(OUT,'preview_manifest.json'),'w') as f:json.dump(selected,f,indent=2)
else:
 manifest={'version':1,'actor':'hero','generator':'Blender 4.3.2 procedural mesh, Cycles CPU','frame_width':128,'frame_height':192,'atlas_columns':16,'atlas_rows':9,'atlas_width':2048,'atlas_height':1728,'fps':12,'foot_anchor':[64,158],'directions':names,'direction_yaw_degrees':[90-45*d for d in range(8)],'animation_offsets':{'idle':0,'walk':4,'attack':12},'animation_counts':{'idle':4,'walk':8,'attack':6},'frame_index_formula':'direction * 18 + animation_offset + animation_frame','camera':{'projection':'orthographic','elevation_degrees':55,'direction':[0,-math.cos(math.radians(55)),math.sin(math.radians(55))],'ortho_scale':cam.data.ortho_scale,'sensor_fit':'VERTICAL'},'light':{'key_position':[-3,-4,8],'model_rotation_independent':True},'alpha':'RGBA; transparent background; no baked ground or shadow','head_anchor_semantics':'projected top-of-head attachment point; frame-specific, in local frame pixels','frames':frames}
 with open(os.path.join(OUT,'hero_manifest.json'),'w') as f:json.dump(manifest,f,indent=2)
 pose(2,'idle',0);scene.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'hero_atlas_source.blend'))
