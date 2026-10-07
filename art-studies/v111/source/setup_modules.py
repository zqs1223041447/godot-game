"""Create a local, isolated three-module source from the unchanged v108 authored assets."""
import bpy,bmesh,math,json,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
R=Path(__file__).resolve().parent.parent;V=R.parent/'v108-professional-environment';SRC=V/'sunlit-ruins-environment.blend'
bpy.ops.wm.open_mainfile(filepath=str(SRC));s=bpy.context.scene
specs=[('short_wall','Low west wall • vegetation-softened edge'),('walkable_arch','Hero arch • authored gate • worn crown'),('moss_rock','Scanned moss rock 01')]
keepers=[];defs=[]
for key,name in specs:
 o=bpy.data.objects[name];orig={'location':list(o.location),'rotation_euler':list(o.rotation_euler),'scale':list(o.scale),'matrix_world':[list(r) for r in o.matrix_world]}
 o.data=o.data.copy();o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4)
 vs=[v.co.copy() for v in o.data.vertices];zmin=min(v.z for v in vs);low=[v for v in vs if v.z<=zmin+.3];foot=Vector(((min(v.x for v in low)+max(v.x for v in low))/2,min(v.y for v in low),zmin))
 o.data.transform(Matrix.Translation(-foot));o.name=key;o['module_id']=key;o['source_object_name']=name;o['source_foot_world']=list(foot);o.is_holdout=False;o.hide_render=False;o.visible_camera=True
 keepers.append(o);parts=[o.name]
 if key=='walkable_arch':
  ids=json.load(open(V/'exports/collision-work/gate-threshold-polygon-indices.json'))['recommended_ground_layer_polygon_indices_union']
  sill=o.copy();sill.data=o.data.copy();s.collection.objects.link(sill);sill.name='walkable_arch_sill';sill['module_id']=key;sill['module_role']='walkable_ground_detail';keepers.append(sill);parts.append(sill.name)
  bm=bmesh.new();bm.from_mesh(sill.data);bm.faces.ensure_lookup_table();bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index not in ids],context='FACES');bm.to_mesh(sill.data);bm.free()
  bm=bmesh.new();bm.from_mesh(o.data);bm.faces.ensure_lookup_table();bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index in ids],context='FACES');bm.to_mesh(o.data);bm.free()
 defs.append({'id':key,'source_object_name':name,'source_scene_transform':orig,'source_foot_world_metres':list(foot),'normalization_translation_metres':list(-foot),'source_transform_baked':True,'parts':parts,'module_foot_local_metres':[0,0,0],'source_asset':o.get('source_asset'),'collision_basis':'flat receiving ground z=0; module geometry foot is exactly zero','pixel_density':{'x':1280/27,'ground_y':1280/27*math.sin(math.radians(55)),'height_z':1280/27*math.cos(math.radians(55))}})
terrain=bpy.data.objects.get('Terrain • soil / grass / gravel + local old path');terrain.name='assembly_ground';terrain.data=terrain.data.copy()
for v in terrain.data.vertices:v.co.z=0
keepers.append(terrain)
lights=[o for o in s.objects if o.type=='LIGHT'];keepers+=lights
cam=s.camera;cam.location=(0,-20,20*math.tan(math.radians(55)));cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=27;keepers.append(cam)
for o in list(s.objects):
 if o not in keepers:bpy.data.objects.remove(o,do_unlink=True)
# Neutral physical receiver. It contributes diffuse bounce, never ground-color pixels to sprite outputs.
bpy.ops.mesh.primitive_plane_add(size=80,location=(0,0,-.001));receiver=bpy.context.object;receiver.name='neutral_shadow_receiver';receiver.is_shadow_catcher=True
m=bpy.data.materials.new('neutral_receiver_material');m.use_nodes=True;bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.32,.32,.32,1);bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0;receiver.data.materials.append(m)
s.render.engine='CYCLES';s.cycles.device='CPU';s.render.threads_mode='FIXED';s.render.threads=4;s.cycles.samples=192;s.cycles.use_denoising=False;s.cycles.use_adaptive_sampling=True;s.cycles.adaptive_threshold=.015;s.cycles.seed=111
s.render.resolution_x=1280;s.render.resolution_y=720;s.render.resolution_percentage=100;s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA';s.render.film_transparent=True;s.render.use_border=False
for o in keepers:
 if o.type=='MESH':o.hide_render=o.name!='short_wall'
terrain.hide_render=True
s.view_layers[0].cycles.use_pass_shadow_catcher=False
s['module_library_note']='Three isolated CC0-derived modules. No neighbor or old scene occlusion retained. Fixed 55-degree camera and sun.'
s['source_scene_sha256']=hashlib.sha256(SRC.read_bytes()).hexdigest()
# Remove unused original materials and images before making the derivative self-contained.
bpy.ops.outliner.orphans_purge(do_recursive=True);bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(R/'source/modules.blend'),compress=True)
doc={'source_scene':str(SRC),'source_scene_sha256':s['source_scene_sha256'],'resolution':[1280,720],'camera_target_metres':[0,0,0],'camera_elevation_degrees':55,'ortho_width_metres':27,'full_frame_foot_pixel':[640,360],'original_lights':[{'name':o.name,'type':o.data.type,'location':list(o.location),'rotation':list(o.rotation_euler),'energy':o.data.energy,'color':list(o.data.color)} for o in lights],'modules':defs}
(R/'source/module-definitions.json').write_text(json.dumps(doc,indent=2))
# A bounded wall-only technical shadow-catcher probe, not a second asset variant.
o=bpy.data.objects['short_wall'];o.visible_camera=False;s.cycles.samples=64;s.render.use_border=True;s.render.use_crop_to_border=True;s.render.border_min_x=420/1280;s.render.border_max_x=970/1280;s.render.border_min_y=1-470/720;s.render.border_max_y=1-180/720;s.render.filepath=str(R/'qa/shadow-catcher-probe.png');bpy.ops.render.render(write_still=True)
print('MODULE_SOURCE_READY',flush=True)
