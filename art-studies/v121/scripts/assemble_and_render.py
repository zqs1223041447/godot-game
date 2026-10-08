"""Isolated Female Ranger sample. Run with Blender --disable-autoexec.
Loads only glTF data and our locally inspected environment settings; package code is never run.
Preserves each skin/armature binding and authors one static pose, explicitly not an animation.
"""
import bpy,bmesh,json,math,hashlib,sys
from pathlib import Path
from mathutils import Vector,Matrix
from bpy_extras.object_utils import world_to_camera_view
ROOT=Path(__file__).resolve().parents[1]
M=json.loads((ROOT/'reports/source-manifest.json').read_text())
E=json.loads((ROOT/'reports/environment-settings.json').read_text())
bpy.ops.wm.read_factory_settings(use_empty=True)
s=bpy.context.scene
s.render.fps=24
assets={}
for name in ['Female_Ranger','Superhero_Female_FullBody','Hair_BuzzedFemale','Female_Peasant_Body']:
 before=set(bpy.data.objects)
 bpy.ops.import_scene.gltf(filepath=M['asset_paths'][name],bone_heuristic='BLENDER')
 obs=list(set(bpy.data.objects)-before)
 # glTF importer creates unlinked bone-shape icospheres. They are not character geometry.
 assets[name]={'armature':next(o for o in obs if o.type=='ARMATURE'),'meshes':[o for o in obs if o.type=='MESH' and o.parent is not None and o.parent.type=='ARMATURE']}
 for o in obs:
  if o.type=='MESH' and o.parent is None:bpy.data.objects.remove(o,do_unlink=True)
ranger=assets['Female_Ranger'];base=assets['Superhero_Female_FullBody'];hair=assets['Hair_BuzzedFemale'];motion=assets['Female_Peasant_Body']
# Check imported rest bones BEFORE any animation reuse, including Blender's generated bone orientation.
def max_matrix_delta(a,b):return max(abs(a[i][j]-b[i][j]) for i in range(4) for j in range(4))
rig=ranger['armature'];rig_checks={}
for key,data in assets.items():
 other=data['armature']; assert set(rig.data.bones.keys())==set(other.data.bones.keys())
 err=max(max_matrix_delta(b.matrix_local,other.data.bones[b.name].matrix_local) for b in rig.data.bones)
 rig_checks[key]={'bones':len(other.data.bones),'maximum_rest_matrix_error':err}
 assert err<1e-5,(key,err)
# Keep intact head/neck index-connected components, rather than cutting through weighted triangles.
body=next(o for o in base['meshes'] if o.name=='Superhero_Female')
mesh=body.data;adj=[[] for _ in mesh.vertices]
for edge in mesh.edges:
 a,b=edge.vertices;adj[a].append(b);adj[b].append(a)
seen=set();components=[];keep=set()
for idx in range(len(mesh.vertices)):
 if idx in seen:continue
 stack=[idx];seen.add(idx);comp=[]
 while stack:
  v=stack.pop();comp.append(v)
  for n in adj[v]:
   if n not in seen:seen.add(n);stack.append(n)
 lo=min(mesh.vertices[v].co.z for v in comp);hi=max(mesh.vertices[v].co.z for v in comp)
 selected=lo>1.46
 components.append({'vertices':len(comp),'min_z':lo,'max_z':hi,'kept':selected})
 if selected:keep.update(comp)
