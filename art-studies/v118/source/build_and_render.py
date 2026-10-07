"""One approved, bounded batch: low fern and a three-pebble ground decoration.

Reads the frozen packed v108 source. Never writes v108/v111 and never downloads.
Usage: blender --background --disable-autoexec --threads 4 --python this_file.py
"""
import bpy
import hashlib
import json
import math
import struct
from pathlib import Path
from mathutils import Vector, Matrix
from bpy_extras.object_utils import world_to_camera_view

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT.parent / 'v108-professional-environment/sunlit-ruins-environment.blend'
MANIFEST_V111 = ROOT.parent / 'v111-modular-environment/exports/manifest.json'
if (ROOT / 'source/BATCH_COMPLETE.json').exists():
    raise RuntimeError('The approved render batch already completed. Do not silently rerender.')
for folder in ('exports', 'qa', 'source/raw-renders'):
    (ROOT / folder).mkdir(exist_ok=True, parents=True)

source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
v111_hash = hashlib.sha256(MANIFEST_V111.read_bytes()).hexdigest()
reference = json.loads(MANIFEST_V111.read_text())
assert source_hash == reference['source_scene_sha256']
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
s = bpy.context.scene
lights = [o for o in s.objects if o.type == 'LIGHT']
cam = s.camera
cam.location = (0, -20, 20 * math.tan(math.radians(55)))
cam.rotation_euler = (Vector((0,0,0))-cam.location).to_track_quat('-Z','Y').to_euler()
cam.data.ortho_scale = 27
W,H = 1280,720
PX = W/27
PY = PX*math.sin(math.radians(55))
PZ = PX*math.cos(math.radians(55))

def hull(raw):
    pts = sorted(set((float(p[0]), float(p[1])) for p in raw))
    def cross(o,a,b):
        return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
    lo,hi=[],[]
    for p in pts:
        while len(lo)>1 and cross(lo[-2],lo[-1],p)<=0: lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi)>1 and cross(hi[-2],hi[-1],p)<=0: hi.pop()
        hi.append(p)
    return lo[:-1]+hi[:-1]

def part(source_name, name, scale, location=(0,0,0), yaw=0):
    src=bpy.data.objects[source_name]
    ob=bpy.data.objects.new(name,src.data.copy())
    s.collection.objects.link(ob)
    transform=Matrix.Translation(Vector(location)) @ Matrix.Rotation(math.radians(yaw),4,'Z') @ Matrix.Diagonal((scale,scale,scale,1))
    ob.data.transform(transform)
    ob.matrix_world=Matrix.Identity(4)
    ob['source_asset']=src.get('source_asset')
    ob['license']='CC0 1.0'
    record={'source_object':source_name,'source_asset':src.get('source_asset'),
            'source_mesh':src.data.name,'source_scene_matrix_world':[list(row) for row in src.matrix_world],
            'source_native_mesh_scale':scale,'fixed_baked_yaw_degrees':yaw,
            'authored_part_translation_metres':list(location),
            'triangle_count':sum(len(p.vertices)-2 for p in ob.data.polygons)}
    return ob,record

fern,fern_rec=part('Fern cluster 01 / 04','fern_low',1.10)
stone_a,rec_a=part('Loose scanned rubble 02','pebble_trio_a',0.12/1.0996944904327393,(-.22,.04,0))
stone_b,rec_b=part('Loose scanned rubble 04','pebble_trio_b',0.09/1.2054507732391357,(.24,.075,0))
stone_c,rec_c=part('Loose scanned rubble 02','pebble_trio_c',0.08/1.0996944904327393,(.015,-.11,0),22)
groups=[('fern_low',[fern],[fern_rec]),('pebble_trio',[stone_a,stone_b,stone_c],[rec_a,rec_b,rec_c])]
allparts=[o for _,obs,_ in groups for o in obs]
defs=[]
for key,obs,records in groups:
    vs=[v.co.copy() for o in obs for v in o.data.vertices]
    zmin=min(v.z for v in vs)
    low=[v for v in vs if v.z <= zmin+.30]
    foot=Vector(((min(v.x for v in low)+max(v.x for v in low))/2,min(v.y for v in low),zmin))
    for o in obs:
        o.data.transform(Matrix.Translation(-foot))
        o.hide_render=True
        o.visible_camera=True
        o.is_holdout=False
    vs=[v.co.copy() for o in obs for v in o.data.vertices]
    bounds=[[min(v[i] for v in vs),max(v[i] for v in vs)] for i in range(3)]
    outline=hull(vs)
    defs.append({'id':key,'parts':[o.name for o in obs],'source_parts':records,
        'normalization_translation_metres':list(-foot),'module_foot_local_metres':[0,0,0],
        'foot_definition':'Same as v111: low vertices <= minimum z+0.30m; midpoint x, minimum y, minimum z',
        'geometry_bounds_metres':bounds,'geometry_dimensions_metres':[b-a for a,b in bounds],
        'visual_placement_hull_ground_xy_metres':outline,
        'visual_placement_hull_foot_relative_screen_pixel':[[PX*x,-PY*y] for x,y in outline],
        'boundary_purpose':'Conservative placement-only mesh envelope. Not collision and not the alpha silhouette.',
        'render_layer':'ground_decoration_below_actors_enemies_and_drops','collision':None,
        'blocks_movement':False,'runtime_rotation_allowed':False})

