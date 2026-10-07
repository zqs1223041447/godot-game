import bpy, math, os, random, json
from mathutils import Vector, Matrix
from math import sin, cos, pi
random.seed(27)
OUT=os.path.dirname(os.path.abspath(__file__))
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for dat in bpy.data.materials: bpy.data.materials.remove(dat)
scene=bpy.context.scene
scene.render.engine='CYCLES'; scene.cycles.device='CPU'; scene.cycles.samples=64; scene.cycles.use_denoising=False
scene.render.resolution_x=256; scene.render.resolution_y=256; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.image_settings.color_mode='RGBA'; scene.render.film_transparent=True
scene.view_settings.view_transform='AgX'; scene.view_settings.look='AgX - Medium High Contrast'
scene.world.color=(.32,.32,.32)
scene.world.use_nodes=True; scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.48,.56,.66,1); scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.35

def mat(name,color,rough=.6,metal=0,noise=0):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
 n=m.node_tree.nodes; l=m.node_tree.links; p=n.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1); p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
 if noise:
  tex=n.new('ShaderNodeTexNoise'); tex.inputs['Scale'].default_value=65; tex.inputs['Detail'].default_value=3
  bump=n.new('ShaderNodeBump'); bump.inputs['Strength'].default_value=noise; bump.inputs['Distance'].default_value=.012; l.new(tex.outputs['Fac'],bump.inputs['Height']); l.new(bump.outputs['Normal'],p.inputs['Normal'])
  ramp=n.new('ShaderNodeValToRGB'); ramp.color_ramp.elements[0].position=.15; ramp.color_ramp.elements[0].color=tuple(v*.62 for v in color)+(1,); ramp.color_ramp.elements[1].position=.84; ramp.color_ramp.elements[1].color=tuple(min(v*1.25,1) for v in color)+(1,); l.new(tex.outputs['Fac'],ramp.inputs['Fac']); l.new(ramp.outputs['Color'],p.inputs['Base Color'])
 return m
wine=mat('wine wool',(0.19,.019,.032),.9,noise=.24); wine_edge=mat('worn wine piping',(.29,.065,.06),.8,noise=.2)
leather=mat('ocher layered leather',(.36,.145,.044),.61,noise=.25); leather_hi=mat('worn leather edge',(.53,.26,.09),.6,noise=.15)
dark=mat('umber belts boots',(.105,.051,.027),.56,noise=.22); bootmat=mat('waxed boot leather',(.13,.071,.043),.5,noise=.18); cloth=mat('charcoal linen',(.052,.051,.043),.95,noise=.4)
metal=mat('old silver',(.29,.31,.30),.53,.62,noise=.20); metal_hi=mat('silver raised edge',(.56,.57,.52),.32,.72); brass=mat('worn brass',(.42,.28,.095),.37,.7)
skin=mat('weathered skin',(.47,.26,.145),.69,noise=.07); skinlight=mat('nose cheeks',(.52,.29,.17),.69); shadow=mat('face dark features',(.035,.019,.013),.8)
hair=mat('dark chestnut hair',(.056,.03,.018),.82,noise=.16); hair_hi=mat('hair warm highlights',(.09,.045,.023),.81); beard=mat('short greying beard',(.09,.075,.059),.87)
wood=mat('aged twisted ash',(.16,.08,.027),.72,noise=.32); wood_hi=mat('wood ridge',(.25,.13,.045),.7,noise=.28)
crystal=mat('muted honey quartz',(.82,.285,.021),.28,.08); crystal.node_tree.nodes['Principled BSDF'].inputs['Emission Color'].default_value=(1,.27,.015,1); crystal.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value=.3

root=bpy.data.objects.new('HeroRoot',None); bpy.context.collection.objects.link(root)
joints={}
def joint(name,p,parent=root):
 o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o); o.location=p; o.parent=parent; joints[name]=o; return o
pelvis=joint('pelvis',(0,0,0)); chest=joint('chest',(0,0,0),pelvis); head=joint('head',(0,0,0),chest)
def mesh(name,verts,faces,ma,parent=root,smooth=True,sub=0):
 me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update(); ob=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(ob); ob.data.materials.append(ma); ob.parent=parent
 for p in me.polygons:p.use_smooth=smooth
 if sub: mod=ob.modifiers.new('gentle sculpt smoothing','SUBSURF'); mod.levels=sub; mod.render_levels=sub
 return ob

