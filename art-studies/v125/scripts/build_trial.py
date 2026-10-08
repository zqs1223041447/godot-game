"""One bounded gait mixture; existing assets only. Original paths are read-only.
No IK, no retarget changes, no per-frame ground shift, no gameplay writes.
"""
import bpy, json, math, hashlib, os
from pathlib import Path
from mathutils import Matrix, Vector, Quaternion
from bpy_extras.object_utils import world_to_camera_view
import numpy as np
# Approved source scenes remain local and are not redistributed in this archive.
# An explicit external output directory prevents overwriting archived evidence.
required=('V125_BASE_BLEND','V125_JOG_BLEND','V125_OUTPUT_DIR')
missing=[name for name in required if not os.environ.get(name)]
if missing:raise RuntimeError('Set explicit local paths: '+', '.join(missing))
BASE=Path(os.environ['V125_BASE_BLEND']).expanduser().resolve()
JOG=Path(os.environ['V125_JOG_BLEND']).expanduser().resolve()
P=Path(os.environ['V125_OUTPUT_DIR']).expanduser().resolve()
ARCHIVE=Path(__file__).resolve().parents[1]
if P==ARCHIVE or ARCHIVE in P.parents:raise RuntimeError('Use an output directory outside the archive')
expected=json.loads((ARCHIVE/'reports/trial-metadata.json').read_text())['sources']
for path,key in [(BASE,'v123_blend_sha256'),(JOG,'v124_blend_sha256')]:
 if hashlib.sha256(path.read_bytes()).hexdigest()!=expected[key]:raise RuntimeError('Approved source-scene hash mismatch: '+path.name)
for rel in ['reports','frames/candidate']:(P/rel).mkdir(parents=True,exist_ok=True)
WALK_CENTER=(.15833333333333333+.3583333333333333)/2/(40/30)
JOG_CENTER=(.04166666595708756+.17499999701976776)/2/(28/30)
WEIGHT=.20
bpy.ops.wm.open_mainfile(filepath=str(BASE),load_ui=False)
s=bpy.context.scene
arms=[bpy.data.objects[n] for n in ['Armature','Armature.001','Armature.002']]
T=arms[0]; assembly=bpy.data.objects['Ranger_Sample_Assembly']
meshes=[o for o in bpy.data.objects if o.type=='MESH' and (o.parent in arms or o.name=='Skinned_Shoulder_Lining_Bridge')]
def signatures():
 out={}
 for o in meshes:
  out[o.name]=hashlib.sha256(json.dumps({'verts':[list(v.co) for v in o.data.vertices],'faces':[list(f.vertices) for f in o.data.polygons],'groups':[g.name for g in o.vertex_groups],'weights':[[(g.group,g.weight) for g in v.groups] for v in o.data.vertices],'uv':[[list(v.uv) for v in layer.data] for layer in o.data.uv_layers]},separators=(',',':')).encode()).hexdigest()
 for a in arms:
  out[a.name]=hashlib.sha256(json.dumps([[b.name,b.parent.name if b.parent else None,[list(r) for r in b.matrix_local]] for b in a.data.bones],separators=(',',':')).encode()).hexdigest()
 return out
def ahash(a):
 return hashlib.sha256(json.dumps([ [f.data_path,f.array_index,[(list(k.co),k.interpolation,list(k.handle_left),list(k.handle_right)) for k in f.keyframe_points]] for f in a.fcurves],separators=(',',':')).encode()).hexdigest()
baseline=signatures(); action_before={a.name:ahash(a) for a in bpy.data.actions}
with bpy.data.libraries.load(str(JOG),link=False) as (src,dst): dst.actions=['Probe_Retarget_Jog_Fwd_Loop']
walk=bpy.data.actions['Game_Walk_Loop'];jog=bpy.data.actions['Probe_Retarget_Jog_Fwd_Loop']
lookup={a.name:{(f.data_path,f.array_index):f for f in a.fcurves} for a in [walk,jog]}
for a in arms:
 a.animation_data_clear()
 for pb in a.pose.bones:pb.rotation_mode='QUATERNION';pb.matrix_basis=Matrix.Identity(4)
# Same fixed ground offset, only assembly heading changes for rightward projection.
original_heading=list(assembly.rotation_euler); assembly.rotation_euler.z=math.pi/2

