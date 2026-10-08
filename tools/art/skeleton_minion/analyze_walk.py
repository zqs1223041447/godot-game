"""One bounded source-cycle measurement. Blender, no render or author code execution."""
import argparse
import hashlib
import json
import math
import statistics
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source-dir', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
source = args.source_dir / 'Skeleton_Minion.glb'
if not source.is_file():
    raise SystemExit('Missing external author model; use the pinned URL/SHA manifest. No automatic download.')
assert hashlib.sha256(source.read_bytes()).hexdigest() == '6ffc003f895bed0b074791e0e490846210a2e2f8fc7da300aba53cc185f95968'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source))
scene = bpy.context.scene
scene.render.fps = 24
rig = bpy.data.objects['Rig']
for track in list(rig.animation_data.nla_tracks): rig.animation_data.nla_tracks.remove(track)
action = bpy.data.actions['Walking_D_Skeletons_Rig']
rig.animation_data.action = action
duration = float(action.frame_range[1] - action.frame_range[0]) / 24
samples = []
for index in range(65):
    fraction = index / 64
    frame = action.frame_range[0] + fraction * (action.frame_range[1] - action.frame_range[0])
    scene.frame_set(math.floor(frame), subframe=frame % 1)
    graph = bpy.context.evaluated_depsgraph_get()
    feet = {}
    for side, name in [('l', 'Left'), ('r', 'Right')]:
        obj = bpy.data.objects['Skeleton_Minion_Leg' + name].evaluated_get(graph)
        mesh = obj.to_mesh()
        vertices = [obj.matrix_world @ v.co for v in mesh.vertices]
        obj.to_mesh_clear()
        ankle = rig.matrix_world @ rig.pose.bones['foot.' + side].head
        feet[side] = {'ankle': list(ankle), 'minimum_mesh_z': min(v.z for v in vertices),
                      'forward': -ankle.y}
    samples.append({'fraction': fraction, 'feet': feet})
# The unmodified author feet dip slightly below z=0 during stance. Select the
# low-foot, backward-travel intervals; do not synthesize a new contact plane.
fits = {}
pair_lengths = []
for side in ['l', 'r']:
    pairs = []
    for a, b in zip(samples, samples[1:]):
        fa, fb = a['feet'][side], b['feet'][side]
        backwards = fa['forward'] - fb['forward']
        if max(fa['minimum_mesh_z'], fb['minimum_mesh_z']) <= .005 and backwards > .0001:
            length = backwards / (b['fraction'] - a['fraction'])
            pairs.append({'start': a['fraction'], 'end': b['fraction'], 'cycle_distance_model': length})
            pair_lengths.append(length)
    assert len(pairs) >= 8, 'Insufficient actual stance samples'
    stance_fraction = sum(p['end'] - p['start'] for p in pairs)
    backward_stroke = sum(p['cycle_distance_model'] * (p['end'] - p['start']) for p in pairs)
    fits[side] = {'pairs': pairs, 'median_cycle_distance_model': statistics.median(p['cycle_distance_model'] for p in pairs),
                  'stance_cycle_fraction': stance_fraction, 'backward_stroke_model': backward_stroke,
                  'whole_stance_cycle_distance_model': backward_stroke / stance_fraction}
stride = sum(f['backward_stroke_model'] for f in fits.values()) / sum(f['stance_cycle_fraction'] for f in fits.values())
directions = []
for index, name in enumerate(['east', 'southeast', 'south', 'southwest', 'west', 'northwest', 'north', 'northeast']):
    angle = index * math.tau / 8
    source_px_per_model_unit = 192 / 3.2 * math.sqrt(math.cos(angle) ** 2 + (math.sin(angle) * math.sin(math.radians(55))) ** 2)
    world_distance = stride * source_px_per_model_unit / 1.3
    directions.append({'index': index, 'name': name, 'source_pixels_per_model_unit': source_px_per_model_unit,
                       'world_units_per_cycle': world_distance,
                       'fps_at_reference_65_4': 8 * 65.4 / world_distance,
                       'fps_at_chill_0_36_reference': 8 * 65.4 * .36 / world_distance})
report = {'schema_version': 1, 'author_clip': 'Walking_D_Skeletons', 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
          'duration_seconds': duration, 'sample_intervals': 64, 'stance_ground_threshold_model': .005,
          'marker': 'evaluated foot bone ankle; low-foot backward intervals selected by actual leg-mesh minimum z',
          'estimator': 'total measured backward ankle stroke / total low-foot backward cycle fraction; whole stance average, not a fit to instantaneous toe-roll speed',
          'cycle_distance_model': stride, 'left_right_fits': fits, 'directions': directions, 'samples': samples,
          'boundary': 'Finite source measurement, no render or foot correction. Toe roll, vertical motion, held 8 frames and heading quantization retain residual slip.'}
out = ROOT / 'docs/qa/undead-minion-integration'
out.mkdir(parents=True, exist_ok=True)
(out / 'source-walk-analysis.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'cycle_distance_model': stride, 'left_right': [fits[s]['median_cycle_distance_model'] for s in ['l', 'r']],
                  'world_distance_by_heading': [d['world_units_per_cycle'] for d in directions],
                  'reference_fps_by_heading': [d['fps_at_reference_65_4'] for d in directions]}, indent=2))