def sphere(name,loc,scale,ma,parent=root,segments=20,rings=12):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,location=loc); o=bpy.context.object;o.name=name;o.scale=scale;o.data.materials.append(ma);o.parent=parent
 for f in o.data.polygons:f.use_smooth=True
 return o

def loft(name,rings,ma,parent=root,n=16,sub=1):
 # rings: center x,y,z, x radius, y radius; asymmetric sculpted silhouettes
 vs=[]
 for j,(x,y,z,rx,ry) in enumerate(rings):
  for i in range(n):
   a=2*pi*i/n; wave=1+.022*sin(3*a+j*.67)
   vs.append((x+rx*cos(a)*wave,y+ry*sin(a)*wave,z))
 fs=[]
 for j in range(len(rings)-1):
  for i in range(n):fs.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
 fs.extend([tuple(range(n-1,-1,-1)),tuple((len(rings)-1)*n+i for i in range(n))])
 return mesh(name,vs,fs,ma,parent,sub=sub)

def tube(name,points,radii,ma,parent=root,n=10,sub=1):
 vs=[]
 for j,p in enumerate(points):
  p=Vector(p); tangent=Vector(points[min(j+1,len(points)-1)])-Vector(points[max(0,j-1)])
  tangent.normalize(); ref=Vector((0,1,0)) if abs(tangent.y)<.9 else Vector((1,0,0)); u=tangent.cross(ref).normalized();v=tangent.cross(u).normalized()
  rr=radii[j] if type(radii) in (list,tuple) else radii
  rx,ry=rr if type(rr) in (list,tuple) else (rr,rr)
  for i in range(n):vs.append(tuple(p+u*(rx*cos(i*2*pi/n))+v*(ry*sin(i*2*pi/n))))
 fs=[]
 for j in range(len(points)-1):
  for i in range(n):fs.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
 fs+=[tuple(range(n-1,-1,-1)),tuple((len(points)-1)*n+i for i in range(n))]
 return mesh(name,vs,fs,ma,parent,sub=sub)

def line(name,points,r,ma,parent=root):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.resolution_u=10;cu.bevel_depth=r;cu.bevel_resolution=2
 sp=cu.splines.new('BEZIER');sp.bezier_points.add(len(points)-1)
 for b,p in zip(sp.bezier_points,points):b.co=p;b.handle_left_type='AUTO';b.handle_right_type='AUTO'
 ob=bpy.data.objects.new(name,cu);bpy.context.collection.objects.link(ob);ob.data.materials.append(ma);ob.parent=parent;return ob

def block(name,loc,scale,ma,bevel=.01,parent=root):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(ma);o.parent=parent
 if bevel: m=o.modifiers.new('soft worn corners','BEVEL');m.width=bevel;m.segments=3;m=o.modifiers.new('weighted corner normals','WEIGHTED_NORMAL')
 return o
# torso and layered body
loft('fitted tunic body',[(0,.015,.91,.15,.11),(0,.008,1.01,.18,.13),(0,.008,1.18,.182,.123),(0,.015,1.35,.237,.145),(0,.01,1.44,.21,.115),(0,.008,1.48,.11,.08)],leather,chest,n=20)
loft('dark inner collar',[(0,0,1.41,.105,.085),(0,0,1.52,.095,.084),(0,0,1.55,.08,.07)],cloth,chest)
# Breast chest seam gently follows form
for s in [-1,1]:
 line('vertical hand sewn coat seam',[(s*.145,-.086,1.00),(s*.153,-.102,1.14),(s*.17,-.116,1.32),(s*.17,-.065,1.43)],.005,leather_hi,chest)
 # flared separated skirt panels, curved fitted surfaces
 vs=[];nu=8;nv=7
 for v in range(nv):
  t=v/(nv-1);z=.97-.39*t
  for u in range(nu):
   q=u/(nu-1); x=s*(.02+.19*q+.05*t*q); y=-.117-.013*t+.036*(q-.3)**2
   zc=z+.065*q*t+.015*sin(q*8)*t
   vs.append((x,y,zc))
 fs=[(v*nu+u,v*nu+u+1,(v+1)*nu+u+1,(v+1)*nu+u) for v in range(nv-1) for u in range(nu-1)]
 ob=mesh('split ocher front coat skirt',vs,fs,leather,pelvis,sub=1);sol=ob.modifiers.new('leather thickness','SOLIDIFY');sol.thickness=.014
 line('skirt outer welt',[(s*.214,-.102,.96),(s*.241,-.105,.8),(s*.266,-.105,.65)],.006,leather_hi,pelvis)
 line('skirt bottom welt',[(s*.025,-.133,.586),(s*.12,-.131,.59),(s*.26,-.106,.65)],.006,leather_hi,pelvis)
