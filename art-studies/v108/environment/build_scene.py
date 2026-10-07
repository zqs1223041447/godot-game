"""Reproducible environment study. All hero/scatter meshes are imported CC0 Poly Haven data.
Blender 4.3.2, run with --background --disable-autoexec --threads 4.
"""
import bpy, bmesh, math, random, json, sys
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.noise import noise_vector, noise
R=Path(__file__).resolve().parent
random.seed(108)
bpy.ops.wm.read_factory_settings(use_empty=True)
s=bpy.context.scene
s.unit_settings.system='METRIC';s.unit_settings.scale_length=1
s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=192;s.cycles.use_denoising=False
s.cycles.use_adaptive_sampling=True;s.cycles.adaptive_threshold=.02
s.cycles.max_bounces=6;s.cycles.diffuse_bounces=3;s.cycles.glossy_bounces=3;s.cycles.transparent_max_bounces=8
s.render.threads_mode='FIXED';s.render.threads=4
s.render.resolution_x=1280;s.render.resolution_y=720;s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGB'
s.view_settings.view_transform='AgX';s.view_settings.look='AgX - Medium High Contrast';s.view_settings.exposure=.25
s.world=bpy.data.worlds.new('Cool open-sky fill');s.world.use_nodes=True
s.world.node_tree.nodes['Background'].inputs[0].default_value=(.39,.52,.72,1)
s.world.node_tree.nodes['Background'].inputs[1].default_value=.72
# Collections are explicit so each reusable module remains inspectable.
def coll(name):
 c=bpy.data.collections.new(name);s.collection.children.link(c);return c
architecture=coll('01 • Poly Haven authored fort modules');nature=coll('02 • Poly Haven scanned rocks and fern clusters');terrain=coll('03 • Layered terrain and worn stone approach');lighting=coll('04 • Camera and lighting')
def move(o,c):
 for old in list(o.users_collection):old.objects.unlink(o)
 c.objects.link(o)
def import_asset(asset):
 before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(R/'assets'/asset/(f'{asset}_selected.gltf' if asset=='tree_small_02' else f'{asset}_1k.gltf')))
 return [o for o in bpy.data.objects if o not in before and o.type=='MESH']
fort=import_asset('modular_fort_01');rock=import_asset('rock_moss_set_01');fern=import_asset('fern_02');shrubs=import_asset('shrub_02');grasses=import_asset('grass_bermuda_01');trees=import_asset('tree_small_02')
# Keep source meshes as data; remove all stock display-grid transforms.
for o in fort+rock+fern+shrubs+grasses+trees:
 center=Vector(((min(v[0] for v in o.bound_box)+max(v[0] for v in o.bound_box))/2,(min(v[1] for v in o.bound_box)+max(v[1] for v in o.bound_box))/2,min(v[2] for v in o.bound_box)))
 o.data.transform(Matrix.Translation(-center));o.location=(0,0,0);o.rotation_euler=(0,0,0);o.scale=(1,1,1)
 o.hide_render=True;o.hide_set(True)
# Gentle limestone grading preserves the authored trim maps and UVs.
for mat in bpy.data.materials:
 if not mat.use_nodes:continue
 nt=mat.node_tree;bs=next((n for n in nt.nodes if n.type=='BSDF_PRINCIPLED'),None)
 if not bs:continue
 if mat.name.startswith('modular_fort'):
  old=bs.inputs['Base Color'].links[0].from_socket if bs.inputs['Base Color'].is_linked else None
  if old:
   mix=nt.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;mix.inputs[2].default_value=(1.47,1.37,1.17,1);nt.links.new(old,mix.inputs[1]);nt.links.new(mix.outputs[0],bs.inputs['Base Color'])
  for n in nt.nodes:
   if n.type=='NORMAL_MAP':n.inputs['Strength'].default_value=.72
 if mat.name.startswith(('fern_02','shrub_02','grass_bermuda_01')):
  plant_asset=next(a for a in ['fern_02','shrub_02','grass_bermuda_01'] if mat.name.startswith(a))
  im=nt.nodes.new('ShaderNodeTexImage');im.image=bpy.data.images.load(str(R/'assets'/plant_asset/'textures'/f'{plant_asset}_alpha_1k.png'));im.image.colorspace_settings.name='Non-Color';nt.links.new(im.outputs['Color'],bs.inputs['Alpha'])
  bs.inputs['Roughness'].default_value=.65
  if 'Subsurface Weight' in bs.inputs:bs.inputs['Subsurface Weight'].default_value=.055