original_counts={'vertices':len(mesh.vertices),'faces':len(mesh.polygons)}
bm=bmesh.new();bm.from_mesh(mesh);bm.verts.ensure_lookup_table();bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.index not in keep],context='VERTS');bm.to_mesh(mesh);bm.free();mesh.update();body.name='Female_Base_Head_Neck_Only'
assert len(mesh.vertices)==1715,len(mesh.vertices)
assert len(ranger['meshes'])==9 and len(base['meshes'])==3 and len(hair['meshes'])==1
head_counts={'vertices':len(mesh.vertices),'faces':len(mesh.polygons),'min_z':min(v.co.z for v in mesh.vertices),'max_z':max(v.co.z for v in mesh.vertices)}
# Keep all rigged hair vertices initially; a short scalp fits entirely beneath the hood exterior.
character_meshes=ranger['meshes']+base['meshes']+hair['meshes']
# Material parameter-only correction. Color textures, normals, UVs and ORM remain intact.
mat=bpy.data.materials['MI_Ranger'];nt=mat.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
base_input=bs.inputs['Base Color'];link=next(l for l in nt.links if l.to_socket==base_input);source=link.from_socket;nt.links.remove(link)
hue=nt.nodes.new('ShaderNodeHueSaturation');hue.name='Sample restrained olive palette';hue.label='Texture-preserving saturation 0.78';hue.inputs['Hue'].default_value=.49;hue.inputs['Saturation'].default_value=.78;hue.inputs['Value'].default_value=1.0;nt.links.new(source,hue.inputs['Color'])
tint=nt.nodes.new('ShaderNodeMixRGB');tint.name='Sample warm leather / subdued metal';tint.blend_type='MULTIPLY';tint.inputs[0].default_value=1;tint.inputs[2].default_value=(1.0,.97,.86,1);nt.links.new(hue.outputs['Color'],tint.inputs[1]);nt.links.new(tint.outputs[0],base_input)
# Material roughness keeps the original map with a modest floor. Avoid polished sci-fi metal.
rough_input=bs.inputs['Roughness'];rough_link=next((l for l in nt.links if l.to_socket==rough_input),None)
if rough_link:
 rough_source=rough_link.from_socket;nt.links.remove(rough_link);floor=nt.nodes.new('ShaderNodeMath');floor.operation='MAXIMUM';floor.inputs[1].default_value=.42;nt.links.new(rough_source,floor.inputs[0]);nt.links.new(floor.outputs[0],rough_input)
bs.inputs['Specular IOR Level'].default_value=.35
# One parent controls a uniform stature normalization. Original rest transforms/skin weights stay intact.
assembly=bpy.data.objects.new('Ranger_Sample_Assembly',None);s.collection.objects.link(assembly)
rest_min=min((o.matrix_world@v.co).z for o in character_meshes for v in o.data.vertices)
rest_max=max((o.matrix_world@v.co).z for o in character_meshes for v in o.data.vertices)
scale=1.8/(rest_max-rest_min);assembly.scale=(scale,)*3;assembly.rotation_euler.z=math.radians(-23)
for key in ['Female_Ranger','Superhero_Female_FullBody','Hair_BuzzedFemale']:
 assets[key]['armature'].parent=assembly
# The packaged clip is mislabeled: all 195 source channels repeat a constant T-pose.
# Retain it for inspection only. Do not call it working animation or recover nonexistent motion.
act=motion['armature'].animation_data.action;act.name='Source_Constant_TPose_Named_Jog_Fwd_Loop';act.use_fake_user=True
for key in ['Female_Ranger','Superhero_Female_FullBody','Hair_BuzzedFemale']:
 arm=assets[key]['armature'];arm.animation_data_clear()
 for bone in arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
for o in motion['meshes']+[motion['armature']]:bpy.data.objects.remove(o,do_unlink=True)
def evaluated_vertices():
 dg=bpy.context.evaluated_depsgraph_get();allv=[]
 for o in character_meshes:
  ev=o.evaluated_get(dg);m=ev.to_mesh();allv.extend(ev.matrix_world@v.co for v in m.vertices);ev.to_mesh_clear()
 return allv
bpy.context.view_layer.update();rest_vertices=evaluated_vertices()
# Author one clearly labeled static ready pose. Bone rotations only; no rebinding or weight changes.
# Rotations are expressed in armature-space axes, with parent updates before the next local edit.
def turn(bone_name,axis,degrees):
 pb=rig.pose.bones[bone_name];head=pb.head.copy()
 pb.matrix=Matrix.Translation(head) @ Matrix.Rotation(math.radians(degrees),4,axis) @ Matrix.Translation(-head) @ pb.matrix
 bpy.context.view_layer.update()