def pose_values(action,phase):
 f=phase*(40 if action==walk else 28); fs=lookup[action.name];out={}
 for n in T.pose.bones.keys():
  path='pose.bones["'+n+'"]'
  q=Quaternion([fs[(path+'.rotation_quaternion',i)].evaluate(f) if (path+'.rotation_quaternion',i) in fs else float(i==0) for i in range(4)]).normalized()
  l=Vector([fs[(path+'.location',i)].evaluate(f) if (path+'.location',i) in fs else 0 for i in range(3)])
  out[n]={'q':q,'l':l}
 return out

def values(kind,p):
 w=pose_values(walk,(p+WALK_CENTER)%1)
 if kind=='walk':return w
 j=pose_values(jog,(p+JOG_CENTER)%1)
 if kind=='jog':return j
 return {n:{'q':w[n]['q'].slerp(j[n]['q'],WEIGHT).normalized(),'l':w[n]['l'].lerp(j[n]['l'],WEIGHT)} for n in w}

def setpose(kind,p):
 vals=values(kind,p)
 for a in arms:
  for n,pb in a.pose.bones.items():
   pb.matrix_basis=Matrix.Identity(4);pb.rotation_quaternion=vals[n]['q'];pb.location=vals[n]['l']
 bpy.context.view_layer.update()
 return vals
feet=bpy.data.objects['Female_Ranger_Feet'];sets={}
for side,sign in [('l',1),('r',-1)]:
 vs=[v for v in feet.data.vertices if v.co.x*sign>0];lo=min(v.co.z for v in vs);sole=[v for v in vs if v.co.z<lo+.015];ys=[v.co.y for v in sole]
 sets[side]={'all':[v.index for v in vs],'sole':[v.index for v in sole],'toe':[v.index for v in sole if v.co.y<min(ys)+.025],'heel':[v.index for v in sole if v.co.y>max(ys)-.025]}
# One continuous fixed-window sample pass only, not a parameter sweep.
rows=[];bone_error=0;root_error=0
for k in range(97):
 p=k/96;setpose('candidate',p);ev=feet.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();row={'phase':p,'feet':{}}
 for side,groups in sets.items():
  row['feet'][side]={}
  for group,ids in groups.items():
   pts=[ev.matrix_world@me.vertices[i].co for i in ids]
   row['feet'][side][group]={'minz':min(v.z for v in pts),'mean':list(sum(pts,Vector())/len(pts))}
 ev.to_mesh_clear();rows.append(row)
 bone_error=max(bone_error,max(abs((pb.tail-pb.head).length-pb.bone.length) for pb in T.pose.bones))
 root_error=max(root_error,T.pose.bones['root'].location.length)
fits={}
for side,center in [('l',0),('r',.5)]:
 chosen=[]
 for r in rows[:-1]:
  d=(r['phase']-center+.5)%1-.5
  if abs(d)<=.06+1e-8:chosen.append((d,r))
 chosen.sort(key=lambda x:x[0]);ph=np.array([d for d,r in chosen]);xyz=np.array([r['feet'][side]['toe']['mean'] for d,r in chosen]);coef=np.polyfit(ph,xyz[:,0],1);res=xyz[:,0]-np.polyval(coef,ph)
 fits[side]={'phase_center':center,'phase_relative_bounds':[float(ph[0]),float(ph[-1])],'phase_samples':[r['phase'] for d,r in chosen],'sample_count':len(chosen),'distance_per_cycle_m':float(-coef[0]),'fit_max_error_m':float(np.max(np.abs(res))),'fit_rms_m':float(np.sqrt(np.mean(res**2))),'lateral_span_m':float(np.ptp(xyz[:,1])),'toe_minz_range_m':[min(r['feet'][side]['toe']['minz'] for d,r in chosen),max(r['feet'][side]['toe']['minz'] for d,r in chosen)],'heel_minz_range_m':[min(r['feet'][side]['heel']['minz'] for d,r in chosen),max(r['feet'][side]['heel']['minz'] for d,r in chosen)]}
distance=sum(v['distance_per_cycle_m'] for v in fits.values())/2
ppm=1280/27;period=distance*ppm/156
for side,v in fits.items():
 ph=np.array([((p-v['phase_center']+.5)%1)-.5 for p in v['phase_samples']]); rr=[min(rows,key=lambda r:abs(r['phase']-p)) for p in v['phase_samples']];x=np.array([r['feet'][side]['toe']['mean'][0] for r in rr]);v['common_period_residual_span_display_px']=float(np.ptp(x+distance*ph))*ppm