for mat in bpy.data.materials:
 if mat.name.startswith('tree_small_02_leaves'):
  nt=mat.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
  im=nt.nodes.new('ShaderNodeTexImage');im.image=bpy.data.images.load(str(R/'assets/tree_small_02/textures/tree_small_02_leaves_alpha_1k.png'));im.image.colorspace_settings.name='Non-Color';nt.links.new(im.outputs['Color'],bs.inputs['Alpha']);bs.inputs['Roughness'].default_value=.68
def terrain_z(x,y):
 # Nearly level traversal plane, soft landforms only along edges.
 edge=min(1,max(0,(abs(x)-3)/5))
 return .018*math.sin(x*.71+y*.37)+.027*noise(Vector((x*.5,y*.5,3)))+edge*(.22+.18*math.sin(y*.8+x*.3))
def inst(src,name,xyz,scale=1,rz=0,c=nature):
 o=bpy.data.objects.new(name,src.data);c.objects.link(o);o.location=xyz;o.scale=(scale,)*3 if isinstance(scale,(int,float)) else scale;o.rotation_euler[2]=math.radians(rz)
 o['source_asset']=src.name;o['license']='CC0 1.0';return o
lookup={o.name:o for o in fort}
def wall(key,name,xy,scale,rot):return inst(lookup['modular_fort_01_'+key],name,(xy[0],xy[1],terrain_z(*xy)-.04),scale,rot,architecture)
# Focal gate is the original authored arch, enlarged horizontally to a practical opening.
gate=wall('wall_thin_gate_01','Hero arch • authored gate • worn crown',(1.75,4.45),(.48,.75,.49),90-7)
# Real mesh damage, retaining source materials. No procedural replacement arch.
bpy.context.view_layer.objects.active=gate;gate.select_set(True);gate.data=gate.data.copy();bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);gate.select_set(False)
for i,(x,y,z,sca) in enumerate([(4.2,4.3,4.0,(1.12,2.0,.85)),(-.72,4.72,4.0,(.85,2.0,.75)),(2.15,4.8,4.48,(1.38,2.0,.42))]):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=(x,y,z));cut=bpy.context.object;cut.scale=sca;cut.rotation_euler=(.2,.4,.7)
 mod=gate.modifiers.new('Small broken crown '+str(i),'BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cut;bpy.context.view_layer.objects.active=gate
 try:bpy.ops.object.modifier_apply(modifier=mod.name)
 except Exception:gate.modifiers.remove(mod)
 bpy.data.objects.remove(cut,do_unlink=True)
wall('wall_thin_straight_03','Low west wall • vegetation-softened edge',(-4.0,4.8),(.44,.57,.34),90-7)
wall('wall_thin_corner_03','West return • cropped environmental edge',(-7.25,6.1),(.48,.48,.41),-7)
wall('wall_thick_end_01','East broken buttress',(5.45,4.9),(.44,.44,.32),72)
# A modest fallen authored wall fragment grounds the ruin rather than adding invented blocks.
f=wall('wall_thin_straight_03','Fallen masonry section',(-5.7,.5),(.26,.22,.16),-21);f.rotation_euler[1]=math.radians(90);f.rotation_euler[0]=math.radians(8);f.location.x=-5.4;f.location.y=3.2;f.location.z=.05
bpy.context.view_layer.update();f.location.z+=terrain_z(f.location.x,f.location.y)-min((f.matrix_world@Vector(v)).z for v in f.bound_box)-.16
# Natural framing: few large scanned rocks, smaller offshoots, consistent world scale.
rock_layout=[(-7,-3.4,1.40,18),(-6.0,-3.9,.78,83),(-7.4,-1.3,1.05,164),(-4.1,3.3,.67,209),(-3.4,3.5,.38,318),(6.7,-2.0,1.08,38),(7.5,-3.6,1.2,155),(5.9,-3.3,.56,238),(5.8,2.9,.60,277),(4.5,4.5,.48,190),(-6.7,6.3,.70,0),(7.7,6.0,.77,182)]
for i,(x,y,sc,rot) in enumerate(rock_layout):inst(rock[i%len(rock)],f'Scanned moss rock {i+1:02d}',(x,y,terrain_z(x,y)-.10),sc,rot)
# Each plant is one of the four authored clumps, with linked data and varied placement.
plant_clusters=[(-7,-3.8,9,1.15),(-6,-.8,8,.8),(-6.0,4.2,9,.83),(-3.4,4.8,7,.61),(-1.9,4.4,5,.52),(5.0,4.55,8,.65),(7.2,3.4,9,.97),(7,-3.1,10,1.02),(5.6,-4.7,5,.78),(-7.8,7.5,9,.84),(5.2,7.2,8,.70)]
for group,(cx,cy,n,sc) in enumerate(plant_clusters):
 for i in range(n):
  ang=random.uniform(0,math.tau);rr=random.uniform(0,.85);x=cx+math.cos(ang)*rr;y=cy+math.sin(ang)*rr
  o=inst(fern[(group+i)%len(fern)],f'Fern cluster {group+1:02d} / {i+1:02d}',(x,y,terrain_z(x,y)-.018),sc*random.uniform(1.15,1.85),random.uniform(0,360))
# Two bounded, actual authored tree subsets frame the image, with an open middle.
# Reuse the downloaded authored leaf subset as rotated canopy clusters; the trunk stays single.
leafmesh=trees[0].data.copy();bm=bmesh.new();bm.from_mesh(leafmesh)
bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.material_index!=1],context='FACES');bm.to_mesh(leafmesh);bm.free()
for ti,(pos,sc,rot) in enumerate([((-11.4,-6.8,terrain_z(-11.4,-6.8)-.12),1.23,8),((9.5,7.2,terrain_z(9.5,7.2)-.12),1.05,155)]):
 inst(trees[0],f'Authored tree frame {ti}',pos,sc,rot)
 for j in range(1,6):
  canopy=bpy.data.objects.new(f'Authored leaf canopy cluster {ti}-{j}',leafmesh);nature.objects.link(canopy);canopy.location=pos;canopy.scale=(sc,sc,sc);canopy.rotation_euler[2]=math.radians(rot+j*60)

