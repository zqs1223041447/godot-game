"""Render three isolated module sprites and their independent flat-ground shadow decals."""
import bpy,math,json,struct
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
R=Path(__file__).resolve().parent.parent;D=json.load(open(R/'source/module-definitions.json'))
bpy.ops.wm.open_mainfile(filepath=str(R/'source/modules.blend'));s=bpy.context.scene;W,H=1280,720;s.render.threads_mode='FIXED';s.render.threads=4;s.cycles.samples=192;s.cycles.use_denoising=False;s.cycles.seed=111
receiver=bpy.data.objects['neutral_shadow_receiver'];ground=bpy.data.objects['assembly_ground'];ground.hide_render=True
allparts=[bpy.data.objects[n] for m in D['modules'] for n in m['parts']]
s.use_nodes=True;nt=s.node_tree;nt.nodes.clear();rl=nt.nodes.new('CompositorNodeRLayers');comp=nt.nodes.new('CompositorNodeComposite');nt.links.new(rl.outputs['Image'],comp.inputs['Image'])
# A bounded 0.8% alpha floor removes shadow-catcher numerical haze in unshadowed regions.
sub=nt.nodes.new('CompositorNodeMath');sub.operation='SUBTRACT';sub.inputs[1].default_value=.008;sub.use_clamp=True;nt.links.new(rl.outputs['Alpha'],sub.inputs[0]);div=nt.nodes.new('CompositorNodeMath');div.operation='DIVIDE';div.inputs[1].default_value=.992;div.use_clamp=True;nt.links.new(sub.outputs[0],div.inputs[0]);seta=nt.nodes.new('CompositorNodeSetAlpha');seta.mode='REPLACE_ALPHA';seta.inputs['Image'].default_value=(0,0,0,1);nt.links.new(div.outputs[0],seta.inputs['Alpha'])
sun=next(o for o in s.objects if o.type=='LIGHT' and o.data.type=='SUN');ray=sun.matrix_world.to_3x3()@Vector((0,0,-1));assert ray.z<0
f32=lambda x:struct.unpack('f',struct.pack('f',x))[0]
def pix(v):
 q=world_to_camera_view(s,s.camera,v);return [q.x*W,(1-q.y)*H]
def box_for(vs,pad):
 ps=[pix(v) for v in vs];return [max(0,math.floor(min(p[0] for p in ps))-pad),max(0,math.floor(min(p[1] for p in ps))-pad),min(W,math.ceil(max(p[0] for p in ps))+pad),min(H,math.ceil(max(p[1] for p in ps))+pad)]
def crop(box):
 s.render.use_border=True;s.render.use_crop_to_border=True;s.render.border_min_x=box[0]/W;s.render.border_max_x=box[2]/W;s.render.border_min_y=1-box[3]/H;s.render.border_max_y=1-box[1]/H
 return [int(f32(s.render.border_min_x*W)),H-int(f32(s.render.border_max_y*H)),int(f32(s.render.border_max_x*W)),H-int(f32(s.render.border_min_y*H))]
def render(path,box,shadow=False):
 eff=crop(box)
 for l in list(comp.inputs['Image'].links):nt.links.remove(l)
 nt.links.new(seta.outputs['Image'] if shadow else rl.outputs['Image'],comp.inputs['Image'])
 s.render.filepath=str(R/path);bpy.ops.render.render(write_still=True)
 return {'image':path,'source_pixel_rect':{'x':eff[0],'y':eff[1],'width':eff[2]-eff[0],'height':eff[3]-eff[1]},'foot_source_pixel':[640,360],'foot_local_pixel':[640-eff[0],360-eff[1]],'sprite_centered':False,'source_pixels_per_metre_x':W/27}
