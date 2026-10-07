import bpy, math, random, json, os, sys
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
from math import sin, cos, pi
OUT=os.path.dirname(os.path.abspath(__file__))
SEED=10573
random.seed(SEED)
DEG=55.0
S=sin(math.radians(DEG)); C=cos(math.radians(DEG)); WU=20.0
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for datablocks in (bpy.data.materials,bpy.data.meshes,bpy.data.curves,bpy.data.cameras):
    for d in list(datablocks):
        if d.users==0: datablocks.remove(d)
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.device='CPU'; scene.cycles.samples=72; scene.cycles.use_denoising=False
scene.cycles.max_bounces=7; scene.cycles.diffuse_bounces=4; scene.cycles.transparent_max_bounces=8
scene.render.image_settings.file_format='PNG'; scene.render.image_settings.color_mode='RGBA'; scene.render.image_settings.color_depth='8'
scene.render.film_transparent=True
scene.render.resolution_percentage=100
scene.render.threads_mode='FIXED'; scene.render.threads=5
scene.world.color=(.3,.3,.3)
scene.world.use_nodes=True; scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.71,.78,.72,1); scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.32
scene.view_settings.view_transform='AgX'; scene.view_settings.look='AgX - Medium High Contrast'; scene.view_settings.exposure=0.0

# All source geometry and materials are authored here, with a reproducible seed.
def mat(name,color,rough=.8,noise=0,bump=.06,metal=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    n=m.node_tree.nodes; l=m.node_tree.links; p=n.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1); p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
    if noise:
        tex=n.new('ShaderNodeTexNoise'); tex.inputs['Scale'].default_value=noise; tex.inputs['Detail'].default_value=4; tex.inputs['Roughness'].default_value=.7
        ramp=n.new('ShaderNodeValToRGB'); ramp.color_ramp.elements[0].position=.18; ramp.color_ramp.elements[0].color=(*(v*.66 for v in color),1); ramp.color_ramp.elements[1].position=.8; ramp.color_ramp.elements[1].color=(*(min(v*1.22,1) for v in color),1)
        l.new(tex.outputs['Fac'],ramp.inputs['Fac']); l.new(ramp.outputs['Color'],p.inputs['Base Color'])
        b=n.new('ShaderNodeBump'); b.inputs['Strength'].default_value=.23; b.inputs['Distance'].default_value=bump; l.new(tex.outputs['Fac'],b.inputs['Height']); l.new(b.outputs['Normal'],p.inputs['Normal'])
    return m
sand=[mat('Warm sandstone %02d'%i,(.43+i*.025,.38+i*.024,.29+i*.018),noise=5,bump=.07) for i in range(5)]
cap=mat('Pale worn limestone cap',(.61,.56,.43),noise=6,bump=.045)
mortar=mat('Earthy recessed mortar',(.22,.23,.16),noise=9,bump=.05)
moss=[mat('Moss velvet %d'%i,(.12+i*.03,.21+i*.03,.056+i*.018),noise=12,bump=.025) for i in range(3)]
soil=mat('Dark garden soil',(.13,.09,.045),noise=13,bump=.08)
bronze=mat('Aged copper botanical inset',(.28,.22,.105),rough=.6,noise=7,bump=.015,metal=.55)
bark=mat('Silver grey ginkgo bark',(.25,.22,.16),noise=9,bump=.09)
# Add anisotropic procedural bark ridges.
n=bark.node_tree.nodes; l=bark.node_tree.links; t=n.new('ShaderNodeTexNoise');t.inputs['Scale'].default_value=3;t.inputs['Detail'].default_value=3
coord=n.new('ShaderNodeTexCoord'); mapping=n.new('ShaderNodeVectorMath');mapping.operation='MULTIPLY';mapping.inputs[1].default_value=(5,5,.65);l.new(coord.outputs['Generated'],mapping.inputs[0]);l.new(mapping.outputs['Vector'],t.inputs['Vector'])
b=n.new('ShaderNodeBump');b.inputs['Strength'].default_value=.55;b.inputs['Distance'].default_value=.1;l.new(t.outputs['Fac'],b.inputs['Height']);l.new(b.outputs['Normal'],n.get('Principled BSDF').inputs['Normal'])
leaf_colors=[(.15,.27,.018),(.23,.36,.035),(.38,.44,.045),(.58,.47,.055),(.64,.54,.09),(.30,.40,.04)]
leaves=[]
for i,color in enumerate(leaf_colors):
    m=mat('Ginkgo fan leaf %d'%i,color,.65)
    n=m.node_tree.nodes;l=m.node_tree.links; p=n.get('Principled BSDF');out=n.get('Material Output'); tr=n.new('ShaderNodeBsdfTranslucent');tr.inputs[0].default_value=(*color,1);mix=n.new('ShaderNodeMixShader');mix.inputs[0].default_value=.19;l.new(p.outputs[0],mix.inputs[1]);l.new(tr.outputs[0],mix.inputs[2]);l.new(mix.outputs[0],out.inputs['Surface']);leaves.append(m)
