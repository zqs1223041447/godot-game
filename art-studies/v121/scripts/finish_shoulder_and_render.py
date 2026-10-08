"""One bounded shoulder-lining correction on the saved STATIC study.
Run: blender --background --disable-autoexec ranger-sample.blend --python scripts/finish_shoulder_and_render.py
No source garment/body vertices, bindings, weights, bone transforms, or source textures change.
This three-dimensional underlay is pose-specific and is NOT animation-ready.
"""
import bpy,bmesh,json,math,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
R=Path(__file__).resolve().parents[1];s=bpy.context.scene
report=json.loads((R/'reports/assembly-report.json').read_text());p=report['pose']
center=Vector([(a+b)/2 for a,b in zip(p['min'],p['max'])]);el=math.radians(55)
right=Vector((1,0,0));up=Vector((0,math.sin(el),math.cos(el)));toward=Vector((0,-math.cos(el),math.sin(el)))
name='Static_Shoulder_Lining_Bridge'
def sha(data):return hashlib.sha256(json.dumps(data,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def signatures():
 out={}
 for o in bpy.data.objects:
  if o.type=='ARMATURE':
   out[o.name]=sha({'bones':[(b.name,b.parent.name if b.parent else None,[list(row) for row in b.matrix_local]) for b in o.data.bones], 'pose':[(b.name,[list(row) for row in b.matrix_basis]) for b in o.pose.bones]})
  elif o.type=='MESH' and o.parent and o.parent.type=='ARMATURE':
   out[o.name]=sha({'verts':[list(v.co) for v in o.data.vertices],'faces':[list(f.vertices) for f in o.data.polygons],'weights':[[(g.group,g.weight) for g in v.groups] for v in o.data.vertices],'groups':[g.name for g in o.vertex_groups],'modifiers':[(m.name,m.type,getattr(getattr(m,'object',None),'name',None)) for m in o.modifiers]})
 return out
before=signatures()
if name not in bpy.data.objects:
 # Endpoints follow the real chest surface and real raised pauldron rim. The
 # strip bows 3.5mm inward between these attachments, becoming a small gusset.
 # Pixel selections identify geometry only; final vertices are real world-space
 # ray/surface intersections, not a billboard or an image patch.
 rows=[(360,706,722),(364,708,722),(368,706,720),(372,704,718),
       (376,700,716),(380,698,714),(384,694,712),(388,690,708),
       (392,688,706),(396,684,704),(400,680,702),(404,678,700),
       (408,676,696),(412,672,694),(416,670,690),(420,668,680),
       (424,664,676),(428,658,672),(432,654,670)]
 dg=bpy.context.evaluated_depsgraph_get();bvhs={}
 for objname in ['Female_Ranger_Body','Female_Ranger_Acc_Pauldrons']:
  o=bpy.data.objects[objname];ev=o.evaluated_get(dg);m=ev.to_mesh();m.calc_loop_triangles()
  bvhs[objname]=BVHTree.FromPolygons([ev.matrix_world@v.co for v in m.vertices],[tuple(t.vertices) for t in m.loop_triangles],all_triangles=True);ev.to_mesh_clear()
 def cast(x,y,objname):
  plane=center+right*((x+.5-600)*2.10/1200)+up*((600-y-.5)*2.10/1200)
  loc,n,idx,dist=bvhs[objname].ray_cast(plane+toward*10,-toward,100)
  assert loc is not None,(x,y,objname)
  return loc
 verts=[];faces=[];endpoints=[];across=7
 for row,(y,xleft,xright) in enumerate(rows):
  a=cast(xleft,y,'Female_Ranger_Body');b=cast(xright,y,'Female_Ranger_Acc_Pauldrons')
  endpoints.append({'left_pixel':[xleft,y],'right_pixel':[xright,y],'chest_world':list(a),'pauldron_world':list(b),'span_m':(a-b).length})
  for j in range(across):
   t=j/(across-1);v=a.lerp(b,t)-toward*(.0012+.0035*math.sin(math.pi*t))
   # Ends turn down slightly beneath the existing geometry, avoiding an exposed cap.
   if row in [0,len(rows)-1]:v-=toward*.0025
   verts.append(v)
 for row in range(len(rows)-1):
  for j in range(across-1):
   a=row*across+j;b=a+1;c=a+across+1;d=a+across
   face=(a,b,c,d)
   if (verts[b]-verts[a]).cross(verts[d]-verts[a]).dot(toward)<0:face=tuple(reversed(face))
   faces.append(face)
 assembly=bpy.data.objects['Ranger_Sample_Assembly'];inv=assembly.matrix_world.inverted()
 me=bpy.data.meshes.new('Pose-specific shoulder gusset mesh');me.from_pydata([inv@v for v in verts],[],faces);me.update()
 ob=bpy.data.objects.new(name,me);s.collection.objects.link(ob);ob.parent=assembly
 for f in me.polygons:f.use_smooth=True
 mat=bpy.data.materials.new('Sample olive shoulder lining');mat.use_nodes=True;nt=mat.node_tree;bs=nt.nodes.get('Principled BSDF')
 bs.inputs['Base Color'].default_value=(.067,.083,.031,1);bs.inputs['Roughness'].default_value=.90;bs.inputs['Specular IOR Level'].default_value=.18
 tex=nt.nodes.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=650;tex.inputs['Detail'].default_value=2
 bump=nt.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.16;bump.inputs['Distance'].default_value=.0003;nt.links.new(tex.outputs['Fac'],bump.inputs['Height']);nt.links.new(bump.outputs['Normal'],bs.inputs['Normal']);ob.data.materials.append(mat)
 solid=ob.modifiers.new('Submillimetre lining thickness','SOLIDIFY');solid.thickness=.0007;solid.offset=-1
 ob['purpose']='Pose-specific local shoulder lining; not animated, not skinned';ob['authorization_scope']='One static study correction only'
 bpy.context.view_layer.update();after=signatures();assert before==after
 fix={'correction_rounds':1,'diagnosis':'Original sparse rays hit deep inner sleeve/pauldron surfaces, but expanded focused grid also detected small genuine outfit openings near the inner shoulder. The static lining bridges both the real opening and the over-deep black transition.',
      'method':'Small curved world-space lining, surface-attached below original chest and raised pauldron rim; all original geometry/rig/weights unchanged.',
      'object':name,'vertices':len(verts),'quads':len(faces),'attachment_samples':endpoints,'bounds_world':{'min':[min(v[i] for v in verts) for i in range(3)],'max':[max(v[i] for v in verts) for i in range(3)]},
      'original_character_signatures_before':before,'original_character_signatures_after':after,'original_character_unchanged':before==after,
      'full_base_restored':False,'pose_specific_unskinned_addition':True,'limits':['This small underlay is for the current static pose only. It has no animation/retarget/weight validation.','No global garment redesign or shoulder armour movement was done.']}
 (R/'reports/shoulder-correction-report.json').write_text(json.dumps(fix,indent=2))
else:
 assert (R/'reports/shoulder-correction-report.json').exists(),'Do not silently duplicate or replace a correction'
 print('Existing one-round lining retained; render-only rerun.',flush=True)
cam=s.camera;ground=bpy.data.objects['Sample Neutral Ground'];char=[o for o in bpy.data.objects if o.type=='MESH' and o!=ground]
for o in char:o.visible_camera=True
s.render.engine='CYCLES';s.cycles.device='CPU';s.render.threads_mode='FIXED';s.render.threads=8;s.cycles.use_denoising=False;s.cycles.use_adaptive_sampling=True;s.cycles.adaptive_threshold=.025;s.cycles.seed=121
s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA';s.render.image_settings.color_depth='8'
def camera(target,width,W,H):
 target=Vector(target);cam.location=target+Vector((0,-20,20*math.tan(el)));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=width;s.render.resolution_x=W;s.render.resolution_y=H;s.render.resolution_percentage=100;bpy.context.view_layer.update()
# Save a convenient original-scale scene, with ordinary geometry visibility restored.
camera((0,0,0),27,1280,720);ground.hide_render=False;ground.is_shadow_catcher=False;s.render.film_transparent=False;s.cycles.samples=192
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(R/'ranger-sample.blend'),compress=True)
camera(center,2.10,1200,1200);s.render.filepath=str(R/'renders/ranger-quality.png');bpy.ops.render.render(write_still=True);print('QUALITY_RECHECK_READY',flush=True)
camera((0,0,0),27,1280,720);ground.hide_render=True;s.render.film_transparent=True;s.cycles.samples=96;s.render.filepath=str(R/'renders/ranger-actual-body.png');bpy.ops.render.render(write_still=True)
ground.hide_render=False;ground.is_shadow_catcher=True
for o in char:o.visible_camera=False
s.cycles.samples=128;s.render.filepath=str(R/'renders/ranger-actual-shadow-raw.png');bpy.ops.render.render(write_still=True)
print('ONE_ROUND_CORRECTION_RENDERS_COMPLETE',flush=True)
