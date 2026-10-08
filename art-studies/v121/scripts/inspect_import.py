import bpy,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
manifest=json.loads((ROOT/'reports/source-manifest.json').read_text())
report={}
for name in ['Female_Ranger','Superhero_Female_FullBody','Hair_BuzzedFemale','Female_Peasant_Body']:
 before=set(bpy.data.objects)
 bpy.ops.import_scene.gltf(filepath=manifest['asset_paths'][name],bone_heuristic='BLENDER')
 objs=set(bpy.data.objects)-before
 entry=[]
 for o in sorted(objs,key=lambda o:o.name):
  d={'name':o.name,'type':o.type,'parent':o.parent.name if o.parent else None,'bounds':[list(v) for v in o.bound_box],'matrix': [list(r) for r in o.matrix_world]}
  if o.type=='MESH':d.update(vertices=len(o.data.vertices),faces=len(o.data.polygons),materials=[m.name for m in o.data.materials],groups=[v.name for v in o.vertex_groups],minZ=min(v.co.z for v in o.data.vertices),maxZ=max(v.co.z for v in o.data.vertices))
  if o.type=='ARMATURE':d.update(bones=[b.name for b in o.data.bones],actions=[a.name for a in bpy.data.actions],action=o.animation_data.action.name if o.animation_data and o.animation_data.action else None,bone_positions={b.name:list(b.head_local) for b in o.data.bones})
  entry.append(d)
 report[name]=entry
(ROOT/'reports/blender-import-inspection.json').write_text(json.dumps(report,indent=2))
for a in bpy.data.actions:print('ACTION',a.name,list(a.frame_range),len(a.fcurves), [c.data_path for c in a.fcurves][:5])
for k,v in report.items():
 print('ASSET',k)
 for o in v: print(o['name'],o['type'],o.get('minZ'),o.get('maxZ'),o.get('action'),o.get('materials'))
print('COMPLETE_INSPECT')