grassmat=mat('Herb leaves muted green',(.14,.32,.12),.8)
petals=[mat('Small flower cream',(.86,.78,.51),.65),mat('Small flower cornflower',(.33,.44,.55),.65),mat('Small flower warm gold',(.72,.48,.11),.65)]

collections={}
def coll(name):
    c=bpy.data.collections.new(name);scene.collection.children.link(c);collections[name]=c;return c
wall_c=coll('WALL_96x64_H70');bed_c=coll('GARDEN_PLINTH_160x120_H45');tree_c=coll('GINKGO_BASE_80x80_H180');stage_c=coll('SHOWCASE_ONLY');rig_c=coll('CAMERA_AND_LIGHT_RIG')
active=wall_c

def relocate(obj):
    for c in list(obj.users_collection): c.objects.unlink(obj)
    active.objects.link(obj)

def mesh_obj(name,verts,faces,mats,indices=None,smooth=False):
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);active.objects.link(o)
    for m in mats:me.materials.append(m)
    for p in me.polygons:
        p.use_smooth=smooth
        if indices:p.material_index=indices[p.index]
    return o

def box(name,loc,dims,material,bevel=.04,rough=0):
    x,y,z=dims; vs=[(sx*x/2+random.uniform(-rough,rough),sy*y/2+random.uniform(-rough,rough),sz*z/2+random.uniform(-rough,rough)) for sz in (-1,1) for sy in (-1,1) for sx in (-1,1)]
    fs=[(2,3,1,0),(5,7,6,4),(1,5,4,0),(6,7,3,2),(4,6,2,0),(3,7,5,1)]
    o=mesh_obj(name,vs,fs,[material]);o.location=loc
    if bevel:
        mod=o.modifiers.new('Hand worn beveled edges','BEVEL');mod.width=bevel;mod.segments=3
        no=o.modifiers.new('Weighted stone normals','WEIGHTED_NORMAL');no.keep_sharp=True
    return o

def tube(name,points,radii,material,sides=9,rough=.05):
    vs=[];fs=[]
    for k,p0 in enumerate(points):
        p=Vector(p0); tang=Vector(points[min(k+1,len(points)-1)])-Vector(points[max(0,k-1)])
        if tang.length==0:tang=Vector((0,0,1))
        tang.normalize(); u=tang.cross(Vector((0,1,0)))
        if u.length<.01:u=tang.cross(Vector((1,0,0)))
        u.normalize();v=tang.cross(u).normalized()
        for j in range(sides):
            a=j*2*pi/sides;r=radii[k]*(1+rough*sin(j*3.8+k*.4));vs.append(tuple(p+(u*cos(a)+v*sin(a))*r))
    for k in range(len(points)-1):
        for j in range(sides):fs.append((k*sides+j,k*sides+(j+1)%sides,(k+1)*sides+(j+1)%sides,(k+1)*sides+j))
    fs+=[tuple(range(sides-1,-1,-1)),tuple((len(points)-1)*sides+j for j in range(sides))]
    return mesh_obj(name,vs,fs,[material],smooth=True)

