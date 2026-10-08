import bpy,json,math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
R=Path(__file__).resolve().parents[1];report=json.loads((R/'reports/assembly-report.json').read_text());p=report['pose'];center=Vector([(a+b)/2 for a,b in zip(p['min'],p['max'])]);el=math.radians(55);right=Vector((1,0,0));up=Vector((0,math.sin(el),math.cos(el)));toward=Vector((0,-math.cos(el),math.sin(el)));dir=-toward
dg=bpy.context.evaluated_depsgraph_get();objects=[]
for ob in bpy.data.objects:
 if ob.type!='MESH':continue
 ev=ob.evaluated_get(dg);me=ev.to_mesh();me.calc_loop_triangles();V=[ev.matrix_world@v.co for v in me.vertices];F=[tuple(t.vertices) for t in me.loop_triangles];bvh=BVHTree.FromPolygons(V,F,all_triangles=True);mats=[ob.material_slots[me.polygons[t.polygon_index].material_index].name if len(ob.material_slots) else None for t in me.loop_triangles];objects.append((ob.name,bvh,mats));ev.to_mesh_clear()
def hits(x,y):
 plane=center+right*((x+.5-600)*2.10/1200)+up*((600-y-.5)*2.10/1200);origin=plane+toward*10;seq=[]
 for n in range(8):
  all=[]
  for name,bvh,mats in objects:
   loc,normal,idx,distance=bvh.ray_cast(origin,dir,100)
   if loc is not None:all.append((distance,name,loc,normal,idx,mats[idx]))
  if not all:break
  distance,name,loc,norm,idx,mat=min(all,key=lambda a:a[0]);seq.append({'object':name,'material':mat,'world':list(loc),'backface':norm.dot(dir)>0,'normal_dot_toward_camera':norm.dot(toward),'triangle':idx});origin=loc+dir*1e-4
 return seq
coords=[(713,365),(710,370),(707,375),(705,380),(695,390),(694,395),(690,400),(685,405),(685,410),(680,415),(672,420),(669,425),(704,395),(678,400),(717,387)]
res={'view':{'center':list(center),'elevation':55,'orthographic_width':2.10,'resolution':[1200,1200]},'samples':[{'pixel':[x,y],'hits':hits(x,y)} for x,y in coords]};(R/'reports/shoulder-opening-ray-diagnosis.json').write_text(json.dumps(res,indent=2));print(json.dumps(res,indent=2))
