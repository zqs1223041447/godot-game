#!/usr/bin/env python3
"""Attach the one measured walk cycle to the unchanged existing 144-frame atlas."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
analysis = json.loads((ROOT / 'docs/qa/undead-minion-integration/source-walk-analysis.json').read_text())
atlas = ROOT / 'assets/actors/studies/skeleton_minion_study.png'
assert hashlib.sha256(atlas.read_bytes()).hexdigest() == '4826d0541b1c1548a79c0128b625bd8393cb3abaea4af9ed06e6546cd037fcfd'
assert analysis['sample_intervals'] == 64 and len(analysis['directions']) == 8
assert analysis['source_sha256'] == '6ffc003f895bed0b074791e0e490846210a2e2f8fc7da300aba53cc185f95968'
manifest = {'frame_width': 128, 'frame_height': 192, 'columns': 16, 'frame_count': 144, 'foot_anchor_px': [64, 158],
            'family': 'undead_minion', 'atlas_sha256': hashlib.sha256(atlas.read_bytes()).hexdigest(),
            'direction_order': [d['name'] for d in analysis['directions']],
            'walk_world_units_per_cycle': [d['world_units_per_cycle'] for d in analysis['directions']],
            'walk_calibration': {'source_clip': analysis['author_clip'], 'source_cycle_seconds': analysis['duration_seconds'],
                                 'stride_model_units': analysis['cycle_distance_model'], 'estimator': analysis['estimator'],
                                 'measurement': 'docs/qa/undead-minion-integration/source-walk-analysis.json',
                                 'projection': '55deg, ortho3.2, 128x192 source; source pixel / 1.3 world units',
                                 'boundary': 'Whole stance stroke average. Toe roll, 8 held phases, quantized headings, impulses and long-frame cap retain residual slide.'},
            'provenance': {'commit': '15b62b9bad122f72926c10fb14d622c73819fa54', 'license': 'CC0, Kay Lousberg',
                           'source_sha256': analysis['source_sha256'], 'head_pitch_degrees': -25, 'head_scale': .85},
            'binding': 'Read-only existing ruins_garden map_spawn_key plus normal crawler generation0 root identity. Archetype unchanged.'}
(ROOT / 'assets/actors/undead_minion.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Prepared measured direction strides; existing atlas bytes unchanged')