def ellipsoid(name,loc,scale,material,sub=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=loc);o=bpy.context.object;o.name=name;relocate(o);o.scale=scale;o.data.materials.append(material)
    for p in o.data.polygons:p.use_smooth=True
    return o

# Subtle real moss islands conform to feet/caps; no flat color decals.
def moss_patch(loc,rx,ry,count=10):
    for k in range(count):
        a=random.random()*2*pi;r=random.random()**.5
        ellipsoid('Soft moss clump',(loc[0]+cos(a)*rx*r,loc[1]+sin(a)*ry*r,loc[2]+random.uniform(-.015,.02)),(random.uniform(.1,.22),random.uniform(.08,.17),random.uniform(.035,.07)),random.choice(moss),1)

# Short modular wall. Outer base footprint is exactly the supplied 96x64 world-units.
active=wall_c
wall_w=96/WU;wall_d=64/WU/S
box('Recessed lime mortar heart',(0,0,1.61),(wall_w-.31,wall_d-.31,2.85),mortar,.06)
for row in range(4):
    z=.30+row*.69+.325
    cuts=[-wall_w/2+.14, -1.33,-.10,1.16,wall_w/2-.14] if row%2==0 else [-wall_w/2+.14,-1.75,-.60,.67,1.71,wall_w/2-.14]
    for side in [-1,1]:
        for j in range(len(cuts)-1):
            a,bb=cuts[j:j+2]
            box('Wall course%d face%d block%d'%(row,side,j),((a+bb)/2,side*(wall_d/2-.42),z),(bb-a-.045,.73,.64),random.choice(sand),.065,.037)
    # Header stones give both ends real thickness, with unaligned courses.
    ycuts=[-wall_d/2+.17,-.61,.63,wall_d/2-.17]
    for side in [-1,1]:
        for j in range(3):
            a,bb=ycuts[j:j+2]
            box('Wall end header', (side*(wall_w/2-.42),(a+bb)/2,z),(.73,bb-a-.055,.635),random.choice(sand),.065,.03)
box('Wall lower weathered footing',(0,0,.155),(wall_w-.12,wall_d-.12,.31),sand[1],.08,.015)
box('Wall projecting neck band',(0,0,3.09),(wall_w-.055,wall_d-.055,.18),cap,.055,.009)
# Mitered broad coping tiles, top and side clearly separated.
for ix in range(3):
    for iy in range(2):
        w=wall_w/3;d=wall_d/2
        box('Broad coping tile',(-wall_w/2+w*(ix+.5),-wall_d/2+d*(iy+.5),3.335),(w-.025,d-.025,.33),cap,.095,.026)
moss_patch((-1.7,-wall_d/2+.25,.325),.5,.28,20)
moss_patch((1.30,wall_d/2-.5,3.51),.5,.3,15)
moss_patch((-2.25,.5,1.02),.18,.30,7)
# Ivy sprigs drape a short way down an end without hiding masonry.
for q in range(3):
    x=-1.7+q*.14;y=-wall_d/2-.015
    pts=[(x+.08*sin(t*1.5+q),y-.02,t) for t in [3.35,3.08,2.85,2.6,2.42]]
    tube('Ivy stem',pts,[.017]*5,grassmat,5)
    for p in pts[1:]:ellipsoid('Small ivy leaf',(p[0]+.1,p[1]-.035,p[2]),(.14,.04,.1),moss[1],1)

# Raised carved garden plinth: massive stepped rim, inset soil, botanical relief.
active=bed_c
bw=160/WU;bd=120/WU/S
box('Plinth broad lower step',(0,0,.12),(bw,bd,.24),sand[2],.085,.015)
box('Plinth chamfered foot',(0,0,.39),(bw-.28,bd-.28,.34),cap,.10,.012)
box('Plinth stone body',(0,0,.94),(bw-.65,bd-.65,.86),sand[1],.045,.012)
box('Plinth top projecting cornice',(0,0,1.43),(bw-.15,bd-.15,.24),cap,.07,.01)
# Rim volume assembled as four thick solid pieces around a true interior.
outer_w=bw-.18;outer_d=bd-.18;rim=.47
for side in [-1,1]:
    box('Raised carved planter rim long',(0,side*(outer_d-rim)/2,1.92),(outer_w,rim,.62),cap,.07,.012)
    box('Raised carved planter rim return',(side*(outer_w-rim)/2,0,1.92),(rim,outer_d-2*rim,.62),cap,.07,.012)
