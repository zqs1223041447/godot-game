"""Read-only focused ray inspection. Run with --disable-autoexec."""
import bpy,json,math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
R=Path(__file__).resolve().parents[1];report=json.loads((R/'reports/assembly-report.json').read_text());p=report['pose'];center=Vector([(a+b)/2 for a,b in zip(p['min'],p['max'])]);el=math.radians(55);right=Vector((1,0,0));up=Vector((0,math.sin(el),math.cos(el)));toward=Vector((0,-math.cos(el),math.sin(el)));dire=-toward
dg=bpy.context.evaluated_depsgraph_get();obs=[]
for o in bpy.data.objects:
 if o.type!='MESH' or not o.name.startswith('Female_Ranger'):continue
 ev=o.evaluated_get(dg);m=ev.to_mesh();m.calc_loop_triangles();vv=[ev.matrix_world@v.co for v in m.vertices];ff=[tuple(t.vertices) for t in m.loop_triangles];obs.append((o.name,BVHTree.FromPolygons(vv,ff,all_triangles=True)));ev.to_mesh_clear()
samples=[]
for y in range(348,441,2):
 for x in range(650,733,2):
  plane=center+right*((x+.5-600)*2.1/1200)+up*((600-y-.5)*2.1/1200);origin=plane+toward*10;hits=[]
  for name,bvh in obs:
   loc,n,idx,d=bvh.ray_cast(origin,dire,100)
   if loc is not None:hits.append((d,name,list(loc),list(n),idx))
  if hits:
   d,name,loc,n,idx=min(hits);samples.append({'pixel':[x,y],'name':name,'loc':loc,'normal':n,'tri':idx})
(R/'reports/shoulder-surface-grid.json').write_text(json.dumps({'samples':samples,'read_only':True},indent=2))
print('SURFACE_GRID_READY',len(samples))
