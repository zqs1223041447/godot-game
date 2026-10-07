import bpy,bmesh,os
s=bpy.context.scene;s.view_settings.exposure=0.0;s.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.32
bpy.data.lights['Warm upper-left key'].energy=35000
bpy.data.lights['Cool soft front fill'].energy=7000
bpy.data.lights['Soft garden rim'].energy=9000
for o in s.objects:
    if o.type=='MESH' and len(o.data.vertices)==8 and len(o.data.polygons)==6:
        bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.reverse_faces(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
colors=[(.15,.27,.018),(.23,.36,.035),(.38,.44,.045),(.58,.47,.055),(.64,.54,.09),(.30,.40,.04)]
for i,c in enumerate(colors):
    m=bpy.data.materials['Ginkgo fan leaf %d'%i];m.diffuse_color=(*c,1);m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*c,1)
    for n in m.node_tree.nodes:
        if n.type=='BSDF_TRANSLUCENT':n.inputs[0].default_value=(*c,1)
# A moved .blend may retain its original machine's render output path.
s.render.filepath=os.path.join(os.path.dirname(os.path.abspath(__file__)),'environment_native_preview.png')
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
bpy.ops.render.render(write_still=True)