keepers=set(allparts+lights+[cam])
for o in list(s.objects):
    if o not in keepers:
        bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.mesh.primitive_plane_add(size=80,location=(0,0,-.001))
receiver=bpy.context.object
receiver.name='neutral_shadow_receiver'
mat=bpy.data.materials.new('neutral_receiver_material')
mat.use_nodes=True
bs=mat.node_tree.nodes.get('Principled BSDF')
bs.inputs['Base Color'].default_value=(.32,.32,.32,1)
bs.inputs['Roughness'].default_value=1
bs.inputs['Specular IOR Level'].default_value=0
receiver.data.materials.append(mat)
receiver.hide_render=True
s.render.engine='CYCLES'
s.cycles.device='CPU'
s.cycles.samples=256
s.cycles.use_denoising=False
s.cycles.use_adaptive_sampling=True
s.cycles.adaptive_threshold=.01
s.cycles.seed=118
s.render.threads_mode='FIXED'
s.render.threads=4
s.render.resolution_x=W
s.render.resolution_y=H
s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG'
s.render.image_settings.color_mode='RGBA'
s.render.image_settings.color_depth='8'
s.render.film_transparent=True
s.render.use_border=False
s.view_layers[0].cycles.use_pass_shadow_catcher=False
s['source_scene_sha256']=source_hash
s['ground_dressing_scope']='Two low decorative modules, fixed view/light, ground layer, no collision'
bpy.ops.outliner.orphans_purge(do_recursive=True)
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source/ground-dressing.blend'),compress=True)
sun=next(o for o in lights if o.data.type=='SUN')
ray=sun.matrix_world.to_3x3() @ Vector((0,0,-1))
assert max(abs(a-b) for a,b in zip(ray,reference['modules'][0]['shadow']['sun_ray_direction']))<1e-6

doc={'schema':'two-low-ground-decoration-modules-v1','source_scene_sha256':source_hash,
     'frozen_v111_manifest_sha256':v111_hash,'resolution':[W,H],'camera_elevation_degrees':55,
     'orthographic_width_metres':27,'module_foot_source_pixel':[640,360],
     'projection':reference['projection'],'sun_ray_direction':list(ray),
     'modules':defs,'renderer':'Blender 4.3.2 Cycles CPU; 256 max samples; no denoising',
     'neighbor_objects_in_render':[],'old_terrain_in_render':False,'new_collision_count':0,
     'render_batch_count':1,'external_downloads':False,
     'placement_policy':'Sparse fixed placements at true obstacle edges; entrance, paths, enemy groups and drops stay clear. Always draw below actors/enemies/drops.',
     'limits':['Only XY translation at fixed scale/orientation on horizontal z=0 ground',
               'Baked fixed sunlight/material/self-shadow, not dynamic lighting',
               'Neutral shadow decals approximate flat-ground contact/cast shadow; no object-to-object cast shadows',
               'No runtime random rotation, mirroring, scaling, slope/elevation placement',
               'No collision. Placement envelopes are only to keep routes and drop space clear']}
(ROOT/'source/module-definitions.json').write_text(json.dumps(doc,indent=2)+'\n')