turn('spine_03','Z',-4)
turn('upperarm_l','Y',64)
turn('upperarm_l','X',-6)
turn('lowerarm_l','X',-26)
turn('upperarm_r','Y',-76)
turn('lowerarm_r','X',-12)
turn('Head','Z',7)
# Copy exactly the authored local basis transforms onto the already identical head/hair skeletons.
for key in ['Superhero_Female_FullBody','Hair_BuzzedFemale']:
 for pb in assets[key]['armature'].pose.bones:pb.matrix_basis=rig.pose.bones[pb.name].matrix_basis.copy()
bpy.context.view_layer.update()
POSE_FRAME=1;s.frame_set(POSE_FRAME);vv=evaluated_vertices();assembly.location.z=-min(v.z for v in vv);bpy.context.view_layer.update();vv=evaluated_vertices()
pose_min=[min(v[i] for v in vv) for i in range(3)];pose_max=[max(v[i] for v in vv) for i in range(3)]
pose_error=max(max_matrix_delta(rig.pose.bones[b.name].matrix,base['armature'].pose.bones[b.name].matrix) for b in rig.data.bones)
vertex_displacement=max((a-b).length for a,b in zip(vv,rest_vertices))
assert pose_error<1e-5 and vertex_displacement>.4,(pose_error,vertex_displacement)
frames=[]
# Match the frozen environment's lighting and color settings exactly.
world=bpy.data.worlds.new('Matched cool open-sky fill');world.use_nodes=True;bg=world.node_tree.nodes.get('Background');envbg=next(n for n in E['world']['nodes'] if n['type']=='BACKGROUND');bg.inputs['Color'].default_value=envbg['inputs']['Color'];bg.inputs['Strength'].default_value=envbg['inputs']['Strength'];s.world=world
for l in E['lights']:
 data=bpy.data.lights.new(l['name'],l['type']);data.energy=l['energy'];data.color=l['color']
 if l['type']=='SUN':data.angle=l['angle']
 if l['type']=='AREA':data.size=l['size']
 o=bpy.data.objects.new(l['name'],data);s.collection.objects.link(o);o.location=l['location'];o.rotation_euler=l['rotation_euler']
for k,v in E['color'].items():setattr(s.view_settings,k,v)
# Neutral, matte actual ground for the quality close-up.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.001));ground=bpy.context.object;ground.name='Sample Neutral Ground'
gmat=bpy.data.materials.new('Muted stone neutral backdrop');gmat.use_nodes=True;gbs=gmat.node_tree.nodes.get('Principled BSDF');gbs.inputs['Base Color'].default_value=(.115,.125,.10,1);gbs.inputs['Roughness'].default_value=1;gbs.inputs['Specular IOR Level'].default_value=.15;ground.data.materials.append(gmat)
cdata=bpy.data.cameras.new('Matched 55 degree orthographic');cam=bpy.data.objects.new('Matched 55 degree orthographic',cdata);s.collection.objects.link(cam);cdata.type='ORTHO';s.camera=cam
def camera(target,width,W,H):
 target=Vector(target);cam.location=target+Vector((0,-20,20*math.tan(math.radians(55))));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cdata.ortho_scale=width;s.render.resolution_x=W;s.render.resolution_y=H;s.render.resolution_percentage=100;bpy.context.view_layer.update()
