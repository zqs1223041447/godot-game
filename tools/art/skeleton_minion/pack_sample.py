#!/usr/bin/env python3
"""Package only the bounded frame evidence; no production atlas is generated."""
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / 'docs/qa/kaykit-skeleton-minion'
DIRECTIONS = ['south', 'southeast', 'east']
CLIPS = ['idle', 'walk', 'attack']
ground = Image.open(ROOT / 'assets/environment/garden_ground.png').convert('RGB')
ground = ground.resize(tuple(round(x * .26) for x in ground.size), Image.Resampling.LANCZOS)
ground = ImageChops.multiply(ground, Image.new('RGB', ground.size, '#d4d7c1'))


def cell(frame, size=(80, 112)):
    result = ground.crop((64, 64, 64 + size[0], 64 + size[1])).convert('RGBA')
    shadow = Image.new('RGBA', size)
    draw = ImageDraw.Draw(shadow)
    for ratio in [1, .72]:
        points = [(40 + math.cos(i * math.tau / 24) * 11.7 * ratio,
                   89 + math.sin(i * math.tau / 24) * 5.226 * ratio) for i in range(24)]
        layer = Image.new('RGBA', size)
        ImageDraw.Draw(layer).polygon(points, fill=(34, 37, 28, round(.38 * 255)))
        shadow = Image.alpha_composite(shadow, layer)
    result = Image.alpha_composite(result, shadow)
    result.alpha_composite(frame.resize((64, 96), Image.Resampling.LANCZOS), (8, 10))
    return result.convert('RGB')


reports = {}
manifest = []
for variant, folder in [('author', OUTPUT), ('head-fit', OUTPUT / 'head-fit')]:
    audit = json.loads((folder / 'render-audit.json').read_text())
    assert len(audit['frames']) == 36
    frames = {}
    frame_records = []
    for record in audit['frames']:
        path = folder / record['path']
        image = Image.open(path)
        assert image.mode == 'RGBA' and image.size == (128, 192)
        bbox = image.getchannel('A').getbbox()
        assert bbox and 0 < bbox[0] < bbox[2] < 128 and 0 < bbox[1] < bbox[3] < 192, (path, bbox)
        assert max(abs(a - b) for a, b in zip(bbox, record['projected_mesh_bounds_px'])) < 3, 'Rendered silhouette disagrees with evaluated pose'
        assert max(abs(x - y) for x, y in zip(record['foot_anchor_px'], [64, 158])) < .001
        frames[path.stem] = image.copy()
        frame_records.append({'path': str(path.relative_to(OUTPUT)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                              'alpha_bounds': bbox, 'visible_display_extent_px': [(bbox[2] - bbox[0]) / 2, (bbox[3] - bbox[1]) / 2]})
    for clip in CLIPS:
        for index in range(4):
            assert len({frames[f'{direction}-{clip}-{index:02}'].tobytes() for direction in DIRECTIONS}) == 3, 'Heading transform was not applied'
        for direction in DIRECTIONS:
            assert len({frames[f'{direction}-{clip}-{index:02}'].tobytes() for index in range(4)}) >= 3, 'No visible frame variation'
    contact = Image.new('RGB', (1008, 434), '#23211f')
    draw = ImageDraw.Draw(contact)
    draw.text((24, 12), f'KayKit Skeletons 1.0 / {variant} / 64 x 96 cells / four authored time samples', fill='white')
    for row, direction in enumerate(DIRECTIONS):
        for column, clip in enumerate(CLIPS):
            for index in range(4):
                contact.paste(cell(frames[f'{direction}-{clip}-{index:02}']), (24 + (column * 4 + index) * 80, 40 + row * 128))
            draw.text((24 + column * 320, 40 + row * 128 + 114), f'{direction} / {clip}: 0, 25, 50, 75%', fill='white')
    contact.save(folder / 'actual-size-contact.png')
    for clip in CLIPS:
        gif_frames = []
        for index in range(4):
            canvas = Image.new('RGB', (288, 156), '#23211f')
            draw = ImageDraw.Draw(canvas)
            draw.text((10, 6), f'{variant} / {clip} / four-frame sample', fill='white')
            for column, direction in enumerate(DIRECTIONS):
                canvas.paste(cell(frames[f'{direction}-{clip}-{index:02}']), (12 + column * 88, 26))
                draw.text((12 + column * 88, 140), direction, fill='white')
            gif_frames.append(canvas)
        ms = round(audit['deformation'][clip]['duration_seconds'] / 4 * 100) * 10
        gif_frames[0].save(folder / f'{clip}-sample.gif', save_all=True, append_images=gif_frames[1:], duration=ms, loop=0)
    deepest = min(r['minimum_foot_vertex_z'] for r in audit['frames'])
    reports[variant] = {'frame_count': 36, 'distinct_headings_per_pose': 3, 'no_alpha_clipping': True,
                        'visible_display_height_px_range': [min(r['visible_display_extent_px'][1] for r in frame_records),
                                                            max(r['visible_display_extent_px'][1] for r in frame_records)],
                        'minimum_sampled_foot_vertex_z': deepest,
                        'sampled_vertical_ground_penetration_display_px': max(0, -deepest) * math.cos(math.radians(55)) * (192 / 3.2) * .5,
                        'foot_anchor_px': [64, 158], 'frames': frame_records}
    manifest.extend(frame_records)
# Compare the same times, headings and feet; the fit is a static head adjustment only.
before = json.loads((OUTPUT / 'render-audit.json').read_text())
after = json.loads((OUTPUT / 'head-fit/render-audit.json').read_text())
for a, b in zip(before['frames'], after['frames']):
    for key in ['path', 'direction', 'yaw_degrees', 'clip', 'sample_fraction', 'author_time_seconds', 'foot_anchor_px', 'minimum_foot_vertex_z', 'maximum_foot_vertex_z']:
        assert a[key] == b[key], ('Non-head fit changed', key)
    assert Image.open(OUTPUT / 'head-fit' / b['path']).tobytes() != Image.open(OUTPUT / a['path']).tobytes(), 'Head fit reverted during render'
(OUTPUT / 'frame-verification.json').write_text(json.dumps({'ok': True, 'variants': reports,
    'scope': '36 sparse samples per variant; alpha/foot/heading checks and author-time GIF packing only. Ground penetration is sampled, not a full-cycle bound.'}, indent=2) + '\n')
print('Verified 72 unclipped frames, three distinct headings, common foot anchors and unchanged feet in head-fit comparison')
