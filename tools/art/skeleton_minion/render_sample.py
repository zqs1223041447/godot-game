"""Run with Blender 4.3.2 --background --factory-startup --disable-autoexec.

Small authored-animation fit sample, not a production eight-direction atlas.
"""
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector
from bpy_extras.object_utils import world_to_camera_view

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'art-studies/kaykit-skeleton-minion-1.0/source/Skeleton_Minion.glb'
OUTPUT = ROOT / 'docs/qa/kaykit-skeleton-minion'
HEAD_PITCH_DEGREES = 0.0
if '--' in sys.argv:
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--head-pitch', type=float, default=0)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    HEAD_PITCH_DEGREES = args.head_pitch
    assert HEAD_PITCH_DEGREES in (0, -25), 'Only the bounded static fit comparison is supported'
    if HEAD_PITCH_DEGREES:
        OUTPUT = OUTPUT / 'head-fit'
FRAMES = OUTPUT / 'frames'
FRAMES.mkdir(parents=True, exist_ok=True)
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == '6ffc003f895bed0b074791e0e490846210a2e2f8fc7da300aba53cc185f95968'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects['Rig']
yaw_root = bpy.data.objects.new('sample_heading_parent', None)
scene.collection.objects.link(yaw_root)
rig.parent = yaw_root  # heading remains independent of author object animation channels
meshes = sorted((o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('Skeleton_Minion_')), key=lambda o: o.name)
assert len(rig.pose.bones) == 41 and len(meshes) == 9
assert all(any(m.type == 'ARMATURE' and m.object == rig for m in o.modifiers) for o in meshes)
for obj in bpy.data.objects:
    if obj.type == 'MESH' and obj not in meshes:
        obj.hide_render = True  # importer bone-custom-shape helper, not author body geometry
for track in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(track)
scene.render.fps = 24  # importer action frames; not gameplay or output animation timing
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 40
scene.cycles.use_denoising = False
scene.render.threads_mode = 'FIXED'
scene.render.threads = 3
scene.render.resolution_x = 128
scene.render.resolution_y = 192
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.world = bpy.data.worlds.new('fixed cool sky')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.48, .56, .66, 1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .35
# Keep the author texture and glow. Match the hero's matte material/light treatment.
for material in bpy.data.materials:
    if material.name == 'skeleton':
        p = material.node_tree.nodes.get('Principled BSDF')
        p.inputs['Roughness'].default_value = .75
        p.inputs['Metallic'].default_value = 0
camdir = Vector((0, -math.cos(math.radians(55)), math.sin(math.radians(55))))
bpy.ops.object.camera_add()
camera = bpy.context.object
camera.name = 'orthographic_55deg_sample'
camera.rotation_euler = (-camdir).to_track_quat('-Z', 'Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.sensor_fit = 'VERTICAL'
camera.data.ortho_scale = 3.2
up = camera.rotation_euler.to_quaternion() @ Vector((0, 1, 0))
camera.location = up * (3.2 * (158 / 192 - .5)) + camdir * 7
scene.camera = camera


def area(name, location, energy, size, color):
    bpy.ops.object.light_add(type='AREA', location=location)
    light = bpy.context.object
    light.name = name
    light.data.energy, light.data.size, light.data.color = energy, size, color
    light.rotation_euler = (Vector((0, 0, 1)) - light.location).to_track_quat('-Z', 'Y').to_euler()


area('fixed screen upper left softbox', (-3, -4, 8), 600, 4, (1, .79, .58))
area('soft front sky fill', (3, -4, 4), 165, 5, (.63, .77, 1))


def evaluate():
    graph = bpy.context.evaluated_depsgraph_get()
    vertices = {}
    for mesh in meshes:
        evaluated = mesh.evaluated_get(graph)
        data = evaluated.to_mesh()
        vertices[mesh.name] = [evaluated.matrix_world @ vertex.co for vertex in data.vertices]
        evaluated.to_mesh_clear()
    return vertices


def set_fraction(action, fraction):
    rig.animation_data.action = action
    frame = action.frame_range[0] + fraction * (action.frame_range[1] - action.frame_range[0])
    scene.frame_set(math.floor(frame), subframe=frame % 1)
    bpy.context.view_layer.update()
    if HEAD_PITCH_DEGREES:
        head = rig.pose.bones['head']
        world = rig.matrix_world @ head.matrix
        pivot = world.translation.copy()
        # Constant rig-space heading-relative tilt, applied after each author pose.
        pitch = rig.matrix_world.to_quaternion() @ Vector((1, 0, 0))
        adjustment = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(HEAD_PITCH_DEGREES), 4, pitch) @ Matrix.Translation(-pivot)
        head.matrix = rig.matrix_world.inverted() @ adjustment @ world
        bpy.context.view_layer.update()