box('Inset soil surface',(0,0,1.82),(outer_w-2*rim+.08,outer_d-2*rim+.08,.25),soil,.05,.035)
# Recessed front panels and stone pilaster strips create geometric depth.
for side in [-1,1]:
    y=side*(bd-.65)/2
    for x in [-2.42,0,2.42]:
        box('Recessed carved panel field',(x,y+side*.026,.94),(2.04,.055,.53),sand[0],.022)
        for xx in [-1.07,1.07]:box('Panel vertical raised fillet',(x+xx,y+side*.066,.96),(.10,.12,.7),cap,.024)
        for zz in [.64,1.24]:box('Panel horizontal raised fillet',(x,y+side*.06,zz),(2.15,.11,.07),cap,.015)
        pts=[(x-.74+i*.185,y+side*.08,.92+.10*sin(i*.62)) for i in range(9)]
        tube('Botanical copper relief curling stem',pts,[.018]*9,bronze,6)
        for j in range(1,8):
            p=pts[j];o=ellipsoid('Raised relief leaf',(p[0],p[1]+side*.016,p[2]+(.105 if j%2 else -.09)),(.13,.026,.07),bronze,2);o.rotation_euler[1]=(-.55 if j%2 else .45)
for xy in [(-bw/2+.32,-bd/2+.5),(bw/2-.6,bd/2-.4)]:moss_patch((xy[0],xy[1],.26),.35,.35,12)

# Actual folded leaf mesh helper, shared by garden and tree.
def add_fan(vs,fs,ids,p,direction,size,matidx):
    p=Vector(p);d=Vector(direction).normalized();normal=Vector((random.uniform(-.4,.4),random.uniform(-.4,.4),1)).normalized()
    right=d.cross(normal)
    if right.length<.01:right=Vector((1,0,0))
    right.normalize();up=right.cross(d).normalized();base=len(vs);vs.append(tuple(p))
    # Fan outline with the characteristic shallow central cleft and scalloping.
    n=8
    for j in range(n+1):
        a=math.radians(-72+144*j/n);notch=.74 if j==n//2 else (1-.025*(j%2));dist=size*notch
        vs.append(tuple(p+d*cos(a)*dist+right*sin(a)*dist*.72+up*(.12*size*sin(j*pi/n)+random.uniform(-.02,.02)*size)))
    for j in range(n):fs.append((base,base+1+j,base+2+j));ids.append(matidx)

# Garden flowers and herbs, sparse enough for soil and inner rim to remain visible.
gv=[];gf=[];gi=[]
for k in range(48):
    x=random.uniform(-bw/2+1.05,bw/2-1.05);y=random.uniform(-bd/2+1.05,bd/2-1.05);h=random.uniform(.25,.82)
    base=Vector((x,y,1.97));tip=base+Vector((random.uniform(-.12,.12),random.uniform(-.12,.12),h))
    tube('Garden herb stem',[base,base+(tip-base)*.53,tip],[.018,.016,.01],grassmat,5)
    for j in range(3):
        a=random.random()*2*pi;add_fan(gv,gf,gi,base+(tip-base)*(.2+j*.20),(cos(a),sin(a),.5),random.uniform(.13,.23),0)
    if k%3!=0:
        col=petals[k%3]
        for j in range(5):
            a=j*2*pi/5;o=ellipsoid('Small garden flower petal',tip+Vector((cos(a)*.072,sin(a)*.072,.02)),(.1,.05,.033),col,1);o.rotation_euler[2]=a
        ellipsoid('Flower center',tip+Vector((0,0,.042)),(.048,.048,.038),petals[2],1)
