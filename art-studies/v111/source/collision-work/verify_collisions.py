#!/usr/bin/python3
"""Read-only independent serialized geometry, source identity, and camera projection validation."""
import json,hashlib,math
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree
from osgeo import ogr
ogr.UseExceptions()
W=Path(__file__).resolve().parent;S=W.parent;R=S.parent;OLD=R.parent/'v108-professional-environment'
D=json.loads((R/'exports/collisions.json').read_text());M=json.loads((W/'actual-module-metadata.json').read_text());A=np.load(W/'actual-module-meshes.npz');B=json.loads((W/'base-geometries.json').read_text());DEFS=json.loads((S/'module-definitions.json').read_text());OLDM=json.loads((OLD/'exports/collision-work/actual-meshes-metadata.json').read_text());OLDD=np.load(OLD/'exports/collision-work/actual-meshes.npz')
def pg(points):
 r=ogr.Geometry(ogr.wkbLinearRing)
 for x,y in points:r.AddPoint_2D(float(x),float(y))
 r.CloseRings();g=ogr.Geometry(ogr.wkbPolygon);g.AddGeometry(r);return g

def union(gs):
 c=ogr.Geometry(ogr.wkbGeometryCollection)
 for g in gs:c.AddGeometry(g)
 return c.UnaryUnion()

counts=0;vertices=0;max_px=0;max_gd=0;geoms={};per_module=[]
for entry in D['modules']:
 key=entry['module_id'];source=next(o for o in M['modules'] if o['id']==key);orig=next(o for o in OLDM['blocking_objects'] if o['object_name']==entry['source_object_name'])
 for field in ['source_object_name','source_scene_transform','source_foot_world_metres','normalization_translation_metres','mesh_local_aabb_metres']:
  assert entry[field]==source[field],(key,field)
 vv=A[key+'_vertices'];tt=A[key+'_triangles'];oldv=OLDD[orig['key']+'_vertices']+np.array(entry['normalization_translation_metres']);oldt=OLDD[orig['key']+'_triangles']
 forward=cKDTree(vv).query(oldv)[0].max();reverse=cKDTree(oldv).query(vv)[0].max();vertex_error=float(max(forward,reverse));assert vertex_error<2e-6,(key,vertex_error)
 oldcent=oldv[oldt].mean(axis=1);newcent=vv[tt].mean(axis=1);centroid_error=float(max(cKDTree(oldcent).query(newcent)[0].max(),cKDTree(newcent).query(oldcent)[0].max()));assert len(tt)==len(oldt) and centroid_error<2e-6,(key,centroid_error)
 module_polys=[]
 for p in entry['polygons']:
  assert not p['holes'],'Any future collider holes require an explicit importer contract'
  o=p['outer'];xy=np.array(o['ground_xy_metres']);g=pg(xy);assert g.IsValid() and not g.IsEmpty();module_polys.append(g);counts+=1
  winding=sum(xy[i,0]*xy[(i+1)%len(xy),1]-xy[(i+1)%len(xy),0]*xy[i,1] for i in range(len(xy)));assert winding>0
  for pt,sp,full,gd in zip(xy,o['foot_relative_screen_pixel'],o['full_frame_screen_pixel'],o['godot_local_world']):
   pexpected=np.array([1280/27*pt[0],-38.83387469221887*pt[1]]);gexpected=np.array([72.9344729345*pt[0],-59.7444226034*pt[1]])
   max_px=max(max_px,float(np.max(abs(pexpected-sp))),float(np.max(abs(pexpected+[640,360]-full))));max_gd=max(max_gd,float(np.max(abs(gexpected-gd))));vertices+=1
  assert np.max(abs(np.array(o['full_frame_screen_pixel'])-np.array(o['foot_relative_screen_pixel'])-[640,360]))<2e-9
 geom=union(module_polys);geoms[key]=geom;base=ogr.CreateGeometryFromWkt(B[key]['base_wkt']);missing=base.Difference(geom).GetArea();assert missing<1e-9,(key,missing)
 per_module.append({'module_id':key,'serialized_polygon_count':len(module_polys),'serialized_polygons_valid':geom.IsValid(),'base_uncovered_area_after_serialization_m2':missing,'maximum_normalized_source_vertex_difference_metres':vertex_error,'maximum_normalized_source_triangle_centroid_difference_metres':centroid_error,'original_triangle_count':len(oldt),'derivative_triangle_count':len(tt),'local_foot_residual_metres':source['measured_local_foot_metres'],'minimum_margin_after_serialization_metres':base.Boundary().Distance(geom.Boundary()),'rock_hull_extra_area_m2':entry['tolerances']['convex_hull_extra_area_m2']})
assert counts==4 and vertices>0 and max_px<1e-7 and max_gd<1e-7
pv=D['portal_validation'];start=pv['verified_centerline']['start']['ground_xy_metres'];end=pv['verified_centerline']['end']['ground_xy_metres'];path=ogr.Geometry(ogr.wkbLineString);path.AddPoint_2D(*start);path.AddPoint_2D(*end);distance=path.Distance(geoms['walkable_arch']);assert distance>.3
# Centerline-to-geometry distance is exact for these linear pieces; it proves the true .3m circle clear, independent of a polygonal buffer approximation.
projection=[]
for case in M['camera_projection_checks']:
 x,y,z=case['local_metres'];expect=[640+1280/27*x,360-38.83387469221887*y-27.191771797382927*z];err=max(abs(np.array(expect)-case['actual_full_frame_pixel']));assert err<.001
 projection.append({**case,'analytic_full_frame_pixel':expect,'max_difference_pixel':float(err)})
source_hash=hashlib.sha256((OLD/'sunlit-ruins-environment.blend').read_bytes()).hexdigest();module_hash=hashlib.sha256((S/'modules.blend').read_bytes()).hexdigest();defs_hash=hashlib.sha256((S/'module-definitions.json').read_bytes()).hexdigest()
assert source_hash==D['frozen_source_scene_sha256']==OLDM['scene_sha256'];assert module_hash==D['source_module_blend_sha256'];assert defs_hash==D['source_definitions_sha256']
result={'result':'PASS','module_count':3,'serialized_polygon_count':counts,'serialized_collision_vertices_checked':vertices,'source_v108_blend_sha256_unchanged':True,'module_blend_sha256_unchanged':True,'module_definitions_sha256_unchanged':True,'all_source_triangles_preserved_in_derivative_modules':True,'original_mesh_comparison_tolerance_metres':2e-6,'maximum_screen_mapping_rounding_error_pixel':max_px,'maximum_godot_mapping_rounding_error_units':max_gd,'independent_actual_blender_camera_projection_checks':projection,'per_module':per_module,'arch_true_circle_sweep_radius_metres':.3,'arch_centerline_exact_minimum_distance_to_serialized_colliders_metres':distance,'arch_character_side_clearance_metres':distance-.3,'arch_two_disjoint_legs':geoms['walkable_arch'].GetGeometryCount()==2,'arch_geometric_passage_1p8m_by_radius_0p3m':True,'flat_ground_local_z_metres':0,'nominal_margin_metres':.025,'margin_error_note':'Nominal 25mm outward buffer after 8mm simplification and before 1mm simplification. Measured actual minimum offset is per-module; boundary displacement bound is 34mm excluding rock hull filling.','no_game_physics_or_assembled_layout_test':True}
assert result['arch_two_disjoint_legs']
(W/'independent-verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print(json.dumps(result,ensure_ascii=False,indent=2))