# lower flared back coat
loft('coat rear skirt',[(0,.045,.62,.215,.08),(0,.035,.83,.204,.13),(0,.02,1.0,.172,.107)],leather,pelvis,n=16)
# legs: weight distributed rather than parallel rods
for s in [-1,1]:
 leg=joint(('right' if s<0 else 'left')+'_leg',(0,0,0),pelvis)
 x=s*.12; offs=-.026 if s<0 else .035
 loft('creased trouser leg',[(x,offs,.29,.07,.066),(x,offs,.40,.076,.071),(x+s*.006,offs,.49,.087,.086),(x+s*.02,.014,.59,.091,.083),(x+s*.012,.013,.73,.103,.095),(x,.01,.90,.105,.099),(x*.73,.018,.98,.1,.094)],cloth,leg,n=14)
 for z in [.48,.56,.72]:line('trouser fold',[(x-.058,offs-.047,z+.018),(x-.012,offs-.079,z),(x+.067,offs-.056,z-.01)],.008,cloth,leg)
 # actual foot upper sculpted with long toe
 loft('boot upper',[(x,offs-.026,.045,.078,.13),(x,offs-.055,.068,.084,.142),(x,offs-.045,.116,.081,.134),(x,offs-.006,.17,.069,.087),(x,offs+.017,.23,.062,.062),(x,offs+.008,.36,.074,.07),(x,offs+.008,.388,.079,.074)],bootmat,leg,n=16)
 loft('layered leather outsole',[(x,offs-.038,.026,.084,.148),(x,offs-.038,.045,.087,.151),(x,offs-.038,.06,.086,.148)],dark,leg,n=18,sub=0)
 loft('turned over boot cuff',[(x,offs+.009,.328,.081,.079),(x,offs+.009,.359,.089,.082),(x,offs+.009,.397,.085,.079),(x,offs+.009,.41,.081,.075)],dark,leg,n=16)
 line('toe cap welt',[(x-.076,offs-.07,.08),(x-.06,offs-.13,.086),(x,offs-.179,.082),(x+.065,offs-.13,.082)],.004,leather_hi,leg)
 for z in [.20,.255]:line('boot wrinkled vamp',[(x-.052,offs-.042,z+.008),(x+.006,offs-.059,z),(x+.052,offs-.046,z+.013)],.005,dark,leg)
 # instep strap
 ob=block('boot instep strap',(x,offs-.046,.151),(.157,.033,.023),dark,.007,leg);ob.rotation_euler[0]=.15
 block('boot strap buckle',(x+s*.071,offs-.05,.156),(.023,.041,.032),brass,.004,leg)
# belt elliptical ring shape
loft('waist belt',[(0,.005,.971,.182,.136),(0,.005,.988,.187,.14),(0,.005,1.053,.187,.139),(0,.005,1.065,.181,.135)],dark,chest,n=28,sub=0)
# buckle frame, not solid blank
for loc,sc in [((-.039,-.143,1.017),(.011,.012,.057)),((.039,-.143,1.017),(.011,.012,.057)),((0,-.144,.989),(.085,.012,.011)),((0,-.144,1.045),(.085,.012,.011))]:block('belt buckle frame',loc,sc,brass,.003,chest)
line('belt buckle pin',[(-.019,-.153,1.02),(.034,-.153,1.019)],.004,metal_hi,chest)
for x in [-.14,-.09,.085,.13]:sphere('belt pierced eyelet',(x,-.138,1.02),(.005,.003,.005),brass,chest,12,8)
# crossed front strap lies over shaped chest
strap=[(-.175,-.112,1.072),(-.10,-.138,1.17),(.001,-.154,1.28),(.103,-.143,1.38),(.18,-.075,1.453)]
for off in [-.019,0,.019]:line('cross body leather baldric',[(x+off,y-.008,z) for x,y,z in strap],.012,dark,chest)
line('baldric lighter welt',[(x+.025,y-.016,z) for x,y,z in strap],.003,leather_hi,chest)
for t in [.26,.65]:
 x=-.175+.355*t;z=1.072+.381*t;sphere('baldric rivet',(x,-.159,z),(.006,.004,.006),brass,chest,12,8)