mesh_obj('Garden leaves',gv,gf,[grassmat],gi,True)

# Mature ginkgo with visibly forked trunk, airy tiered branch fans and individual fan leaves.
active=tree_c
trunk_pts=[(0,0,0),(.02,.03,.48),(-.09,.03,1.15),(-.08,.01,2.0),(.11,.06,2.9),(.04,.1,3.9),(.2,.18,4.85),(.20,.14,5.75),(.43,.18,6.65),(.46,.17,7.6),(.38,.25,8.55)]
trunk_rs=[.53,.40,.34,.285,.245,.21,.17,.12,.09,.055,.008]
tube('Naturally tapering ginkgo trunk',trunk_pts,trunk_rs,bark,13,.11)
for k in range(7):
    a=k*2*pi/7+.17;end=(cos(a)*random.uniform(1.15,1.7),sin(a)*random.uniform(1.15,1.7),.03)
    tube('Root flare',[(.03,0,.48),(cos(a)*.44,sin(a)*.44,.19),end],[.23,.19,.006],bark,8,.15)
# Three levels with air gaps; irregular limb lengths prevent stacked circles.
branch_specs=[]
for level,(z,spread,n) in enumerate([(3.5,3.0,4),(4.55,3.85,5),(5.8,3.25,5),(6.9,2.3,4),(7.9,1.3,3)]):
    for k in range(n):
        a=k*2*pi/n+level*.91+random.uniform(-.22,.22);r=spread*random.uniform(.84,1.06);rise=random.uniform(.55,1.05)
        start=Vector((.11,.08,z));elbow=start+Vector((cos(a)*r*.44,sin(a)*r*.44,rise*.44));tip=start+Vector((cos(a)*r,sin(a)*r,rise));
        pts=[start,start*.28+elbow*.72,elbow,elbow*.48+tip*.52,tip]
        tube('Ginkgo sweeping primary limb',pts,[.15*(1-level*.13),.13*(1-level*.13),.09,.055,.014],bark,9,.1)
        branch_specs.append((a,r,start,elbow,tip,level))
lv=[];lf=[];li=[]
for a,r,start,elbow,tip,level in branch_specs:
    for j in range(5):
        t=.39+j*.135;origin=start.lerp(tip,t);side=-1 if j%2 else 1;ang=a+side*random.uniform(.44,1.05)
        spread=random.uniform(.46,1.14)*(1-level*.07)
        end=origin+Vector((cos(ang)*spread,sin(ang)*spread,random.uniform(.22,.62)))
        mid=origin.lerp(end,.48)+Vector((0,0,.1))
        tube('Ginkgo secondary branchlet',[origin,mid,end],[.045,.027,.007],bark,7,.08)
        # Fan sprays are distributed along bent twigs, not on spherical clusters.
        for q in range(3):
            f=.42+q*.27;twig_start=origin.lerp(end,f);ta=ang+random.uniform(-.75,.75);twig_end=twig_start+Vector((cos(ta)*random.uniform(.28,.58),sin(ta)*random.uniform(.28,.58),random.uniform(.08,.3)))
            tube('Fine leaf-bearing ginkgo twig',[twig_start,twig_end],[.017,.003],bark,5,0)
            for m in range(7):
                p=twig_start.lerp(twig_end,random.uniform(.15,1.05));phi=ta+(-1 if m%2 else 1)*random.uniform(.65,1.65)
                d=Vector((cos(phi),sin(phi),random.uniform(-.28,.65)))
                add_fan(lv,lf,li,p,d,random.uniform(.21,.34),random.choices(range(6),weights=[1,2,3,4,2,2])[0])
    # Tip long-shoot fans create articulated outer silhouette.
    for k in range(19):
        p=tip+Vector((random.uniform(-.18,.18),random.uniform(-.18,.18),random.uniform(-.07,.15)));phi=a+random.uniform(-1.3,1.3)
        add_fan(lv,lf,li,p,(cos(phi),sin(phi),random.uniform(-.3,.6)),random.uniform(.22,.36),random.choice(range(6)))