s.render.engine='CYCLES';s.cycles.device='CPU';s.render.threads_mode='FIXED';s.render.threads=8;s.cycles.samples=192;s.cycles.use_denoising=False;s.cycles.use_adaptive_sampling=True;s.cycles.adaptive_threshold=.025;s.cycles.seed=121;s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA';s.render.image_settings.color_depth='8';s.render.film_transparent=True
s.render.use_file_extension=True
# Foot-relative projected bounds are the authoritative actual silhouette dimensions at the environment scale.
camera((0,0,0),27,1280,720)
proj=[world_to_camera_view(s,cam,v) for v in vv]
projected_bounds={'min_x':min(p.x for p in proj)*1280,'max_x':max(p.x for p in proj)*1280,'min_y':(1-max(p.y for p in proj))*720,'max_y':(1-min(p.y for p in proj))*720}
projected_bounds['width']=projected_bounds['max_x']-projected_bounds['min_x'];projected_bounds['height']=projected_bounds['max_y']-projected_bounds['min_y']
report={'sample':'Female Ranger / authored static ready pose','scope':'Isolated art study only; no production game modifications, no eight-direction batch, not a complete animation set','source_manifest':'source-manifest.json','original_package_sha256':M['archives'],'uri_repairs':M['uri_repairs'],'rig_checks':rig_checks,'base_body_original':original_counts,'head_neck_retained':head_counts,'base_components':components,'hair':'Hair_BuzzedFemale under hood; no long hair','binding_changes':False,'material_adjustment':{'color_texture_preserved':True,'normal_texture_preserved':True,'ORM_texture_preserved':True,'hue':.49,'saturation':.78,'linear_multiply':[1,.97,.86],'roughness_floor':.42,'specular_ior_level':.35},'rest_stature_metres':1.8,'raw_rest_height':rest_max-rest_min,'uniform_assembly_scale':scale,'character_heading_degrees':-23,'pose':{'action':None,'frame':POSE_FRAME,'render_label':'authored static ready pose; no motion clip','source_clip_problem':'Jog_Fwd_Loop has 195 constant channels over 29 samples; it is a repeated T-pose','maximum_vertex_displacement_from_rest_m':vertex_displacement,'head_ranger_pose_matrix_error':pose_error,'ground_offset':assembly.location.z,'min':pose_min,'max':pose_max},'full_loop_numeric_checks':frames,'projection':{'camera_elevation_degrees':55,'source_resolution':[1280,720],'orthographic_width_metres':27,'x_pixels_per_m':1280/27,'y_pixels_per_m':1280/27*math.sin(math.radians(55)),'z_pixels_per_m':1280/27*math.cos(math.radians(55)),'vertical_1_8m_reference_pixels':1.8*1280/27*math.cos(math.radians(55)),'projected_geometry_bounds':projected_bounds},'environment_settings':E,'limits':['The included 1.1667-second Jog clip contains no changing channel values. This sample uses an authored static ready pose, not idle or walking animation; no weapon or magic effect is delivered.','Retained neck and hood need visual checks at the chosen pose; no automatic mesh-intersection clearance certificate is claimed.','Nominal 49 pixels is a vertical 1.8m reference; posed silhouette also reflects depth and limb motion.','The old 53-DEF UAL was not used.']}
(ROOT/'reports/assembly-report.json').write_text(json.dumps(report,indent=2))
# Save the assembled asset with packed textures and the camera set to the original environment scale.
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'ranger-sample.blend'),compress=True)
if '--assemble-only' in sys.argv:
 print('ASSEMBLY_ONLY_COMPLETE',flush=True)
 sys.exit(0)
# Quality view: the same camera elevation and lighting at a larger magnification, never a different perspective.
center=Vector(((pose_min[0]+pose_max[0])/2,(pose_min[1]+pose_max[1])/2,(pose_min[2]+pose_max[2])/2))
camera(center,2.10,1200,1200);ground.is_shadow_catcher=False;s.render.film_transparent=False;s.render.filepath=str(ROOT/'renders/ranger-quality.png');bpy.ops.render.render(write_still=True)
print('QUALITY_RENDER_READY',flush=True)
# Actual-size body and independent transparent cast-shadow pass, at original source pixel density.
camera((0,0,0),27,1280,720);s.render.film_transparent=True;ground.hide_render=True;s.cycles.samples=96;s.cycles.use_denoising=False;s.render.filepath=str(ROOT/'renders/ranger-actual-body.png');bpy.ops.render.render(write_still=True)
ground.hide_render=False;ground.is_shadow_catcher=True
for o in character_meshes:o.visible_camera=False
s.cycles.samples=128;s.render.filepath=str(ROOT/'renders/ranger-actual-shadow-raw.png');bpy.ops.render.render(write_still=True)
print('SAMPLE_RENDER_COMPLETE',flush=True)
