"""Read-only verification of saved static correction and scoped gaps."""
import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from bpy_extras.object_utils import world_to_camera_view
R=Path(__file__).resolve().parents[1];s=bpy.context.scene
fix=json.loads((R/'reports/shoulder-correction-report.json').read_text());rep=json.loads((R/'reports/assembly-report.json').read_text());p=rep['pose'];center=Vector([(a+b)/2 for a,b in zip(p['min'],p['max'])]);el=math.radians(55);right=Vector((1,0,0));up=Vector((0,math.sin(el),math.cos(el)));toward=Vector((0,-math.cos(el),math.sin(el)))
def sha(data):return hashlib.sha256(json.dumps(data,sort_keys=True,separators=(',',':')).encode()).hexdigest()
sig={}
for o in bpy.data.objects:
 if o.type=='ARMATURE':sig[o.name]=sha({'bones':[(b.name,b.parent.name if b.parent else None,[list(row) for row in b.matrix_local]) for b in o.data.bones],'pose':[(b.name,[list(row) for row in b.matrix_basis]) for b in o.pose.bones]})
 elif o.type=='MESH' and o.parent and o.parent.type=='ARMATURE':sig[o.name]=sha({'verts':[list(v.co) for v in o.data.vertices],'faces':[list(f.vertices) for f in o.data.polygons],'weights':[[(g.group,g.weight) for g in v.groups] for v in o.data.vertices],'groups':[g.name for g in o.vertex_groups],'modifiers':[(m.name,m.type,getattr(getattr(m,'object',None),'name',None)) for m in o.modifiers]})
assert sig==fix['original_character_signatures_before'],'Original character changed'
dg=bpy.context.evaluated_depsgraph_get();bvhs=[];allverts=[]
for o in bpy.data.objects:
 if o.type!='MESH' or o.name=='Sample Neutral Ground':continue
 ev=o.evaluated_get(dg);me=ev.to_mesh();me.calc_loop_triangles();vv=[ev.matrix_world@v.co for v in me.vertices];allverts+=vv
 bvhs.append((o.name,BVHTree.FromPolygons(vv,[tuple(t.vertices) for t in me.loop_triangles],all_triangles=True)));ev.to_mesh_clear()
def first(x,y):
 plane=center+right*((x+.5-600)*2.1/1200)+up*((600-y-.5)*2.1/1200);origin=plane+toward*10;hits=[]
 for name,bvh in bvhs:
  loc,n,idx,d=bvh.ray_cast(origin,-toward,100)
  if loc is not None:hits.append((d,name))
 return min(hits)[1] if hits else None
baseline={tuple(q['pixel']):q['name'] for q in json.loads((R/'reports/shoulder-surface-grid.json').read_text())['samples']}
checks=[]
for q in fix['attachment_samples']:
 xl,y=q['left_pixel'];xr,_=q['right_pixel']
 for x in range(xl+2,xr,2):checks.append({'pixel':[x,y],'before':baseline.get((x,y)),'after':first(x,y)})
missing=[q for q in checks if not q['before']];after_missing=[q for q in checks if not q['after']]
proj=[world_to_camera_view(s,s.camera,v) for v in allverts]
bounds={'min_x':min(v.x for v in proj)*1280,'max_x':max(v.x for v in proj)*1280,'min_y':(1-max(v.y for v in proj))*720,'max_y':(1-min(v.y for v in proj))*720}
bounds['width']=bounds['max_x']-bounds['min_x'];bounds['height']=bounds['max_y']-bounds['min_y']
result={'blend_file':str(R/'ranger-sample.blend'),'original_character_signatures_match':True,'original_character_object_count':len(sig),'added_object':'Static_Shoulder_Lining_Bridge','projection_bounds':bounds,'scoped_shoulder_rays':len(checks),'original_open_rays':len(missing),'final_open_rays':len(after_missing),'original_open_rays_recheck':missing,'all_scope_rays':checks,'source_actions_assigned':{o.name:o.animation_data.action.name if o.animation_data and o.animation_data.action else None for o in bpy.data.objects if o.type=='ARMATURE'},'limits':['Only scoped static shoulder rays checked; no all-pose or watertightness claim.','Added lining is pose-specific and unskinned. No animation integration tested.']}
result['final_open_ray_details']=after_missing
result['interior_open_rays']=sum(q['after'] is None for q in checks if q['pixel'][1] not in [360,432])
result['terminal_edge_open_rays']=sum(q['after'] is None for q in checks if q['pixel'][1] in [360,432])
result['limits'].append('Six rays on the exact upper/lower terminal edges still do not hit character geometry; no fully sealed or watertight shoulder claim is made.')
assert all(v is None for v in result['source_actions_assigned'].values())
(R/'reports/final-sample-verification.json').write_text(json.dumps(result,indent=2))
print(json.dumps({k:v for k,v in result.items() if k not in ['all_scope_rays','original_open_rays_recheck']},indent=2))