# Higher foliage groups give depth at the edges; the central corridor stays empty.
for i,(x,y,sc,rot) in enumerate([(-8.9,-5.6,1.6,18),(-9.1,-3.8,1.4,80),(-9.4,.9,1.5,120),(-8.7,6.8,1.5,210),(-6.4,7.1,1.2,11),(-3.8,6.7,1.1,74),(-1.55,4.75,.72,80),(4.9,4.4,.65,92),(6.1,6.4,1.1,31),(8.1,5.6,1.4,190),(8.9,1.7,1.35,180),(9.0,-4.6,1.55,55),(7.9,-5.8,1.05,77)]):
 inst(shrubs[i%4],f'Authored shrub edge {i:02d}',(x,y,terrain_z(x,y)-.10),sc,rot)
# Authored grass blades occur only in uneven banks at selected wall/rock roots.
for cx,cy,rad,n in [(-6.2,2.9,1.7,500),(-8,-3.9,1.8,650),(7.4,-3.6,1.9,650),(6.1,4.5,1.5,400),(-4.0,5.9,1.3,400),(8.9,1.4,1.4,350)]:
 for i in range(n):
  ang=random.uniform(0,math.tau);rr=rad*math.sqrt(random.random());x=cx+math.cos(ang)*rr;y=cy+math.sin(ang)*rr
  if noise(Vector((x*1.4,y*1.4,3)))<-.08:continue
  inst(grasses[3+i%10],f'Authored grass bank {cx} {i}',(x,y,terrain_z(x,y)-.005),random.uniform(1.35,2.8),random.uniform(0,360))
# Masonry left where wall sections broke; shape comes from the same authored kit.
for i,(x,y,rot) in enumerate([(-1.85,4.55,47),(-2.65,4.8,19),(4.8,4.95,61)]):
 f=wall('wall_thin_straight_03',f'Collapsed wall-root masonry {i}',(x,y),(.20,.13,.09),rot);f.rotation_euler[1]=math.radians(72)
 bpy.context.view_layer.update();f.location.z+=terrain_z(x,y)-min((f.matrix_world@Vector(v)).z for v in f.bound_box)-.12
