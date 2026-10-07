"""Run after art-direction approval:
blender -b environment_native_preview.blend --python export_sprites.py
Exports 3 real RGBA renders and camera-derived runtime metadata. No image paint-over.
"""
import bpy, math, json, os
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
OUT=os.path.dirname(os.path.abspath(__file__))
scene=bpy.context.scene;cam=scene.camera
E=math.radians(55);S=math.sin(E);C=math.cos(E);PPW=2;WU=20;PPBU=PPW*WU
scene.cycles.device='CPU';scene.cycles.use_denoising=False;scene.cycles.samples=144
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.image_settings.color_depth='8';scene.render.film_transparent=True
scene.render.resolution_percentage=100;scene.render.threads_mode='FIXED';scene.render.threads=4
# Undo the display-only separations from the preview scene.
for o in bpy.data.collections['WALL_96x64_H70'].objects:o.location.x+=9.5
for o in bpy.data.collections['GINKGO_BASE_80x80_H180'].objects:o.location.x-=10
bpy.data.collections['SHOWCASE_ONLY'].hide_render=True
bpy.context.view_layer.update()
# Normalize the full authored tree to an exact 180-world-unit maximum height.
tree_col=bpy.data.collections['GINKGO_BASE_80x80_H180']
tree_top=max((o.matrix_world@Vector(v)).z for o in tree_col.objects if o.type=='MESH' for v in o.bound_box)
for o in tree_col.objects:
    o.location.z*=9.0/tree_top
    o.scale.z*=9.0/tree_top
bpy.context.view_layer.update()
specs=[
    ('ruin_wall','WALL_96x64_H70',(96,64),(512,512),440,70),
    ('stone_planter','GARDEN_PLINTH_160x120_H45',(160,120),(512,512),450,45),
    ('ginkgo_tree','GINKGO_BASE_80x80_H180',(80,80),(512,768),645,180),
]
allcolls=[s[1] for s in specs]
result={'version':2,'camera':{'projection':'orthographic','elevation_deg':55,'azimuth_deg':0,'pixels_per_world':PPW,'blender_units_per_world':1/WU,'ground_depth_compensation':1/S},'lighting':'Fixed upper-left warm key, soft cool front fill, broad warm rim. Cycles CPU. Transparent film.','geometry':'Original reproducible meshes and procedural PBR materials, authored by build_environment.py; no external assets.','axis_mapping':'Blender +X => Godot +X. Blender -Y => Godot +Y. Z gives visual height; it does not change collision.','assets':[]}

def px(point):
    v=world_to_camera_view(scene,cam,Vector(point));return [round(v.x*scene.render.resolution_x,5),round((1-v.y)*scene.render.resolution_y,5)]

def setup_camera(res,depth,front_y):
    scene.render.resolution_x=res[0];scene.render.resolution_y=res[1]
    cam.data.type='ORTHO';cam.data.ortho_scale=10
    target=Vector((0,0,0));cam.location=target+Vector((0,-C*70,S*70));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();bpy.context.view_layer.update()
    ratio=(px((1,0,0))[0]-px((0,0,0))[0])/PPBU;cam.data.ortho_scale*=ratio
    base_y=front_y-depth*PPW/2
    target=Vector((0,S,C))*((base_y-res[1]/2)/PPBU)
    cam.location=target+Vector((0,-C*70,S*70));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();bpy.context.view_layer.update()

for name,cname,foot,res,front_y,h in specs:
    for col in allcolls:bpy.data.collections[col].hide_render=(col!=cname)
    setup_camera(res,foot[1],front_y)
    outfile=os.path.join(OUT,name+'.png');scene.render.filepath=outfile
    bpy.ops.render.render(write_still=True)
    im=bpy.data.images.load(outfile,check_existing=False);w,hpx=im.size
    pix=list(im.pixels);xs=[];ys=[]
    for y in range(hpx):
        for x in range(w):
            if pix[(y*w+x)*4+3]>1/255:xs.append(x);ys.append(hpx-1-y)
    bbox=[min(xs),min(ys),max(xs)+1,max(ys)+1] if xs else [0,0,0,0]
    alpha=[pix[i] for i in range(3,len(pix),4)]
    dBU=foot[1]/WU/S;wBU=foot[0]/WU
    entry={'path':'assets/environment/'+name+'.png','file':name+'.png','world_footprint':list(foot),'pixels_per_world':2,'canvas_px':list(res),'anchor_px':px((0,-dBU/2,0)),'base_center_anchor':px((0,0,0)),'visual_bounds':bbox,'visual_bounds_format':'[left,top,right_exclusive,bottom_exclusive] alpha>1/255','ground_corners_px':[px((-wBU/2,-dBU/2,0)),px((wBU/2,-dBU/2,0)),px((wBU/2,dBU/2,0)),px((-wBU/2,dBU/2,0))],'height_world':h,'mesh_bounds_world':[[round(min((o.matrix_world@Vector(v))[a] for o in bpy.data.collections[cname].objects if o.type=='MESH' for v in o.bound_box)*WU,5) for a in range(3)],[round(max((o.matrix_world@Vector(v))[a] for o in bpy.data.collections[cname].objects if o.type=='MESH' for v in o.bound_box)*WU,5) for a in range(3)]],'camera_ortho_scale':cam.data.ortho_scale,'fully_transparent_pixels':sum(a==0 for a in alpha),'partially_transparent_pixels':sum(0<a<1 for a in alpha),'min_alpha':min(alpha),'max_alpha':max(alpha),'anchor_definition':'Projection of ground footprint front-edge center; this anchor is intended for depth sorting. base_center_anchor is provided for footprint-centered placement.'}
    result['assets'].append(entry)
    with open(os.path.join(OUT,'environment_manifest.json'),'w') as f:json.dump(result,f,indent=2)
    bpy.data.images.remove(im)
    print('EXPORTED',name,entry,flush=True)
print('ALL_ENVIRONMENT_SPRITES_EXPORTED',flush=True)
