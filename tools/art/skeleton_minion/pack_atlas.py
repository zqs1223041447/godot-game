#!/usr/bin/env python3
"""Pack the verified eight true headings into the existing retained actor layout."""
import hashlib
import json
import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'docs/qa/kaykit-skeleton-minion/eight-direction'
OUTPUT = ROOT / 'assets/actors/studies'
DIRECTIONS = ['east', 'southeast', 'south', 'southwest', 'west', 'northwest', 'north', 'northeast']
CLIPS = {'idle': [0, 4], 'walk': [4, 8], 'attack': [12, 6]}
audit = json.loads((SOURCE / 'render-audit.json').read_text())
assert audit['direction_order'] == DIRECTIONS and len(audit['frames']) == 144
assert audit['head_fit_pitch_degrees'] == -25 and audit['head_fit_scale'] == .85
assert audit['foot_anchor_px'] == [64, 158]
atlas = Image.new('RGBA', (2048, 1728))
records = []
seams = {}
for direction_index, direction in enumerate(DIRECTIONS):
    for clip, (offset, count) in CLIPS.items():
        clip_images = []
        for index in range(count):
            record = next(r for r in audit['frames'] if r['direction'] == direction and r['clip'] == clip and r['clip_frame_index'] == index)
            expected_fraction = index / (count - 1) if clip == 'attack' else index / count
            assert abs(record['sample_fraction'] - expected_fraction) < 1e-9
            assert max(abs(x - y) for x, y in zip(record['foot_anchor_px'], [64, 158])) < .001
            path = SOURCE / record['path']
            frame = Image.open(path)
            assert frame.mode == 'RGBA' and frame.size == (128, 192)
            bounds = frame.getchannel('A').getbbox()
            assert bounds and 0 < bounds[0] < bounds[2] < 128 and 0 < bounds[1] < bounds[3] < 192, (path, bounds)
            assert max(abs(a - b) for a, b in zip(bounds, record['projected_mesh_bounds_px'])) < 3, 'Render disagrees with evaluated pose'
            flat_index = direction_index * 18 + offset + index
            x, y = flat_index % 16 * 128, flat_index // 16 * 192
            atlas.paste(frame, (x, y))
            assert atlas.crop((x, y, x + 128, y + 192)).tobytes() == frame.tobytes()
            clip_images.append(frame.tobytes())
            records.append({'index': flat_index, 'path': str(path.relative_to(ROOT)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                            'region': [x, y, 128, 192], 'foot': [64, 158], 'direction': direction, 'clip': clip,
                            'source_fraction': expected_fraction, 'alpha_bounds': bounds})
        assert len(set(clip_images)) >= 3
for clip, (_, count) in CLIPS.items():
    for index in range(count):
        hashes = [r['sha256'] for r in records if r['clip'] == clip and r['index'] % 18 == CLIPS[clip][0] + index]
        assert len(set(hashes)) == 8, 'Directions were copied instead of rendered'
for clip in ['idle', 'walk']:
    assert audit['source_loop_audit'][clip]['source_endpoint_max_vertex_delta'] < .0001
OUTPUT.mkdir(parents=True, exist_ok=True)
atlas_path = OUTPUT / 'skeleton_minion_study.png'
atlas.save(atlas_path)
definition = {'schema_version': 1, 'coordinate_space': 'world', 'texture_path': 'res://assets/actors/studies/skeleton_minion_study.png',
              'direction_count': 8, 'world_units_per_source_pixel': 1 / (2 * .65), 'frames_per_direction': 18, 'fps': 12,
              'clips': CLIPS, 'frames': [{'region': r['region'], 'foot': r['foot']} for r in sorted(records, key=lambda r: r['index'])],
              'contact_shadow_half_size_world': [18, 8.04], 'provenance': {
                  'family': 'undead_minion_study', 'study_only': True, 'source_commit': audit['source_commit'],
                  'source_glb_sha256': '6ffc003f895bed0b074791e0e490846210a2e2f8fc7da300aba53cc185f95968',
                  'license': 'CC0; Kay Lousberg', 'source_manifest': 'art-studies/kaykit-skeleton-minion-1.0/source/source-manifest.json',
                  'head_pitch_degrees': -25, 'head_scale': .85, 'camera_elevation_degrees': 55,
                  'author_clips': {clip: r['author_animation'] for clip, r in audit['deformation'].items()},
                  'author_cycle_seconds': {clip: r['duration_seconds'] for clip, r in audit['deformation'].items()},
                  'display_clip_seconds': {'idle': 4 / 12, 'walk': 8 / 12, 'attack': 6 / 12},
                  'timing_boundary': 'Visual samples resampled to existing 12fps contract; gameplay clocks unchanged; walk is not completely foot-locked'}}
(OUTPUT / 'skeleton_minion_study.json').write_text(json.dumps(definition, indent=2) + '\n')
report = {'ok': True, 'frame_count': 144, 'directions': DIRECTIONS, 'clips': CLIPS, 'foot_anchor_px': [64, 158],
          'atlas_size': list(atlas.size), 'atlas_sha256': hashlib.sha256(atlas_path.read_bytes()).hexdigest(),
          'head_pitch_degrees': -25, 'head_scale': .85, 'source_cycle_checks': audit['source_loop_audit'],
          'minimum_rendered_foot_vertex_z': min(r['minimum_foot_vertex_z'] for r in audit['frames']),
          'sampled_ground_penetration_display_px': max(0, -min(r['minimum_sampled_foot_vertex_z'] for r in audit['source_loop_audit'].values())) * math.cos(math.radians(55)) * 30,
          'records': sorted(records, key=lambda r: r['index']),
          'boundary': 'Eight true rendered headings, alpha clipping and exact region packing checked; source cycle endpoint closure plus 64 ground phases. Not continuous-cycle, natural AI or gameplay validation.'}
(SOURCE / 'atlas-verification.json').write_text(json.dumps(report, indent=2) + '\n')
print('Packed and verified 144 true rendered frames, 8 directions, Idle4/Walk8/Attack6, 12fps retained layout')