lower=[min(r['feet'][side]['all']['minz'] for side in ['l','r']) for r in rows[:-1]]
ground={'fixed_assembly_z':assembly.location.z,'lower_boot_height_m':[min(lower),max(lower)],'max_penetration_m':max(0,-min(lower)),'max_both_feet_clearance_m':max(lower),'lower_boot_height_display_px':[min(lower)*ppm*math.cos(math.radians(55)),max(lower)*ppm*math.cos(math.radians(55))],'fraction_lower_boot_above_25mm':sum(v>.025 for v in lower)/len(lower)}
# Strict bounded-trial acceptance: actual penetration or lack of a near-ground support window rejects.
reasons=[]
if ground['max_penetration_m']>1e-5:reasons.append('Actual boot vertices penetrate the unchanged ground plane; no pose-dependent ground correction allowed.')
if any(v['toe_minz_range_m'][1]>.045 or v['toe_minz_range_m'][0]>.025 for v in fits.values()):reasons.append('The prespecified same-side window has no sufficiently near-ground forefoot support.')
if max(lower)>.05:reasons.append('Both boots rise more than 50mm above fixed ground, visibly floating for a walk-like default candidate.')
status='geometry_failed_visual_pending' if reasons else 'conditional_visual_candidate'
# Bake only the proposed mixture into an isolated working asset. Endpoint repeats phase0.
act=bpy.data.actions.new('Trial_Walk80_Jog20_Loop');act.use_fake_user=True
baked=[(p*30,values('candidate',p)) for p in [k/96 for k in range(97)]]
for n in T.pose.bones.keys():
 prev=None
 for fr,vals in baked:
  q=vals[n]['q']
  if prev is not None and q.dot(prev)<0:q.negate()
  prev=q.copy()
 for prop,key,count in [('rotation_quaternion','q',4),('location','l',3)]:
  if key=='l' and n!='pelvis':continue
  for i in range(count):
   fc=act.fcurves.new(data_path='pose.bones["'+n+'"].'+prop,index=i,action_group=n);fc.keyframe_points.add(len(baked))
   for kp,(fr,vals) in zip(fc.keyframe_points,baked):kp.co=(fr,vals[n][key][i]);kp.interpolation='LINEAR'
   fc.update()
assert signatures()==baseline
assert all(ahash(bpy.data.actions[n])==h for n,h in action_before.items())
# Small portrait cell; fix camera projection from the measured ppm, not alpha bounds.
cam=s.camera;cam.data.type='ORTHO';target=Vector((0,0,0));cam.location=target+Vector((0,-20,20*math.tan(math.radians(55))));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();s.render.resolution_x=128;s.render.resolution_y=192;s.render.resolution_percentage=100;cam.data.ortho_scale=192/(2*ppm);bpy.context.view_layer.update()
def project(v):
 q=world_to_camera_view(s,cam,Vector(v));return [q.x*128,(1-q.y)*192]
p0=project((0,0,0));px=project((1,0,0));measured=px[0]-p0[0]
cam.data.ortho_scale*=measured/(2*ppm)
bpy.context.view_layer.update()
# root ground is [64,158] px; pan camera in its image-up axis, no mesh re-grounding.
p0=project((0,0,0));up=cam.rotation_euler.to_matrix()@Vector((0,1,0));cam.location+=up*((158-p0[1])/(2*ppm));bpy.context.view_layer.update()
anchor=project((0,0,0));px=project((1,0,0));assert abs(px[0]-anchor[0]-2*ppm)<.001,(anchor,px)
render_meta={'resolution':[128,192],'density':2,'display_size':[64,96],'root_anchor_px':anchor,'heading_world_degrees':90,'direction':'screen_right','camera_elevation_degrees':55,'source_horizontal_pixels_per_m':ppm,'source_depth_pixels_per_m':ppm*math.sin(math.radians(55)),'source_height_pixels_per_m':ppm*math.cos(math.radians(55)),'root_anchor_policy':'Fixed projected ground origin; never track lowest alpha or posed feet.'}
counts={'candidate':16} # Archive scope: no additional baseline renders
periods={'candidate':period,'walk':1.1015521174702922*(40/30)*ppm/156,'jog':5.845505236772125*(28/30)*ppm/156}
variants={}
for kind,count in counts.items():
 phases=[i/count for i in range(count)]
 variants[kind]={'cycle_seconds':periods[kind],'frame_count':count,'phases':phases,'frames':['frames/'+kind+'/'+str(i).zfill(2)+'.png' for i in range(count)],'source_target_frames':[{'walk_frame':((p+WALK_CENTER)%1)*40,'jog_frame':((p+JOG_CENTER)%1)*28} for p in phases],'reference_quality':('full_trial' if kind=='candidate' else 'Sparse four-phase cadence reference; not fair smoothness comparison')}