s.use_nodes=True
nt=s.node_tree
nt.nodes.clear()
rl=nt.nodes.new('CompositorNodeRLayers')
comp=nt.nodes.new('CompositorNodeComposite')
sub=nt.nodes.new('CompositorNodeMath')
sub.operation='SUBTRACT'
sub.inputs[1].default_value=.008
sub.use_clamp=True
nt.links.new(rl.outputs['Alpha'],sub.inputs[0])
div=nt.nodes.new('CompositorNodeMath')
div.operation='DIVIDE'
div.inputs[1].default_value=.992
div.use_clamp=True
nt.links.new(sub.outputs[0],div.inputs[0])
seta=nt.nodes.new('CompositorNodeSetAlpha')
seta.mode='REPLACE_ALPHA'
seta.inputs['Image'].default_value=(0,0,0,1)
nt.links.new(div.outputs[0],seta.inputs['Alpha'])

def pixel(v):
    q=world_to_camera_view(s,s.camera,v)
    return [q.x*W,(1-q.y)*H]

def crop_for(vs,pad):
    ps=[pixel(v) for v in vs]
    return [math.floor(min(p[0] for p in ps))-pad,math.floor(min(p[1] for p in ps))-pad,
            math.ceil(max(p[0] for p in ps))+pad,math.ceil(max(p[1] for p in ps))+pad]

def render(key,box,shadow):
    s.render.use_border=True
    s.render.use_crop_to_border=True
    s.render.border_min_x=box[0]/W
    s.render.border_max_x=box[2]/W
    s.render.border_min_y=1-box[3]/H
    s.render.border_max_y=1-box[1]/H
    f32=lambda x:struct.unpack('f',struct.pack('f',x))[0]
    actual=[int(f32(s.render.border_min_x*W)),H-int(f32(s.render.border_max_y*H)),
            int(f32(s.render.border_max_x*W)),H-int(f32(s.render.border_min_y*H))]
    for link in list(comp.inputs['Image'].links):nt.links.remove(link)
    nt.links.new(seta.outputs['Image'] if shadow else rl.outputs['Image'],comp.inputs['Image'])
    filename=key+('_shadow' if shadow else '')+'.png'
    s.render.filepath=str(ROOT/'source/raw-renders'/filename)
    bpy.ops.render.render(write_still=True)
    return {'image':'exports/'+filename,'raw_render':'source/raw-renders/'+filename,
            'source_pixel_rect':{'x':actual[0],'y':actual[1],'width':actual[2]-actual[0],'height':actual[3]-actual[1]},
            'foot_source_pixel':[640,360],'foot_local_pixel':[640-actual[0],360-actual[1]],
            'sprite_centered':False,'source_pixels_per_metre_x':PX}

for rec,(key,obs,_) in zip(defs,groups):
    for o in allparts:
        o.hide_render=o not in obs
        o.visible_camera=True
    receiver.hide_render=False
    receiver.visible_camera=False
    receiver.is_shadow_catcher=False
    vs=[o.matrix_world @ v.co for o in obs for v in o.data.vertices]
    rec['sprite']=render(key,crop_for(vs,5),False)
    for o in obs:o.visible_camera=False
    receiver.visible_camera=True
    receiver.is_shadow_catcher=True
    projected=[v-ray*(v.z/ray.z) for v in vs]
    groundfoot=[Vector((v.x,v.y,0)) for v in vs]
    rec['shadow']=render(key,crop_for(projected+groundfoot,24),True)
    rec['shadow'].update({'blend':'straight-alpha neutral black source-over','dynamic_lighting':False,
        'ground_receiver_z_metres':0,'sun_ray_direction':list(ray),'alpha_floor_removed_in_compositor':.008,
        'method':'Cycles native shadow catcher, isolated target group, neutral horizontal receiver'})
    (ROOT/'exports/manifest.rendered.json').write_text(json.dumps(doc,indent=2)+'\n')
    print('MODULE_RENDERED',key,flush=True)

assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==source_hash
assert hashlib.sha256(MANIFEST_V111.read_bytes()).hexdigest()==v111_hash
(ROOT/'source/BATCH_COMPLETE.json').write_text(json.dumps({'result':'PASS','rendered_modules':2,'rendered_images':4,
    'batch_count':1,'frozen_source_unchanged':True,'frozen_v111_manifest_unchanged':True},indent=2)+'\n')
print('GROUND_DRESSING_BATCH_COMPLETE',flush=True)