# hip pouches and dangling keeper
for s in [-1,1]:
 x=s*.206;y=-.007
 pouch=block('rounded hip satchel',(x,y,.924),(.123,.132,.159),dark,.025,pelvis);pouch.rotation_euler[1]=s*.10
 block('satchel flap',(x,y-.067,.961),(.123,.026,.092),bootmat,.018,pelvis)
 line('satchel flap stitched lip',[(x-.05,y-.081,.965),(x,y-.09,.924),(x+.05,y-.081,.965)],.003,leather_hi,pelvis)
 sphere('satchel brass clasp',(x,y-.089,.942),(.012,.006,.013),brass,pelvis,12,8)
# arms asymmetrical anatomically bending
for s in [-1,1]:
 ar=joint(('right' if s<0 else 'left')+'_arm',(0,0,0),chest)
 if s<0:pts=[(-.22,.0,1.407),(-.28,-.013,1.353),(-.31,-.06,1.222),(-.326,-.098,1.168),(-.355,-.16,1.094),(-.398,-.197,1.038)]
 else:pts=[(.22,.0,1.406),(.294,.006,1.348),(.331,.015,1.21),(.328,-.012,1.164),(.334,-.072,1.059),(.36,-.12,.982)]
 tube('shaped linen sleeve',pts,[(.102,.098),(.097,.097),(.072,.071),(.076,.07),(.065,.061),(.054,.052)],cloth,ar,n=14,sub=1)
 p0=Vector(pts[-3]);p1=Vector(pts[-1]);mid=p0.lerp(p1,.6)
 tube('layered leather bracer',[tuple(p0.lerp(p1,.12)),tuple(p0.lerp(p1,.24)),tuple(mid),tuple(p0.lerp(p1,.9))],[.081,.076,.067,.064],dark,ar,n=12)
 for t in [.22,.84]:
  a=p0.lerp(p1,t-.055);b=p0.lerp(p1,t+.055);tube('bracer wrap strap',[tuple(a),tuple(b)],[.082 if t<.4 else .07]*2,leather,ar,n=12,sub=0)
 handp=Vector(pts[-1])+Vector((-.008 if s<0 else .009,-.012,-.027))
 sphere('leather glove palm',handp,(.061,.052,.071),bootmat,ar)
 # Individual curled finger volumes
 for k in range(4):
  fp=handp+Vector(((k-1.5)*.024,-.037,-.023))
  sphere('glove curled finger',fp,(.015,.03,.037),bootmat,ar,12,8)
 sphere('glove thumb',handp+Vector((.05 if s<0 else -.051,-.004,.025)),(.024,.029,.044),bootmat,ar,12,8)
# left shoulder old-silver compound plate, cap around deltoid
vs=[];nu=20;nv=9
for j in range(nv):
 t=j/(nv-1);a=t*pi*.72
 for i in range(nu):
  p=2*pi*i/nu
  vs.append((.25+.139*sin(a)*cos(p),.004+.12*sin(a)*sin(p),1.37+.103*cos(a)+.018*sin(a)*cos(p)))
fs=[(j*nu+i,j*nu+(i+1)%nu,(j+1)*nu+(i+1)%nu,(j+1)*nu+i) for j in range(nv-1) for i in range(nu)]
ob=mesh('hammered convex pauldron',vs,fs,metal,chest,sub=1);mod=ob.modifiers.new('forged thickness','SOLIDIFY');mod.thickness=.01
for a in [pi*.52,pi*.69]:
 line('rolled silver pauldron rim',[(.25+.143*sin(a)*cos(p),.004+.125*sin(a)*sin(p),1.37+.105*cos(a)+.018*sin(a)*cos(p)) for p in [i*2*pi/20 for i in range(21)]],.006,metal_hi,chest)
