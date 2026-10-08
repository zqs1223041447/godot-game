"""Independent read-only verification of the loaded Ranger scene. Never saves the blend."""
import bpy,json,math,numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
s=bpy.context.scene
s.frame_set(1)
bpy.context.view_layer.update()
dg=bpy.context.evaluated_depsgraph_get()
char=[o for o in bpy.data.objects if o.type=='MESH' and o.parent and o.parent.type=='ARMATURE']
def evaluated(o):
 ev=o.evaluated_get(dg); me=ev.to_mesh(); me.calc_loop_triangles(); V=np.array([tuple(ev.matrix_world@v.co) for v in me.vertices]); F=np.array([tuple(t.vertices) for t in me.loop_triangles]); ev.to_mesh_clear();return V,F
meshes={o.name:evaluated(o) for o in char}
H,HF=meshes[next(n for n in meshes if n.startswith('Hair_BuzzedFemale'))]
C,CF=meshes[next(n for n in meshes if n.startswith('Female_Ranger_Head_Hood'))]
def edge_triangle_hits(EV,EF,TV,TF):
 edges=np.unique(np.sort(np.concatenate([EF[:,[0,1]],EF[:,[1,2]],EF[:,[2,0]]]),axis=1),axis=0); tris=TV[TF]; e1=tris[:,1]-tris[:,0];e2=tris[:,2]-tris[:,0];hits=[]
 for ix in edges:
  o,d=EV[ix[0]],EV[ix[1]]-EV[ix[0]];h=np.cross(d,e2);det=np.einsum('ij,ij->i',e1,h);good=abs(det)>1e-12; inv=np.divide(1.,det,out=np.zeros(len(det)),where=good);ss=o-tris[:,0];u=inv*np.einsum('ij,ij->i',ss,h);q=np.cross(ss,e1);v=inv*np.einsum('j,ij->i',d,q);t=inv*np.einsum('ij,ij->i',e2,q);valid=good&(u>=-1e-8)&(v>=-1e-8)&(u+v<=1+1e-8)&(t>=-1e-8)&(t<=1+1e-8)
  for j in np.flatnonzero(valid):hits.append({'edge':ix.tolist(),'triangle':int(j),'position':(o+t[j]*d).tolist()})
 points=np.array([h['position'] for h in hits]); visible_hits=[h for h in hits if bvh.ray_cast(Vector(h['position'])+camdir*1e-4,camdir,10.)[0] is None]; direct_visible=len(visible_hits)
 return {'edges_tested':len(edges),'triangles_tested':len(TF),'hits':len(hits),'intersection_bounds':{'min':points.min(axis=0).tolist(),'max':points.max(axis=0).tolist()} if hits else None,'intersections_not_occluded_by_outfit_from_saved_camera':direct_visible,'intersections_not_occluded_by_any_character_mesh_from_saved_camera':sum(all_bvh.ray_cast(Vector(h['position'])+camdir*1e-4,camdir,10.)[0] is None for h in hits),'not_occluded_examples':visible_hits[:10],'examples':hits[:10]}
head=next(o for o in char if o.name=='Female_Base_Head_Neck_Only');V,F=meshes[head.name]
# Weld only an analysis-only topology array, never scene geometry.
rest=np.array([tuple(v.co) for v in head.data.vertices]);_,unique_idx,inv=np.unique(np.round(rest,5),axis=0,return_index=True,return_inverse=True); ff=inv[F];ed=np.sort(np.concatenate([ff[:,[0,1]],ff[:,[1,2]],ff[:,[2,0]]]),axis=1);un,cnt=np.unique(ed,axis=0,return_counts=True);boundary=un[cnt==1];cut=boundary[np.max(rest[unique_idx[boundary]][:,:,2],axis=1)<1.5]
seam_samples=[]
for edge in cut:
 a,b=V[unique_idx[edge]]
 for t in [0.,.25,.5,.75]:seam_samples.append(a*(1-t)+b*t)
# Test actual cut-ring visibility through all outfit geometry from the scene view and eight azimuths.
RV=[];RF=[]
for n,(v,f) in meshes.items():
 if not n.startswith('Female_Ranger_'):continue
 RF.extend((f+len(RV)).tolist());RV.extend(v.tolist())
bvh=BVHTree.FromPolygons(RV,RF,all_triangles=True)
AV=[];AF=[]
for v,f in meshes.values():
 AF.extend((f+len(AV)).tolist());AV.extend(v.tolist())
all_bvh=BVHTree.FromPolygons(AV,AF,all_triangles=True)
def visibility(d):
 d=Vector(d).normalized();visible=[]
 for idx,p in enumerate(seam_samples):
  origin=Vector(p)+d*1e-5; hit=bvh.ray_cast(origin,d,10.)
  if hit[0] is None:visible.append(idx)
 return {'samples':len(seam_samples),'not_occluded_by_outfit':len(visible),'sample_indices':visible}
cam=s.camera;camdir=cam.rotation_euler.to_matrix()@Vector((0,0,1));views={'saved_camera':visibility(camdir)}
for a in range(0,360,45):
 r=math.radians(a);el=math.radians(55);views[str(a)+'deg_55elev']=visibility((math.sin(r)*math.cos(el),math.cos(r)*math.cos(el),math.sin(el)))
# Check the actual evaluated pose differs from its original mesh and that rigs stay synchronized.
pose_stats={}
for o in char:
 vv,_=meshes[o.name];orig=np.array([tuple(o.matrix_world@v.co) for v in o.data.vertices]);diff=np.linalg.norm(vv-orig,axis=1);pose_stats[o.name]={'vertex_count':len(vv),'max_vertex_displacement_metres':float(diff.max()),'rms_displacement_metres':float(np.sqrt(np.mean(diff**2)))}
rigs=[o for o in bpy.data.objects if o.type=='ARMATURE'];reference=rigs[0];rig_errors={}
for rig in rigs:
 rig_errors[rig.name]=max(abs(reference.pose.bones[b.name].matrix[i][j]-rig.pose.bones[b.name].matrix[i][j]) for b in reference.data.bones for i in range(4) for j in range(4))
curves=[]
for a in bpy.data.actions:
 for f in a.fcurves:
  values=[k.co.y for k in f.keyframe_points]
  if values:curves.append({'action':a.name,'path':f.data_path,'component':f.array_index,'sample_variation':max(values)-min(values)})
rep={'blend_file':bpy.data.filepath,'frame':s.frame_current,'hair_vs_hood':edge_triangle_hits(H,HF,C,CF),'hood_vs_hair':edge_triangle_hits(C,CF,H,HF),'head_vs_hood':edge_triangle_hits(V,F,C,CF),'hood_vs_head':edge_triangle_hits(C,CF,V,F),'cut_ring_edges':len(cut),'cut_ring_visibility':views,'evaluated_pose_displacements':pose_stats,'rig_pose_matrix_errors':rig_errors,'actions':{'curve_count':len(curves),'varying_curve_count':sum(x['sample_variation']>1e-7 for x in curves),'max_curve_variation':max([x['sample_variation'] for x in curves],default=0)},'limits':['Ray tests only sample the retained neck boundary against outfit triangles; they are not a continuous visibility proof or a complete intersection certificate.','An intentionally authored static pose can be valid with zero varying animation curves.','No render or scene save performed.']}
(ROOT/'reports/independent-geometry-verification.json').write_text(json.dumps(rep,indent=2));print(json.dumps(rep,indent=2))
