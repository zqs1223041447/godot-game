#!/usr/bin/python3
"""Build independent fixed-orientation local modules from their finalized normalized meshes."""
import json, math, hashlib
from pathlib import Path
import numpy as np
from geometry_common import ogr, polygon, line, polys, collection_union, boundary_section, slab_footprint
W=Path(__file__).resolve().parent; S=W.parent; R=S.parent
D=np.load(W/'actual-module-meshes.npz'); M=json.loads((W/'actual-module-metadata.json').read_text()); DEFS=json.loads((S/'module-definitions.json').read_text())
HEIGHT=1.8;RADIUS=.3;GUARD=.001;SIMPLIFY=.008;MARGIN=.025;FINAL=.001
PX=1280/27; PY=38.83387469221887; PZ=27.191771797382927; GX=72.9344729345; GY=59.7444226034

def rounded(values):return [round(float(x),9) for x in values]
def screen(x,y,z=0):return [PX*x,-PY*y-PZ*z]
def godot(x,y):return [GX*x,-GY*y]
def ref(x,y,z=0):return {'ground_xy_metres':rounded([x,y]),'local_xyz_metres':rounded([x,y,z]),'foot_relative_screen_pixel':rounded(screen(x,y,z)),'full_frame_screen_pixel':rounded(np.array(screen(x,y,z))+[640,360]),'godot_local_world':rounded(godot(x,y))}
def points(g):
 out=[]
 for p in polys(g):out.extend(p.GetGeometryRef(0).GetPoints())
 return np.asarray(out)[:,:2]
def serial(poly):
 rings=[]
 for i in range(poly.GetGeometryCount()):
  ring=poly.GetGeometryRef(i); xy=[rounded(ring.GetPoint(j)[:2]) for j in range(ring.GetPointCount()-1)]
  area=sum(xy[j][0]*xy[(j+1)%len(xy)][1]-xy[(j+1)%len(xy)][0]*xy[j][1] for j in range(len(xy)))
  if (area>0)!=(i==0):xy.reverse()
  rings.append({'ground_xy_metres':xy,'foot_relative_screen_pixel':[rounded(screen(*p)) for p in xy],'full_frame_screen_pixel':[rounded(np.array(screen(*p))+[640,360]) for p in xy],'godot_local_world':[rounded(godot(*p)) for p in xy]})
 return {'outer':rings[0],'holes':rings[1:]}

def width(g,origin,across):
 legs=sorted(polys(g),key=lambda p:p.GetArea(),reverse=True)
 assert len(legs)==2,('expected two gate legs',len(legs))
 legs.sort(key=lambda p:float(((points(p)-origin)@across).mean()))
 low=float(((points(legs[0])-origin)@across).max());high=float(((points(legs[1])-origin)@across).min())
 return {'left_inner_axis_metres':low,'right_inner_axis_metres':high,'clear_width_metres':high-low,'minimum_euclidean_leg_separation_metres':legs[0].Distance(legs[1]),'component_count':len(legs)}