# distinct lames below armour cap
for z in [1.295,1.25]:
 tube('articulated lower shoulder lame',[(.302,.0,z+.023),(.32,.0,z-.018)],[.096,.091],metal,chest,n=12,sub=0)
# visible engraved feather fan etched bronze lines
for i in range(3):
 line('pauldron chased groove',[(.209+i*.036,-.084,1.44),(.222+i*.037,-.105,1.397),(.239+i*.034,-.101,1.351)],.0024,dark,chest)
for a in [.45,1.2,2.2,3.9,5.0]:sphere('silver cap rivet',(.25+.128*cos(a),.004+.104*sin(a),1.385),(.008,.008,.006),brass,chest,12,8)
# cape is a curved draped cloth sheet behind the body, scalloped/folded hems
vs=[];nu=29;nv=15
for j in range(nv):
 t=j/(nv-1)
 for i in range(nu):
  u=(i/(nu-1)-.5)*2; theta=u*1.95
  width=.20+.14*sin(t*pi*.76);x=width*sin(theta)
  y=.038+(.113+.082*t)*cos(theta)+.034*sin(u*6*pi)*(t**.65)
  z=1.476-.64*t+.036*cos(u*4*pi)*t*t-.05*abs(u)*(1-t)
  vs.append((x,y,z))
fs=[(j*nu+i,j*nu+i+1,(j+1)*nu+i+1,(j+1)*nu+i) for j in range(nv-1) for i in range(nu-1)]
ob=mesh('short burgundy traveling cloak',vs,fs,wine,chest,sub=1);mod=ob.modifiers.new('woven cloth thickness','SOLIDIFY');mod.thickness=.012
line('cape old wool hem',[vs[(nv-1)*nu+i] for i in range(nu)],.006,wine_edge,chest)
# hood laid down at nape: heavy upper folds crossing behind neck, remains off head
for k in range(3):
 pts=[]
 for i in range(13):
  a=-pi*.12+i*pi*1.24/12
  pts.append((.142*cos(a),.008+.115*sin(a)+k*.024,1.479-k*.018+.04*sin(a)))
 line('folded hood roll',pts,.024-k*.002,wine,chest)
# asymmetric shoulder cape and chest drape, front fold from shoulder to brooch
line('cape heavy cowl front',[(-.262,.018,1.425),(-.223,-.058,1.459),(-.127,-.106,1.456),(-.035,-.107,1.433),(.025,-.104,1.426)],.036,wine,chest)
line('cloak collar worn lip',[(-.266,-.012,1.446),(-.194,-.094,1.477),(-.102,-.132,1.467),(.025,-.129,1.436)],.007,wine_edge,chest)
sphere('round antique cloak clasp',(.021,-.143,1.436),(.031,.011,.031),brass,chest)
sphere('clasp garnet center',(.021,-.155,1.436),(.014,.007,.014),wine,chest)
# head real silhouette: trapezoid jaw, cheeks, cranium, ears and low brow
loft('sculpted mature human head',[(0,-.006,1.505,.054,.052),(0,-.013,1.525,.074,.066),(0,-.01,1.553,.084,.077),(0,-.003,1.601,.099,.085),(0,.0,1.654,.106,.088),(0,.013,1.708,.098,.09),(0,.019,1.744,.078,.077),(0,.019,1.763,.041,.049)],skin,head,n=24,sub=1)
loft('exposed neck',[(0,.009,1.451,.06,.06),(0,.005,1.53,.063,.058)],skin,head,n=16)
for s in [-1,1]:
 sphere('ear', (s*.102,.0,1.615),(.022,.018,.041),skin,head)
 sphere('ear concha', (s*.116,-.009,1.615),(.007,.011,.025),skinlight,head)
 # cheek planes, restrained eye sockets and very small pupils
 sphere('angular cheekbone',(s*.059,-.073,1.598),(.037,.014,.029),skinlight,head)
 sphere('recessed eyelid',(s*.043,-.083,1.639),(.027,.008,.012),dark,head)
 sphere('eye glint',(s*.044,-.089,1.639),(.011,.003,.0045),metal_hi,head,12,8)
 line('frowning brow',[(s*.02,-.088,1.654),(s*.043,-.091,1.66),(s*.07,-.078,1.655)],.009,hair,head)
