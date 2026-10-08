"""Finite v126 atlas; read approved local scenes and retain source geometry/actions.
No runtime edits, IK, per-frame grounding, source downloads or original-source writes.
"""
import bpy, json, math, hashlib, os, sys
import numpy as np
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
ARCHIVE=Path(__file__).resolve().parents[1]
if not os.environ.get('V126_SOURCE_BLEND') or not os.environ.get('V126_OUTPUT_DIR'):
 raise RuntimeError('Set explicit V126_SOURCE_BLEND and V126_OUTPUT_DIR local paths; no source scenes are redistributed.')
P=Path(os.environ['V126_OUTPUT_DIR']).expanduser().resolve()
SOURCE=Path(os.environ['V126_SOURCE_BLEND']).expanduser().resolve()
if P==ARCHIVE or ARCHIVE in P.parents:raise RuntimeError('Use output outside the archived research directory')
expected=json.loads((ARCHIVE/'reports/render-config.json').read_text())['source_blend_sha256']
if hashlib.sha256(SOURCE.read_bytes()).hexdigest()!=expected:raise RuntimeError('Approved local source scene SHA256 mismatch')
for rel in ['reports','samples','frames','atlas','licenses']:(P/rel).mkdir(parents=True,exist_ok=True)
(P/'.gdignore').touch()
for name in ['UAL_License.txt','base-License_Standard.txt','fantasy-License_Standard.txt']:
 license_source=Path(__file__).resolve().parents[1]/'licenses'/name
 license_destination=P/'licenses'/name
 if license_source.resolve()!=license_destination.resolve():license_destination.write_bytes(license_source.read_bytes())
bpy.ops.wm.open_mainfile(filepath=str(SOURCE),load_ui=False);s=bpy.context.scene
arms=[bpy.data.objects[n] for n in ['Armature','Armature.001','Armature.002']];assembly=bpy.data.objects['Ranger_Sample_Assembly'];cam=s.camera
char=[o for o in bpy.data.objects if o.type=='MESH' and (o.parent in arms or o.name=='Skinned_Shoulder_Lining_Bridge')]
for o in bpy.data.objects:
 if o.type=='MESH':o.hide_render=o not in char
for o in char:o.hide_render=False;o.visible_camera=True
for a in arms:
 if not a.animation_data:a.animation_data_create()
 for track in a.animation_data.nla_tracks:track.mute=True
# Ground compass definition: local forward is -Y; yaw+90 is screen-right.
DIRECTIONS=[('e',90),('se',45),('s',0),('sw',-45),('w',-90),('nw',-135),('n',180),('ne',135)]
ACTIONS={'idle':'Game_Idle_Loop','walk':'Trial_Walk80_Jog20_Loop','attack':'Game_Cast_Simple_Composite'}
SOURCE_FRAMES={'idle':[i*7.5 for i in range(10)],'walk':[i*30/16 for i in range(16)],'attack':[23,25.5,28,30.5,33,38]}
PPM=1280/27
# One canvas/root anchor for every animation, direction and pose. No alpha recentering.
W=int(os.environ.get('V126_CELL_WIDTH','160'));H=int(os.environ.get('V126_CELL_HEIGHT','224'));ANCHOR=(W/2,H/2+62)
s.render.resolution_x=W;s.render.resolution_y=H;s.render.resolution_percentage=100;s.render.pixel_aspect_x=1;s.render.pixel_aspect_y=1
cam.data.type='ORTHO';cam.data.shift_x=0;cam.data.shift_y=0;target=Vector((0,0,0));cam.location=target+Vector((0,-20,20*math.tan(math.radians(55))));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=max(W,H)/(2*PPM);bpy.context.view_layer.update()
def project(v):
 p=world_to_camera_view(s,cam,Vector(v));return [p.x*W,(1-p.y)*H]
p0=project((0,0,0));px=project((1,0,0));cam.data.ortho_scale*=(px[0]-p0[0])/(2*PPM);bpy.context.view_layer.update();p0=project((0,0,0));up=cam.rotation_euler.to_matrix()@Vector((0,1,0));cam.location+=up*((ANCHOR[1]-p0[1])/(2*PPM));bpy.context.view_layer.update();root=project((0,0,0))
assert abs(root[0]-ANCHOR[0])<.002 and abs(root[1]-ANCHOR[1])<.002
s.render.engine='CYCLES';s.cycles.samples=12;s.cycles.use_denoising=False;s.cycles.device='CPU';s.cycles.seed=126;s.render.threads_mode='FIXED';s.render.threads=8;s.render.film_transparent=True;s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA';s.render.image_settings.color_depth='8';s.render.fps=30;s.render.fps_base=1