# Ground texture blending is vertex-controlled; not a repeated mirror-tile map.
N=151;size=34;vs=[];faces=[];colors=[]
for j in range(N):
 y=-size/2+j*size/(N-1)
 for i in range(N):
  x=-size/2+i*size/(N-1);z=terrain_z(x,y);vs.append((x,y,z))
  no=noise(Vector((x*.54,y*.54,1.7)));no2=noise(Vector((x*1.3,y*1.3,4.1)))
  pathx=1.45+.45*math.sin(y*.42)-.21*(4-y)
  central=math.exp(-((x-pathx)/3.7)**4)*math.exp(-((y+.3)/7.2)**8)
  grass=max(0,min(1,.84-central*.77+no*.40))
  gravel=max(0,min(1,.20+no*.6+no2*.2))*(1-grass*.7)
  stone=max(0,min(1,(1.18+no*.23-abs(x-pathx))/.35))*max(0,min(1,(y+.35)/1.0))*max(0,min(1,(8-y)/1.8))
  stone*=max(0,min(1,.68+no2*1.2))
  colors.append((grass,gravel,stone,1))
for j in range(N-1):
 for i in range(N-1):
  k=j*N+i;faces.append((k,k+1,k+1+N,k+N))
me=bpy.data.meshes.new('Soft terrain surface 1m units');me.from_pydata(vs,[],faces);me.update();o=bpy.data.objects.new('Terrain • soil / grass / gravel + local old path',me);terrain.objects.link(o)
for p in me.polygons:p.use_smooth=True
att=me.color_attributes.new(name='GroundMasks',type='FLOAT_COLOR',domain='POINT')
for i,c in enumerate(colors):att.data[i].color=c
m=bpy.data.materials.new('Layered scanned ground • quiet traversal zone');m.use_nodes=True;nt=m.node_tree;nt.nodes.clear();out=nt.nodes.new('ShaderNodeOutputMaterial');bs=nt.nodes.new('ShaderNodeBsdfPrincipled');bs.inputs['Roughness'].default_value=.89;nt.links.new(bs.outputs[0],out.inputs[0]);o.data.materials.append(m)
geo=nt.nodes.new('ShaderNodeNewGeometry');attr=nt.nodes.new('ShaderNodeVertexColor');attr.layer_name='GroundMasks';sep=nt.nodes.new('ShaderNodeSeparateColor');nt.links.new(attr.outputs['Color'],sep.inputs[0])
def mulvec(socket,scale):
 n=nt.nodes.new('ShaderNodeVectorMath');n.operation='SCALE';n.inputs['Scale'].default_value=scale;nt.links.new(socket,n.inputs[0]);return n.outputs[0]
def image_tex(asset,suffix,vec,non=False):
 n=nt.nodes.new('ShaderNodeTexImage');n.image=bpy.data.images.load(str(R/'assets'/asset/f'{asset}_{suffix}_1k.jpg'),check_existing=True);n.extension='REPEAT';nt.links.new(vec,n.inputs['Vector'])
 if non:n.image.colorspace_settings.name='Non-Color'
 return n.outputs['Color']
def multiply(sock,color):
 n=nt.nodes.new('ShaderNodeMixRGB');n.blend_type='MULTIPLY';n.inputs[0].default_value=1;n.inputs[2].default_value=(*color,1);nt.links.new(sock,n.inputs[1]);return n.outputs[0]
def blend(a,b,factor):
 n=nt.nodes.new('ShaderNodeMixRGB');nt.links.new(a,n.inputs[1]);nt.links.new(b,n.inputs[2]);nt.links.new(factor,n.inputs[0]);return n.outputs[0]
