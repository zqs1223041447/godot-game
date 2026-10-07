"""Read the finalized derivative modules without saving/rendering or changing any source file."""
import bpy, json, hashlib
import numpy as np
from pathlib import Path
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
W=Path(__file__).resolve().parent; S=W.parent; R=S.parent
F=S/'modules.blend'; D=S/'module-definitions.json'
bpy.ops.wm.open_mainfile(filepath=str(F))
defs=json.loads(D.read_text()); scene=bpy.context.scene; deps=bpy.context.evaluated_depsgraph_get(); arrays={}; records=[]
for spec in defs['modules']:
 vertices=[]; triangles=[]; parts=[]; offset=0
 for name in spec['parts']:
  obj=bpy.data.objects[name]; ev=obj.evaluated_get(deps); mesh=ev.to_mesh(); mesh.calc_loop_triangles()
  vv=np.array([tuple(ev.matrix_world@v.co) for v in mesh.vertices],dtype=np.float64)
  tt=np.array([tuple(t.vertices) for t in mesh.loop_triangles],dtype=np.int32)
  vertices.append(vv);triangles.append(tt+offset);offset+=len(vv)
  parts.append({'object_name':name,'vertices':len(vv),'triangles':len(tt),'polygons':len(mesh.polygons),'matrix_world':[list(row) for row in ev.matrix_world],'modifiers':[m.name for m in obj.modifiers]});ev.to_mesh_clear()
 v=np.concatenate(vertices);t=np.concatenate(triangles)
 arrays[spec['id']+'_vertices']=v; arrays[spec['id']+'_triangles']=t
 low=v[v[:,2]<=v[:,2].min()+.3];foot=[float((low[:,0].min()+low[:,0].max())/2),float(low[:,1].min()),float(v[:,2].min())]
 records.append({**spec,'parts_extracted':parts,'mesh_local_aabb_metres':[v.min(axis=0).tolist(),v.max(axis=0).tolist()],'measured_local_foot_metres':foot,'vertices_including_split_seams':len(v),'triangles':len(t)})
checks=[]
for xyz in [(0,0,0),(1,0,0),(0,1,0),(0,0,1),(-2,1.5,2)]:
 p=world_to_camera_view(scene,scene.camera,Vector(xyz));checks.append({'local_metres':xyz,'actual_full_frame_pixel':[1280*p.x,720*(1-p.y)]})
out={'module_blend':'source/modules.blend','module_blend_sha256':hashlib.sha256(F.read_bytes()).hexdigest(),'definitions_sha256':hashlib.sha256(D.read_bytes()).hexdigest(),'source_scene_sha256':defs['source_scene_sha256'],'blender_version':bpy.app.version_string,'module_count':len(records),'modules':records,'camera_projection_checks':checks}
np.savez_compressed(W/'actual-module-meshes.npz',**arrays);(W/'actual-module-metadata.json').write_text(json.dumps(out,ensure_ascii=False,indent=2))
print(json.dumps(out,ensure_ascii=False,indent=2))