def pose(state,frame,yaw):
 assembly.rotation_euler.z=math.radians(yaw)
 for a in arms:a.animation_data.action=bpy.data.actions[ACTIONS[state]]
 s.frame_set(math.floor(frame),subframe=frame-math.floor(frame));bpy.context.view_layer.update()

def bounds():
 dg=bpy.context.evaluated_depsgraph_get();mins=[];maxs=[]
 for o in char:
  ev=o.evaluated_get(dg);me=ev.to_mesh();raw=np.empty(len(me.vertices)*3,dtype=np.float64);me.vertices.foreach_get('co',raw);pts=raw.reshape((-1,3));mat=np.asarray(ev.matrix_world);world=pts@mat[:3,:3].T+mat[:3,3]
  x=root[0]+2*PPM*world[:,0];y=root[1]-2*PPM*(math.sin(math.radians(55))*world[:,1]+math.cos(math.radians(55))*world[:,2]);mins.append((float(x.min()),float(y.min())));maxs.append((float(x.max()),float(y.max())));ev.to_mesh_clear()
 return [min(x[0] for x in mins),min(x[1] for x in mins),max(x[0] for x in maxs),max(x[1] for x in maxs)]
mode=os.environ.get('V126_MODE','samples')
config={'cell_size':[W,H],'density':2,'display_cell_size':[W/2,H/2],'root_anchor_px':root,'fixed_ground_assembly_z':assembly.location.z,'camera_elevation_degrees':55,'horizontal_display_px_per_m':PPM,'depth_display_px_per_m':PPM*math.sin(math.radians(55)),'height_display_px_per_m':PPM*math.cos(math.radians(55)),'direction_order':[d for d,y in DIRECTIONS],'direction_yaw_degrees':dict(DIRECTIONS),'forward_local':[0,-1,0],'forward_screen_basis':'camera at -Y; screen X=worldX; screenY=-sin55*worldY-cos55*worldZ','actions':ACTIONS,'source_frames':SOURCE_FRAMES,'source_blend_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'samples_per_pixel':12,'ground_rendered':False,'shadow_contract':'body-only alpha; runtime draws independent foot-anchored shadow','attack_sampling_note':'f23->38 recovery-only slice. Nominal12fps source samples23,25.5,28,30.5,33,35.5; final sample is deliberately replaced by sourcef38 to retain neutral recovery endpoint. First5 unchanged; last interval is5source frames rather than2.5; endpoint is sampled2.5source frames later than the nominal last sample. Does not set release, damage or cooldown.'}
(P/'reports/render-config.json').write_text(json.dumps(config,indent=2))
rows=[]
if mode=='samples':
 for name,yaw in DIRECTIONS:
  pose('attack',23,yaw);b=bounds();file='samples/attack-start-'+name+'.png';s.render.filepath=str(P/file);bpy.ops.render.render(write_still=True);rows.append({'direction':name,'yaw':yaw,'state':'attack','source_frame':23,'geometry_bounds_px':b,'file':file});print('SAMPLE_DONE',name,b,flush=True)
 (P/'reports/sample-report.json').write_text(json.dumps(rows,indent=2))
elif mode=='bounds':
 # Finite preflight over only the256 final source poses, before any batch rendering.
 for state,frames in SOURCE_FRAMES.items():
  for name,yaw in DIRECTIONS:
   for i,fr in enumerate(frames):
    pose(state,fr,yaw);rows.append({'state':state,'direction':name,'index':i,'source_frame':fr,'geometry_bounds_px':bounds()})
 (P/'reports/bounds-preflight.json').write_text(json.dumps(rows,indent=2));print('BOUNDS_DONE',len(rows),flush=True)
elif mode=='batch':
 for state,frames in SOURCE_FRAMES.items():
  for name,yaw in DIRECTIONS:
   folder=P/'frames'/state/name;folder.mkdir(parents=True,exist_ok=True)
   for i,fr in enumerate(frames):
    pose(state,fr,yaw);file=f'frames/{state}/{name}/{i:02d}.png';s.render.filepath=str(P/file);bpy.ops.render.render(write_still=True);rows.append({'state':state,'direction':name,'index':i,'source_frame':fr,'file':file,'root_anchor_px':project((0,0,0))});print('FRAME_DONE',state,name,i,flush=True)
 (P/'reports/rendered-frames.json').write_text(json.dumps(rows,indent=2));print('BATCH_DONE',len(rows),flush=True)
else:raise RuntimeError('Unknown mode: '+mode)