metadata={'status':status,'rejection_reasons':reasons,'target_screen_speed_px_s':156,'game_move_world_s':240,'game_camera_zoom':.65,'blend':{'jog_weight':WEIGHT,'walk_weight':1-WEIGHT,'walk_phase_offset':WALK_CENTER,'jog_phase_offset':JOG_CENTER,'jog_relative_to_walk_phase_offset':JOG_CENTER-WALK_CENTER,'method':'Local quaternion slerp, normalized; local pelvis translation lerp; scales1 and root translation0. Same-side mid-support aligned. No IK or contact fix.'},'render':render_meta,'root_anchor_px':anchor,'variants':variants,'support_fit':{'basis':'Predeclared same-side mid-support phase +/-0.06; evaluated fixed forefoot vertices; world+X travel. No height/parameter search. Regress foot X on phase, then period = mean cycle distance*47.4074074/156. Diagnostic only, not authored root motion.','sides':fits,'cycle_distance_m':distance,'cycle_seconds':period},'ground':ground,'invariants':{'original_13_meshes_plus_shoulder_bridge_unchanged':True,'target_rest_and_weights_unchanged':True,'original_actions_unchanged':True,'maximum_bone_length_error_m':bone_error,'root_translation_error_m':root_error},'sources':{'v123_blend_sha256':hashlib.sha256(BASE.read_bytes()).hexdigest(),'v124_blend_sha256':hashlib.sha256(JOG.read_bytes()).hexdigest()},'no_gameplay_changes':True}
metadata['geometry_acceptance']='Zero-penetration criterion FAILED' if reasons else 'Conditional geometric trial; no perfect foot-lock guarantee'
metadata['visual_acceptance']='Selected static images inspected; dynamic and in-game behavior not accepted'
contact_frames=[]
for p in variants['candidate']['phases']:
 row=min(rows,key=lambda x:abs(x['phase']-p));item={'phase':p,'feet':{}}
 for side in ['l','r']:
  foot=row['feet'][side];x,y,z=foot['toe']['mean'];yp=render_meta['source_depth_pixels_per_m'];zp=render_meta['source_height_pixels_per_m']
  item['feet'][side]={'fixed_forefoot_mean_px':[anchor[0]+2*ppm*x,anchor[1]-2*(yp*y+zp*z)],'fixed_forefoot_ground_projection_px':[anchor[0]+2*ppm*x,anchor[1]-2*yp*y],'all_boot_minz_m':foot['all']['minz'],'toe_minz_m':foot['toe']['minz'],'within_fitted_support_window':abs((p-(0 if side=='l' else .5)+.5)%1-.5)<=.06}
 contact_frames.append(item)
metadata['contact_projection']={'coordinates':'128x192 render pixels; x right/y down. Forefoot marker is fixed toe vertex mean, ground marker same world x/y at z0. Neither is lowest-alpha anchor.','frames':contact_frames}
(P/'reports/trial-metadata.json').write_text(json.dumps(metadata,indent=2))
(P/'reports/contact-samples.json').write_text(json.dumps(rows,indent=2))
(P/'reports/invariants.json').write_text(json.dumps({'before':baseline,'after':signatures(),'original_action_hashes':action_before},indent=2))
print('TRIAL_SUMMARY',json.dumps({k:metadata[k] for k in ['status','rejection_reasons','blend','support_fit','ground','render']}),flush=True)
# Save isolated asset and restore no-source action identity changes.
setpose('candidate',0)
for a in arms:a.animation_data_create();a.animation_data.action=act
s.render.fps=30;s.frame_start=0;s.frame_end=30;s.frame_set(0)
s['trial_status']=status;s['trial_cycle_seconds']=period;bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(P/'ranger-locomotion-trial.blend'),compress=True)
for a in arms:a.animation_data_clear()
for o in bpy.data.objects:
 if o.type=='MESH':o.hide_render=o not in meshes
for o in meshes:o.hide_render=False;o.visible_camera=True
s.render.engine='CYCLES';s.cycles.samples=12;s.cycles.use_denoising=False;s.cycles.device='CPU';s.cycles.seed=125;s.render.threads_mode='FIXED';s.render.threads=8;s.render.film_transparent=True;s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA';s.render.image_settings.color_depth='8'
for kind,v in variants.items():
 for i,p in enumerate(v['phases']):
  setpose(kind,p);s.render.filepath=str(P/v['frames'][i]);bpy.ops.render.render(write_still=True);print('FRAME_DONE',kind,i,flush=True)
print('V125_RENDER_DONE',flush=True)