# strong nose with bridge and angular tip
mesh('nose bridge and tip',[(-.012,-.083,1.648),(.012,-.083,1.648),(-.017,-.11,1.594),(.017,-.11,1.594),(0,-.132,1.602),(0,-.1,1.65),(-.021,-.091,1.59),(.021,-.091,1.59)],[(0,1,5),(0,5,4,2),(1,3,4,5),(2,4,3),(2,3,7,6),(0,2,6),(1,7,3)],skinlight,head,sub=1)
# short salt/pepper beard follows jaw, not a long wizard triangle
loft('trimmed full jaw beard',[(0,-.015,1.504,.056,.053),(0,-.023,1.521,.07,.064),(0,-.024,1.549,.079,.074),(0,-.012,1.567,.081,.072)],beard,head,n=20,sub=1)
line('moustache left',[(-.004,-.107,1.574),(-.024,-.106,1.579),(-.042,-.09,1.569)],.009,hair,head)
line('moustache right',[(.004,-.107,1.574),(.024,-.106,1.579),(.042,-.09,1.569)],.009,hair,head)
line('set mouth',[(-.029,-.107,1.558),(0,-.114,1.555),(.029,-.107,1.558)],.0026,shadow,head)
for s in [-1,1]:
 for i in range(4):
  x=s*(.025+i*.012);line('grey beard strand',[(x,-.079- .02*(1-i/4),1.55),(x*.85,-.071-.02*(1-i/4),1.522)],.002,metal,head)
# swept chestnut scalp, custom cap surface only where hair grows
vs=[];N=24;M=10
for j in range(M):
 t=j/(M-1)
 for i in range(N):
  a=i*2*pi/N;front=max(0,-sin(a));phi=.08+t*(1.66-.66*front)
  vs.append((.112*sin(phi)*cos(a),.014+.104*sin(phi)*sin(a),1.664+.121*cos(phi)))
fs=[(j*N+i,j*N+(i+1)%N,(j+1)*N+(i+1)%N,(j+1)*N+i) for j in range(M-1) for i in range(N)]
mesh('sculpted swept scalp',vs,fs,hair,head,sub=1)
# individual broad swept locks kept close to skull; silhouette layered, no bead hair
for i in range(10):
 t=i/9;x=-.105+.18*t
 pts=[(x,.045,1.736+ .038*(1-abs(x)/.12)),(x-.021,.0,1.782-abs(x)*.3),(x-.038,-.055,1.749-abs(x)*.2),(x-.045,-.085,1.709-abs(x)*.12)]
 tube('swept sculpted forelock',pts,[(.018,.012),(.021,.014),(.02,.013),(.006,.005)],hair_hi if i%3==0 else hair,head,n=8,sub=1)
for s in [-1,1]:
 for k in range(5):
  y=-.005+k*.021
  tube('wavy nape hair',[(s*.096,y,1.706),(s*.119,y+.003,1.662),(s*.102,y+.015,1.607),(s*.117,y+.018,1.58-k*.002)],[.018,.021,.017,.004],hair_hi if k==2 else hair,head,n=8,sub=1)
# Staff thin irregular solid ash; fixture held by left-screen glove
sx=-.407;sy=-.211
pts=[(sx+.016,sy+.01,.035),(sx+.005,sy+.007,.38),(sx+.009,sy,.73),(sx,sy,1.05),(sx-.021,sy+.007,1.39),(sx-.012,sy+.014,1.62)]
tube('crooked seasoned wooden staff',pts,[.023,.021,.022,.024,.027,.031],wood,joints['right_arm'],n=10,sub=1)
line('staff winding grain',[(sx+.02,sy,.06),(sx-.013,sy-.019,.40),(sx+.023,sy-.014,.71),(sx-.018,sy-.02,1.06),(sx+.016,sy-.015,1.40),(sx-.03,sy-.017,1.62)],.006,wood_hi,joints['right_arm'])
for z in [.12,.82,1.39]:tube('staff antique binding',[(sx,sy,z),(sx,sy,z+.028)],[.027,.027],brass,joints['right_arm'],n=12,sub=0)
# crystal faceted mesh and cradling prongs
cx=sx-.012;cy=sy+.014;cz=1.714
verts=[(cx,cy,cz-.105)]
for z,r in [(cz-.044,.045),(cz+.025,.041)]:
 for i in range(6):verts.append((cx+r*cos(i*pi/3),cy+r*sin(i*pi/3),z))