objects=[];final_geoms={};base_geoms={};raw_geoms={};threshold=None;arch_axes=None
for m in M['modules']:
 key=m['id'];v=D[key+'_vertices'];t=D[key+'_triangles'];rock=key=='moss_rock';lo=-GUARD;hi=HEIGHT+GUARD
 base,raw,details=slab_footprint(v,t,lo,hi,rock=rock)
 if key=='walkable_arch':
  q=v[t];low=q[:,:,2].max(axis=1)<.30;threshold_top=float(q[low,:,2].max());hi=threshold_top+HEIGHT+GUARD
  full,_,details=slab_footprint(v,t,lo,hi);upper,_,_=slab_footprint(v,t,threshold_top+GUARD,hi)
  source_matrix=np.asarray(m['source_scene_transform']['matrix_world']);through=source_matrix[:2,0];through=through/np.linalg.norm(through);across=np.array([through[1],-through[0]])
  origin=np.array(m['source_scene_transform']['location'][:2])+np.array(m['normalization_translation_metres'][:2]);arch_axes=(origin,across,through)
  opening=width(upper,origin,across);depth=(v[:,:2]-origin)@through
  a=opening['left_inner_axis_metres'];b=opening['right_inner_axis_metres'];near=float(depth.min()-.01);far=float(depth.max()+.01)
  corners=[origin+across*u+through*vv for u,vv in [(a,near),(b,near),(b,far),(a,far)]];cut=polygon(corners)
  base=full.Difference(cut).Union(upper);raw=base
  threshold={'classification':'walkable_low_authored_sill','maximum_sill_height_above_flat_ground_metres':threshold_top,'maximum_step_above_flat_ground_metres':threshold_top,'step_up_required':True,'maximum_low_face_classification_height_metres':.30,'low_triangle_count':int(low.sum()),'body_band_top_including_sill_metres':hi,'exemption_polygon_ground_xy_metres':[rounded(p) for p in corners],'removed_low_sill_projection_area_m2':full.GetArea()-base.GetArea(),'visual_mesh_parts':m['parts'],'policy':'Only the low sill inside the actual open portal is nonblocking. Foundations outside the opening stay solid. The visual sill remains. Flat 2D collision treats this as walkable ground; a 3D controller must support a 0.151m step or an equivalent ramp.'}
  details['threshold_exclusion']=threshold
 final=base.SimplifyPreserveTopology(SIMPLIFY).Buffer(MARGIN,8).SimplifyPreserveTopology(FINAL)
 missing=base.Difference(final).GetArea();assert missing<1e-10,(key,missing);assert final.IsValid()
 parts=sorted(polys(final),key=lambda p:p.GetArea(),reverse=True);expected=2 if key=='walkable_arch' else 1;assert len(parts)==expected,(key,len(parts))
 measured_minimum_offset=base.Boundary().Distance(final.Boundary())
 entry={'module_id':key,'source_object_name':m['source_object_name'],'source_asset':m['source_asset'],'mesh_parts':m['parts'],'source_scene_transform':m['source_scene_transform'],'source_foot_world_metres':m['source_foot_world_metres'],'normalization_translation_metres':m['normalization_translation_metres'],'source_transform_baked':True,'classification':'walkable_arch' if key=='walkable_arch' else 'scanned_rock' if rock else 'short_wall','foot':ref(0,0,0),'measured_low_vertices_foot_residual_metres':m['measured_local_foot_metres'],'mesh_local_aabb_metres':m['mesh_local_aabb_metres'],'body_band_local_z_metres':[lo,hi],'ground_support_plane_local_z_metres':0,'polygon_count':len(parts),'ground_collision_area_m2':final.GetArea(),'polygons':[serial(p) for p in parts],'geometry_stats':details,'tolerances':{'clip_vertical_guard_metres':GUARD,'section_endpoint_snap_metres':1e-7,'simplify_metres':SIMPLIFY,'nominal_outward_margin_metres':MARGIN,'final_simplify_metres':FINAL,'buffer_segments_per_quadrant':8,'polygon_rounding_metres':1e-9,'maximum_boundary_displacement_from_base_metres':SIMPLIFY+MARGIN+FINAL,'measured_minimum_final_boundary_offset_from_base_metres':measured_minimum_offset,'raw_base_area_not_covered_m2':missing,'raw_slab_projection_area_m2':raw.GetArea(),'convex_hull_extra_area_m2':base.GetArea()-raw.GetArea() if rock else 0,'margin_note':'25mm is the nominal buffer after 8mm simplification, followed by 1mm simplification. It is not a guaranteed uniform 25mm offset from raw mesh; the measured minimum offset is reported. Combined boundary displacement is at most 34mm, excluding the intentionally conservative rock convex hull. Exact base containment is verified.','rock_hull_note':'A convex hull fills scanned-rock concave notches and scan gaps; its extra area is independent of and not bounded by the 34mm simplification/buffer bound.' if rock else None},'reuse_contract':'XY translation only, fixed authored orientation and scale; do not mirror, rotate, or scale this mesh, sprite, or its collider independently.'}
 if threshold and key=='walkable_arch':entry['walkable_threshold']=threshold
 objects.append(entry);final_geoms[key]=final;base_geoms[key]=base;raw_geoms[key]=raw
 print(key,'polygons',len(parts),'vertices',sum(p.GetGeometryRef(0).GetPointCount()-1 for p in parts),'minimum_margin_m',measured_minimum_offset,flush=True)