mesh_obj('Individual folded bilobed ginkgo leaves',lv,lf,leaves,li,True)
# Fallen leaves and moss at root base preserve ground contact without a painted ground plate.
for k in range(34):
    a=random.random()*2*pi;r=random.uniform(.5,1.62);add_fan(lv:=[],lf:=[],li:=[],(cos(a)*r,sin(a)*r,.018),(cos(a+1),sin(a+1),.02),random.uniform(.08,.15),3)
    mesh_obj('Fallen ginkgo fan leaf',lv,lf,leaves,li)
moss_patch((-.32,-.2,.06),.68,.54,19)

# Consistent light rig: upper left key, broad warm-neutral fill, soft restrained rim.
active=rig_c
def area(name,loc,power,size,color,target=(0,0,2)):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color;o=bpy.data.objects.new(name,data);active.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();return o
# Large lights are distant enough to maintain near-identical lighting across showcase modules.
area('Warm upper-left key',(-35,-45,65),35000,28,(1,.90,.72))
area('Cool soft front fill',(35,-18,32),7000,34,(.76,.84,1))
area('Soft garden rim',(-6,35,40),9000,25,(1,.95,.72))
cam_data=bpy.data.cameras.new('Orthographic 55 degree game camera');cam=bpy.data.objects.new('Orthographic 55 degree game camera',cam_data);rig_c.objects.link(cam);scene.camera=cam;cam.data.type='ORTHO';cam.data.lens=50

def camera_at(target,scale,res):
    target=Vector(target);cam.location=target+Vector((0,-C*70,S*70));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;scene.render.resolution_x=res[0];scene.render.resolution_y=res[1];bpy.context.view_layer.update()

# Metadata records exact ground projection; exporter below computes pixel anchors from camera.
manifest={'version':1,'source':'Original procedural Blender mesh and material source; no downloaded assets','blender':'4.3.2','seed':SEED,'render_engine':'Cycles CPU','camera_elevation_degrees':55,'camera_yaw_degrees':0,'world_units_per_blender_unit':WU,'pixels_per_world_unit':2,'ground_depth_factor':1/S,'coordinate_mapping':'Blender X maps to Godot +X; Blender -Y maps to Godot +Y; Blender Z is visual height only. Ground anchor=(0,0,0).','assets':{
'wall_sandstone_short':{'collection':wall_c.name,'footprint_world':[96,64],'stone_height_world':70,'recommended_canvas':[512,512],'placement':'Modular short segment; do not stretch into full long wall'},
'garden_carved_plinth':{'collection':bed_c.name,'footprint_world':[160,120],'stone_height_world':45,'recommended_canvas':[512,512],'placement':'Existing obstacle footprint only; flowers extend above stone'},
'ginkgo_gold_green':{'collection':tree_c.name,'footprint_world':[80,80],'height_world':180,'recommended_canvas':[512,768],'placement':'Existing obstructed tiles or outer map perimeter only; canopy is larger than root footprint'}
}}
with open(os.path.join(OUT,'environment_manifest.json'),'w') as f:json.dump(manifest,f,indent=2)

# Assemble one native Blender showcase, not a painted composite.
for o in wall_c.objects:o.location.x-=9.5
for o in tree_c.objects:o.location.x+=10.0
active=stage_c
floor=mat('Showcase ground warm sage',(.23,.27,.21),noise=1.5,bump=.035)
box('Showcase ground only',(0,1,-.21),(31,17,.36),floor,.22)
# Gentle dividers are physical in-scene paving, not UI overlays.
for x in [-5.7,5.4]:
    for y in range(-5,7):box('Showcase paving joint marker',(x,y,-.022),(.12,.76,.035),sand[1],.02)
camera_at((.8,0,2.8),32.2,(1600,900))
scene.render.film_transparent=False;scene.render.filepath=os.path.join(OUT,'environment_native_preview.png')
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'environment_native_preview.blend'))
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
if '--no-render' not in args:bpy.ops.render.render(write_still=True)
print('ENVIRONMENT_PREVIEW_READY',scene.render.filepath,flush=True)
