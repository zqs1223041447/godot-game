import bpy,math,json,sys,argparse
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
r=Path(__file__).resolve().parent
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
parser=argparse.ArgumentParser();parser.add_argument('--report',type=Path);options=parser.parse_args(args)
bpy.ops.wm.open_mainfile(filepath=str(r/'sunlit-ruins-environment.blend'))
s=bpy.context.scene;cam=s.camera
images=[i for i in bpy.data.images if i.source=='FILE'];bad=[i.name for i in images if not i.packed_file];print('FILE_IMAGES',len(images),'UNPACKED',bad)
projection=[]
for name,pt in [('reference_feet',(0,-.7,0)),('reference_head',(0,-.7,1.8)),('world_origin',(0,0,0)),('gate_floor',(1.75,4.45,0))]:
 v=world_to_camera_view(s,cam,Vector(pt));projection.append({'name':name,'metres':pt,'pixels':[v.x*1280,(1-v.y)*720]})
report={'render_exists':(r.parent/'godot_preview/assets/environment-final.png').exists(),'packed_images':len(images),'unpacked_image_names':bad,'exact_camera_projection':projection,'camera_ortho_scale':cam.data.ortho_scale,'resolution':[s.render.resolution_x,s.render.resolution_y],'percentage':s.render.resolution_percentage,'threads':s.render.threads,'samples_max':s.cycles.samples,'denoising':s.cycles.use_denoising,'render_engine':s.render.engine,'blender_version':bpy.app.version_string,'visible_mesh_objects':sum(o.type=='MESH' and not o.hide_render for o in s.objects)}
print(json.dumps(report,indent=2))
if options.report is not None:
 target=options.report.resolve()
 if target.suffix.lower()!='.json' or target==(r/'verification-final.json').resolve(): raise ValueError('Choose a new .json report path; preserve original evidence')
 target.write_text(json.dumps(report,indent=2)+'\n')
if bad: raise RuntimeError('Packed scene has external image dependencies')