origin,across,through=arch_axes;gate=final_geoms['walkable_arch'];raw=base_geoms['walkable_arch'];raw_width=width(raw,origin,across);safe_width=width(gate,origin,across)
u=(safe_width['left_inner_axis_metres']+safe_width['right_inner_axis_metres'])/2;dep=(points(gate)-origin)@through
start=origin+across*u+through*(dep.min()-.65);end=origin+across*u+through*(dep.max()+.65);path=line([start,end]);swept=path.Buffer(RADIUS,32)
clearance=gate.Distance(path);assert clearance>RADIUS;intersection=gate.Intersection(swept);assert intersection.IsEmpty()
gv=D['walkable_arch_vertices'];gt=D['walkable_arch_triangles'];sections=[]
for h in [.10,.9,1.8]:
 cap,count=boundary_section(gv,gt,threshold['maximum_sill_height_above_flat_ground_metres']+h)
 sections.append({'height_above_conservative_sill_top_metres':h,'local_z_metres':threshold['maximum_sill_height_above_flat_ground_metres']+h,'section_segment_count':count,**width(cap,origin,across)})
upper=[]
for tri in gv[gt]:
 if tri[:,2].min()<1:continue
 p=polygon(tri[:,:2])
 if p.GetArea()>1e-12 and p.Intersects(swept):upper.append(float(tri[:,2].min()))
