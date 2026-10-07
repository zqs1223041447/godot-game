"""Read-only source inventory, no rendering or saving of source blend."""
import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
r=Path(__file__).resolve().parent.parent
src=r.parent/'v108-professional-environment/sunlit-ruins-environment.blend'
bpy.ops.wm.open_mainfile(filepath=str(src))
found=[]; seen=set()
for o in bpy.context.scene.objects:
 if o.type!='MESH': continue
 if not o.name.startswith(('Fern cluster','Loose scanned rubble','Authored tree frame')): continue
 if o.data.name in seen: continue
 seen.add(o.data.name)
 vs=[v.co for v in o.data.vertices]
 bounds=[[min(v[k] for v in vs),max(v[k] for v in vs)] for k in range(3)]
 found.append({'object':o.name,'mesh':o.data.name,'asset':o.get('source_asset'),'mesh_aabb':bounds,'mesh_dimensions':[b-a for a,b in bounds],'original_scale':list(o.scale),'rotation_euler':list(o.rotation_euler),'materials':[m.name for m in o.data.materials],'vertex_count':len(vs),'triangles':sum(len(p.vertices)-2 for p in o.data.polygons),'material_face_counts':{str(i):sum(1 for p in o.data.polygons if p.material_index==i) for i in range(len(o.data.materials))}})
doc={'frozen_source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'source_scene':str(src),'source_objects':found,'rendered':False,'source_saved':False}
(r/'source/source-inventory.json').write_text(json.dumps(doc,indent=2))
print(json.dumps(doc,indent=2))