records=[]
for m in D['modules']:
 key=m['id'];obs=[bpy.data.objects[n] for n in m['parts']]
 for o in allparts:o.hide_render=o not in obs;o.visible_camera=True;o.is_holdout=False
 receiver.hide_render=False;receiver.visible_camera=False;receiver.is_shadow_catcher=False
 # Only the target module and its neutral invisible bounce receiver exist for rays.
 main=obs[0];mainverts=[main.matrix_world@v.co for v in main.data.vertices]
 if len(obs)>1:obs[1].visible_camera=False
 sprite=render(f'exports/{key}.png',box_for(mainverts,5))
 rec={**m,'sprite':sprite,'parts_rendered_together':m['parts'],'neighbor_objects_in_render':[],'old_terrain_in_render':False}
 if len(obs)>1:
  main.visible_camera=True;main.is_holdout=True;obs[1].visible_camera=True
  sillverts=[obs[1].matrix_world@v.co for v in obs[1].data.vertices]
  rec['ground_detail']=render(f'exports/{key}_sill.png',box_for(sillverts,5))
  main.is_holdout=False
 # Independent shadow projection on a flat neutral shadow-catcher, with all module parts casting.
 for o in obs:o.visible_camera=False;o.is_holdout=False
 receiver.visible_camera=True;receiver.is_shadow_catcher=True;s.view_layers[0].cycles.use_pass_shadow_catcher=False
 vs=[o.matrix_world@v.co for o in obs for v in o.data.vertices];projected=[v-ray*(v.z/ray.z) for v in vs];groundfoot=[Vector((v.x,v.y,0)) for v in vs]
 rec['shadow']=render(f'exports/{key}_shadow.png',box_for(projected+groundfoot,60),True)
 rec['shadow'].update({'blend':'straight-alpha neutral black source-over','ground_receiver_z_metres':0,'sun_ray_direction':list(ray),'alpha_floor_removed':.008,'dynamic_lighting':False,'method':'Cycles native simple shadow catcher approximation, target module only, zero RGB, no ground texture; alpha remapped max(0,(a-0.008)/0.992)'})
 records.append(rec);(R/'exports/modules-manifest.partial.json').write_text(json.dumps({'modules':records},indent=2))
# An actual ground-only render provides a texture-varying assembly check background. It has no prop shadows.
for o in allparts:o.hide_render=True
receiver.hide_render=True;ground.hide_render=False;s.render.use_border=False;s.render.use_crop_to_border=False;s.render.film_transparent=False
for l in list(comp.inputs['Image'].links):nt.links.remove(l)
nt.links.new(rl.outputs['Image'],comp.inputs['Image']);s.render.filepath=str(R/'qa/assembly-ground.png');bpy.ops.render.render(write_still=True)
manifest={'schema':'three-independent-environment-modules-v1','resolution':[W,H],'camera_elevation_degrees':55,'orthographic_width_metres':27,'module_foot_source_pixel':[640,360],'projection':{'source_pixel_per_ground_m_x':W/27,'source_pixel_per_ground_m_y':W/27*math.sin(math.radians(55)),'source_pixel_per_height_m_z':W/27*math.cos(math.radians(55)),'module_to_source_pixel':'[640 + 47.4074074074*x, 360 - 38.833874692219*y - 27.191771797383*z]','camera2d_zoom':.65,'godot_world_per_m_x':72.9344729345,'godot_world_per_ground_m_y':-59.7444226034,'godot_world_per_height_m_z':-41.8334950729},'modules':records,'render':{'engine':'Blender 4.3.2 Cycles CPU','threads':4,'samples_max':192,'denoising':False,'view_transform':'Original v108 AgX, original exposure and original sun/fill lights'},'source_scene_sha256':D['source_scene_sha256'],'reuse_scope':'XY translation at fixed scale and orientation on a flat receiving ground. Three authored modules only.','limits':['Sun direction, material lighting and self-shadow are baked, not dynamic.','Shadow decals have no baked neighboring object or ground base color, but assume a flat horizontal receiver.','Simple neutral shadow catcher omits colored indirect-light changes and is not a physically exact relight on every new ground.','Independently overlaid shadows may over-darken overlapping regions; no object-to-object cast shadow is generated.','Do not rotate, mirror, change elevation or place on sloped ground without re-rendering.','Arch threshold is a separate module-internal ground detail; always keep it with the arch.']}
(R/'exports/manifest.json').write_text(json.dumps(manifest,indent=2));print('ALL_MODULE_EXPORTS_COMPLETE',flush=True)