ceiling=min(upper) if upper else None
portal={'module_id':'walkable_arch','source_object_name':next(m['source_object_name'] for m in M['modules'] if m['id']=='walkable_arch'),'basis_origin_local_xy_metres':rounded(origin),'across_unit_xy':rounded(across),'through_unit_xy':rounded(through),'character_height_metres':HEIGHT,'character_radius_metres':RADIUS,'raw_body_band_opening':raw_width,'buffered_collision_opening':safe_width,'remaining_character_center_width_metres':safe_width['clear_width_metres']-2*RADIUS,'threshold':threshold,'actual_mesh_horizontal_section_checks':sections,'verified_centerline':{'start':ref(*start),'end':ref(*end),'minimum_distance_to_arch_blockers_metres':clearance,'minimum_clearance_after_character_radius_metres':clearance-RADIUS,'swept_capsule_radius_metres':RADIUS,'swept_capsule_intersects_arch_blocker':False},'conservative_ceiling_local_z_lower_bound_over_swept_path_metres':ceiling,'conservative_headroom_above_sill_lower_bound_metres':ceiling-threshold['maximum_sill_height_above_flat_ground_metres'] if ceiling is not None else None,'passes_1p8m_tall_0p3m_radius_geometric_test':True,'scope':'Valid for this isolated arch on flat z=0 ground with a walkable 0.15008m sill. Other modules are independent instances, not obstacles overlaid at local origin. The eventual assembled layout requires its own path and overlap validation. This is a geometric test, not a Godot physics or animation test.'}
assert portal['conservative_headroom_above_sill_lower_bound_metres']>=HEIGHT
out={'schema':'fixed-orientation-modular-ground-collision-v1','source_module_blend':'source/modules.blend','source_module_blend_sha256':M['module_blend_sha256'],'source_definitions':'source/module-definitions.json','source_definitions_sha256':M['definitions_sha256'],'frozen_source_scene_sha256':M['source_scene_sha256'],'source_is_actual_normalized_mesh':True,'coordinate_contract':{'length_unit':'metres','local_mesh_foot':[0,0,0],'ground_collision_plane':'module local z=0; flat receiving ground','full_frame_foot_pixel':[640,360],'full_frame_resolution_pixel':[1280,720],'camera_elevation_degrees':55,'pixel_density':{'ground_x':PX,'ground_y':PY,'height_z':PZ},'foot_relative_screen_pixel_formula':['x_px = 47.407407407407405 * x_m','y_px = -38.83387469221887 * y_m - 27.191771797382927 * z_m'],'full_frame_screen_formula':'[640,360] + foot_relative_screen_pixel','cropped_sprite_pixel_formula':'cropped_sprite_foot_pixel + foot_relative_screen_pixel, where cropped_sprite_foot_pixel = [640-crop_left,360-crop_top]. Crop coordinates do not change any metre-space or Godot-local collision vertex.','godot_local_world_formula':['x_world = 72.9344729345 * x_m','y_world = -59.7444226034 * y_m'],'godot_camera_zoom':.65,'collision_z_metres':0,'repeated_first_polygon_point':False,'winding':'outer CCW in metre XY; screen and Godot winding is reversed; holes if any CW in metre XY','instancing':'Add an instance XY metre translation to the local metre vertices; add its projected foot-relative pixel/Godot translation to the corresponding local coordinates. Do not reapply the source-scene rotation/scale or normalization translation. These were already baked.','foot_definition':'From the complete source mesh transformed by its original matrix_world: select vertices <= global minimum z + 0.30m; foot=(midpoint of selected x range, minimum selected y, global minimum z). Translate the entire module by -foot. For the arch both visual parts together are one module.','depth_reference':'Use the instance ground foot. For Godot Y-sort depth is -59.7444226034 * instance_ground_y_m. An arch or tall wall may require split visual layers/anchors for correct character occlusion.','character_radius':'Collision polygons include nominal 25mm asset margin, not the character radius. A .3m metre-space circle maps to an ellipse of radii [21.88034188035,17.92332678102] in Godot units. A same-radius Godot circle is not equivalent.','independent_module_coordinates':True},'generation':{'body_height_metres':HEIGHT,'validation_character_radius_metres':RADIUS,'method':'Clip actual normalized mesh triangles to the vertical body band; project to ground XY and union filled clipping-plane sections. Use a conservative convex hull for the scanned rock. Remove only low walkable sill inside the arch portal. Apply 8mm simplification, nominal 25mm outward buffer, and 1mm final simplification, then verify base containment.','script':'source/collision-work/build_collisions.py','extract_script':'source/collision-work/extract_modules.py','blender_version':M['blender_version'],'external_assets_downloaded':False,'source_saved_or_rendered_by_collision_work':False},'modules':objects,'portal_validation':portal,'verification':{'module_count':len(objects),'collision_polygon_count':sum(o['polygon_count'] for o in objects),'expected_polygon_count':4,'all_polygons_valid':all(g.IsValid() for g in final_geoms.values()),'all_base_footprints_covered_after_threshold_exemption':True,'arch_two_disjoint_blocking_legs':len(polys(gate))==2,'source_module_blend_hash_unchanged':hashlib.sha256((S/'modules.blend').read_bytes()).hexdigest()==M['module_blend_sha256'],'source_definitions_hash_unchanged':hashlib.sha256((S/'module-definitions.json').read_bytes()).hexdigest()==M['definitions_sha256'],'independent_serialized_qa_file':'source/collision-work/independent-verification.json','physics_engine_not_run':True,'assembled_layout_not_tested':True},'limitations':['Collision is a body-height ground occupancy projection, not a visible alpha contour or a full 3D collider.','Flat z=0 receiving ground only; terrain slopes, stairs other than the declared walkable sill, jumps, crouching, and taller/wider bodies need new validation.','The low sill is deliberately walkable. A 3D controller needs enough step height or an equivalent ramp; the mesh alone does not implement stepping.','Keep fixed orientation and scale. Translation-only instancing is supported.','Rock convex-hull filling is deliberately conservative and can extend beyond the nominal 25mm margin.','These are separate reusable modules; the assembled arrangement, collisions between placed instances, and visual occlusion/Y-sort require separate testing.']}
assert out['verification']['collision_polygon_count']==4 and out['verification']['source_module_blend_hash_unchanged'] and out['verification']['source_definitions_hash_unchanged']
(R/'exports'/'collisions.json').write_text(json.dumps(out,ensure_ascii=False,indent=2))
(W/'verification.json').write_text(json.dumps({'verification':out['verification'],'portal_validation':portal},ensure_ascii=False,indent=2))
(W/'base-geometries.json').write_text(json.dumps({k:{'base_wkt':g.ExportToWkt(),'raw_wkt':raw_geoms[k].ExportToWkt(),'final_wkt':final_geoms[k].ExportToWkt()} for k,g in base_geoms.items()},indent=2))
print(json.dumps({'verification':out['verification'],'portal_validation':portal},ensure_ascii=False,indent=2))