clips = {'idle': 'Idle', 'walk': 'Walking_D_Skeletons', 'attack': 'Unarmed_Melee_Attack_Punch_A'}
directions = {'south': 0, 'southeast': 45, 'east': 90}
fractions = [0, .25, .5, .75]
deformation = {}
for clip, name in clips.items():
    action = bpy.data.actions[name + '_Rig']
    samples = []
    for fraction in fractions:
        set_fraction(action, fraction)
        samples.append(evaluate())
    deltas = []
    for sample in samples[1:]:
        deltas.append(max((a - b).length for key in sample for a, b in zip(sample[key], samples[0][key])))
    assert max(deltas) > .001, name + ' did not deform the evaluated body'
    deformation[clip] = {'author_animation': name, 'action_fcurves': len(action.fcurves),
                         'duration_seconds': (action.frame_range[1] - action.frame_range[0]) / 24,
                         'sample_fractions': fractions, 'max_vertex_displacement_from_first': deltas,
                         'verified_on': [mesh.name for mesh in meshes]}
records = []
for direction, yaw in directions.items():
    yaw_root.rotation_euler.z = math.radians(yaw)
    for clip, name in clips.items():
        action = bpy.data.actions[name + '_Rig']
        for index, fraction in enumerate(fractions):
            set_fraction(action, fraction)
            vertices = evaluate()
            # Render re-evaluates animation. Freeze this sampled pose so a fitted
            # head cannot silently revert to the author pose during render.
            basis = {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}
            rig_basis = rig.matrix_basis.copy()
            rig.animation_data.action = None
            rig.matrix_basis = rig_basis
            for bone in rig.pose.bones: bone.matrix_basis = basis[bone.name]
            bpy.context.view_layer.update()
            frozen = evaluate()
            assert max((a - b).length for key in vertices for a, b in zip(vertices[key], frozen[key])) < .0001
            foot_vertices = [v for key, points in vertices.items() if '_Leg' in key for v in points]
            all_vertices = [v for points in vertices.values() for v in points]
            projected = [world_to_camera_view(scene, camera, v) for v in all_vertices]
            foot = world_to_camera_view(scene, camera, Vector((0, 0, 0)))
            filename = f'{direction}-{clip}-{index:02}.png'
            scene.render.filepath = str(FRAMES / filename)
            bpy.ops.render.render(write_still=True)
            records.append({'path': 'frames/' + filename, 'direction': direction, 'yaw_degrees': yaw,
                            'clip': clip, 'sample_fraction': fraction, 'author_time_seconds': fraction * deformation[clip]['duration_seconds'],
                            'foot_anchor_px': [foot.x * 128, (1 - foot.y) * 192],
                            'minimum_foot_vertex_z': min(v.z for v in foot_vertices),
                            'maximum_foot_vertex_z': max(v.z for v in foot_vertices),
                            'projected_mesh_bounds_px': [min(v.x for v in projected) * 128, (1 - max(v.y for v in projected)) * 192,
                                                         max(v.x for v in projected) * 128, (1 - min(v.y for v in projected)) * 192]})
report = {'sample_kind': 'three-direction ordinary unarmed skeleton art fit', 'author_version': 'KayKit Skeletons 1.0',
          'source_commit': '15b62b9bad122f72926c10fb14d622c73819fa54', 'source_cell_px': [128, 192],
          'sample_display_cell_px': [64, 96], 'sample_scale': .5, 'foot_anchor_px': [64, 158],
          'camera': {'projection': 'orthographic', 'elevation_degrees': 55, 'ortho_scale': 3.2},
          'render': {'blender': bpy.app.version_string, 'engine': 'Cycles CPU', 'samples': 40, 'denoising': False,
                     'view_transform': 'AgX', 'look': 'AgX - Medium High Contrast', 'fixed_light': True,
                     'material_change': 'skeleton roughness 0.75, metallic 0; author texture/glow retained'},
          'deformation': deformation, 'frames': records,
          'root_policy': 'No per-frame grounding, root motion removal or retiming',
          'head_fit_pitch_degrees': HEAD_PITCH_DEGREES,
          'pose_policy': 'Author animation unchanged' if not HEAD_PITCH_DEGREES else 'One constant head-bone pitch after the author pose; this is an adapted fit candidate, not an untouched author render',
          'render_pose_policy': 'Sampled pose frozen for render; evaluated vertex agreement checked before every frame',
          'shadow_policy': 'Transparent renders contain no ground or baked shadow; preview adds one independent static contact shadow',
          'boundary': 'Only 4 samples per clip and 3 headings; no production atlas or gameplay integration.'}
(OUTPUT / 'render-audit.json').write_text(json.dumps(report, indent=2) + '\n')
print('Rendered 36 authored frames with evaluated deformation evidence')