verts.append((cx+.007,cy,cz+.096));faces=[]
for i in range(6):faces.extend([(0,1+i,1+(i+1)%6),(1+i,7+i,7+(i+1)%6,1+(i+1)%6),(13,7+(i+1)%6,7+i)])
mesh('six sided honey quartz',verts,faces,crystal,joints['right_arm'],smooth=False)
for i in range(4):
 a=i*pi/2+.45
 pts=[(cx,cy,1.576),(cx+.055*cos(a),cy+.055*sin(a),1.645),(cx+.054*cos(a),cy+.054*sin(a),1.712),(cx+.03*cos(a),cy+.03*sin(a),1.768)]
 tube('wooden crystal cradle',pts,[.019,.018,.012,.003],wood_hi,joints['right_arm'],n=8,sub=1)
# The traveler plants the staff inward by the boot rather than one arm's width outside it.
# Bend the lower shaft in toward the foot while keeping the grip and crystal at the hand.
for ob in list(bpy.data.objects):
 if ob.name.startswith(('crooked seasoned wooden staff','staff winding grain','staff antique binding')):
  def staff_inset(co):
   co.x += .15*max(0,(1.05-co.z)/1.015)
   co.y += .09*max(0,(1.05-co.z)/1.015)
  if ob.type=='MESH':
   for v in ob.data.vertices:staff_inset(v.co)
  elif ob.type=='CURVE':
   for sp in ob.data.splines:
    for p in sp.bezier_points:staff_inset(p.co)
# A head-height walking staff fits all compass views under the fixed portrait camera.
for ob in list(bpy.data.objects):
 if ob.name.startswith(('crooked seasoned wooden staff','staff winding grain','staff antique binding','six sided honey quartz','wooden crystal cradle')):
  def staff_top_fit(co):
   if co.z>1.05:co.z=1.05+(co.z-1.05)*.80
  if ob.type=='MESH':
   for v in ob.data.vertices:staff_top_fit(v.co)
  elif ob.type=='CURVE':
   for sp in ob.data.splines:
    for p in sp.bezier_points:staff_top_fit(p.co)
# Fixed screen-left warm key and large cool fill
camdir=Vector((4,-6,math.sqrt(52)*math.tan(math.radians(55)))).normalized()
rot=(-camdir).to_track_quat('-Z','Y');up=rot@Vector((0,1,0));right=rot@Vector((1,0,0))
scale=2.0;target=up*(scale*.32)
bpy.ops.object.camera_add(location=target+camdir*7);cam=bpy.context.object;cam.name='orthographic_55deg';cam.rotation_euler=rot.to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=scale;scene.camera=cam

def area(name,loc,power,size,col):
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.data.color=col;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
area('fixed screen upper left softbox',Vector((0,0,1))+camdir*3-right*3+up*4,500,4,(1,.79,.58))
area('soft front sky fill',Vector((0,0,1))+camdir*3+right*3,170,5,(.63,.77,1))
# Tilt the face toward its route, making brow/nose/beard legible from the high camera.
head.matrix_basis=Matrix.Translation((0,0,1.61)) @ Matrix.Rotation(math.radians(-18),4,'X') @ Matrix.Translation((0,0,-1.61))
# Intentional pose root only: all individual components remain articulated under named joints.
scene.render.filepath=os.path.join(OUT,'hero_sample_256.png')
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'hero_adventurer.blend'))
if os.environ.get('HERO_MODEL_ONLY') != '1': bpy.ops.render.render(write_still=True)
with open(os.path.join(OUT,'sample_metadata.json'),'w') as f:json.dump({'artifact':'original procedural full 3D traveler mage','render_engine':'Cycles CPU','samples':64,'resolution':[256,256],'camera_elevation':55,'camera_azimuth_from_front':33.6900675,'foot_anchor':[128,209.92],'orthographic_scale':scale,'alpha':'transparent straight RGBA; no plane or baked shadow','material_notes':'wine wool, ocher leather, waxed boots, old silver pauldron, mature face/hair/beard, sculpted layered meshes','direction_contract':'not selected; root review required before atlas batch'},f,indent=2)