soilv=mulvec(geo.outputs['Position'],.31);gravelv=mulvec(geo.outputs['Position'],.48);grassv=mulvec(geo.outputs['Position'],.085);stonev=mulvec(geo.outputs['Position'],.50)
soil=image_tex('forest_ground_04','diff',soilv);soil=multiply(soil,(1.10,1.09,1.02))
gravel=image_tex('forest_ground_04','diff',gravelv);gravel=multiply(gravel,(1.25,1.25,1.18))
grass=image_tex('aerial_grass_rock','diff',grassv);grass=multiply(grass,(.48,.84,.67))
stone=image_tex('medieval_blocks_05','diff',stonev);stone=multiply(stone,(1.05,1.04,.98))
col=blend(soil,gravel,sep.outputs['Green']);col=blend(col,grass,sep.outputs['Red']);col=blend(col,stone,sep.outputs['Blue']);nt.links.new(col,bs.inputs['Base Color'])
soiln=image_tex('forest_ground_04','nor_gl',soilv,True);grassn=image_tex('aerial_grass_rock','nor_gl',grassv,True);stonen=image_tex('medieval_blocks_05','nor_gl',stonev,True)
norcol=blend(soiln,grassn,sep.outputs['Red']);norcol=blend(norcol,stonen,sep.outputs['Blue']);normal=nt.nodes.new('ShaderNodeNormalMap');normal.space='WORLD';normal.inputs['Strength'].default_value=.55;nt.links.new(norcol,normal.inputs['Color']);nt.links.new(normal.outputs[0],bs.inputs['Normal'])
# Larger scanned chips close to the ruin gradually transition to fine ground gravel.
for i in range(48):
 x=random.uniform(-6.8,7.2);y=random.uniform(.7,6)
 if abs(x-1.4)<2.1 and y<4.7:continue
 sc=random.uniform(.07,.22);inst(rock[i%len(rock)],f'Loose scanned rubble {i:02d}',(x,y,terrain_z(x,y)-.025),sc,random.uniform(0,360))
# Lighting: warm key from camera-left, cool sky fill, gentle broad bounce.
def light(name,typ,loc,energy,color,size=0):
 d=bpy.data.lights.new(name,typ);d.energy=energy;d.color=color;o=bpy.data.objects.new(name,d);lighting.objects.link(o);o.location=loc
 if typ=='AREA':d.shape='DISK';d.size=size;o.rotation_euler=(Vector((0,2,0))-o.location).to_track_quat('-Z','Y').to_euler()
 return o
sun=light('Warm afternoon sun','SUN',(-8,-6,14),3.0,(1.0,.89,.72));sun.rotation_euler=(math.radians(37),math.radians(-39),math.radians(-35));sun.data.angle=math.radians(6)
light('Cool soft environment bounce','AREA',(2,-2,14),650,(.68,.81,1),15)
# This is exactly 55 degrees above the horizontal ground plane.
cdata=bpy.data.cameras.new('Orthographic 55-degree gameplay camera');cam=bpy.data.objects.new('Camera • 55° elevation • 27m wide',cdata);lighting.objects.link(cam)
target=Vector((0,.8,.35));dist=20;cam.location=target+Vector((0,-dist,dist*math.tan(math.radians(55))));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cdata.type='ORTHO';cdata.ortho_scale=27;cdata.lens=50;s.camera=cam
# Hidden technical guides are not part of the beauty image.
guides=coll('05 • World-scale reference guides • hidden in render')
for name,loc,scale in [('Clear traversal area • approx 8m x 6m',(0,-.6,.1),(4,3,.05)),('Standing hero reference • 1.8m tall',(0,-.7,.9),(.3,.3,.9))]:
 bpy.ops.object.empty_add(type='CUBE',location=loc);e=bpy.context.object;e.name=name;e.scale=scale;move(e,guides);e.hide_render=True
for obj in fort+rock+fern+shrubs+grasses+trees:bpy.data.objects.remove(obj,do_unlink=True)
# Make it self-contained; source files and verified original manifests are also delivered separately.
s['sample_purpose']='Environment-only art proof; not integrated into the published game or collision map.'
s['world_scale']='1 Blender unit = 1 metre. Orthographic view 27m wide. Hero scale reference 1.8m.'
s['license']='Source assets by Poly Haven contributors, CC0 1.0. See SOURCES.md.'
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(R/'sunlit-ruins-environment.blend'))
if '--preview' in sys.argv:s.render.resolution_percentage=65;s.cycles.samples=40
s.render.filepath=str(R/'renders'/('environment-preview.png' if '--preview' in sys.argv else 'sunlit-ruins-1280x720.png'))
bpy.ops.render.render(write_still=True)
# Camera and triangle statistics are machine-readable for review.
stat={'camera_elevation_degrees':55,'resolution':[s.render.resolution_x,s.render.resolution_y],'ortho_width_metres':27,'source_meshes':{'fort':len(fort),'rocks':len(rock),'ferns':len(fern)},'visible_mesh_objects':sum(o.type=='MESH' and not o.hide_render for o in s.objects),'render_engine':'Blender 4.3.2 Cycles CPU','threads':4,'samples':s.cycles.samples,'denoising':False,'world_units':'metres','not_integrated_into_game':True}
(R/'scene-verification.json').write_text(json.dumps(stat,indent=2))
