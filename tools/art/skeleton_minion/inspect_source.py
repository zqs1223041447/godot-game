#!/usr/bin/env python3
"""Inspect the pinned author GLB bytes, rather than trusting clip names."""
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / 'docs/qa/kaykit-skeleton-minion/source-audit.json'
SELECTED = ['Idle', 'Walking_D_Skeletons', 'Unarmed_Melee_Attack_Punch_A']


def inspect(source):
    for name in ['Skeleton_Minion.glb', 'skeleton_texture.png', 'LICENSE.txt']:
        if not (source / name).is_file():
            raise SystemExit(f'Missing external author file: {source / name}. Obtain the pinned official files listed in art-studies/kaykit-skeleton-minion-1.0/source/source-manifest.json; no automatic download is performed.')
    data = (source / 'Skeleton_Minion.glb').read_bytes()
    assert len(data) == 4814296
    assert hashlib.sha1(b'blob 4814296\0' + data).hexdigest() == '3b7e7ee4f1c8dd6dd99ddad27824ef1dc52ff12d'
    magic, version, length = struct.unpack_from('<4sII', data)
    assert (magic, version, length) == (b'glTF', 2, len(data))
    json_length, kind = struct.unpack_from('<I4s', data, 12)
    assert kind == b'JSON'
    gltf = json.loads(data[20:20 + json_length])
    offset = 20 + json_length
    binary_length, kind = struct.unpack_from('<I4s', data, offset)
    assert kind == b'BIN\0'
    binary = data[offset + 8:offset + 8 + binary_length]

    def accessor(index):
        entry = gltf['accessors'][index]
        view = gltf['bufferViews'][entry['bufferView']]
        assert 'sparse' not in entry and view['buffer'] == 0
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[entry['type']]
        assert entry['componentType'] == 5126
        start = view.get('byteOffset', 0) + entry.get('byteOffset', 0)
        stride = view.get('byteStride', width * 4)
        return [struct.unpack_from('<' + 'f' * width, binary, start + stride * i) for i in range(entry['count'])]

    selected = {}
    inventory = []
    for animation in gltf['animations']:
        moving = []
        duration = 0.0
        paths = {}
        for channel in animation['channels']:
            sampler = animation['samplers'][channel['sampler']]
            times, values = accessor(sampler['input']), accessor(sampler['output'])
            assert len(times) == len(values) and sampler.get('interpolation', 'LINEAR') == 'LINEAR'
            assert all(a[0] <= b[0] for a, b in zip(times, times[1:]))
            duration = max(duration, times[-1][0])
            delta = max(abs(component - values[0][j]) for value in values for j, component in enumerate(value))
            if delta > 1e-6:
                target = channel['target']
                moving.append({'node': gltf['nodes'][target['node']].get('name'), 'path': target['path'],
                               'keys': len(times), 'max_component_change': delta})
                paths[target['path']] = paths.get(target['path'], 0) + 1
        record = {'name': animation['name'], 'duration_seconds': duration,
                  'channels': len(animation['channels']), 'varying_channels': len(moving), 'varying_paths': paths}
        inventory.append(record)
        if animation['name'] in SELECTED:
            assert duration > 0 and moving
            selected[animation['name']] = dict(record, varying_channel_evidence=moving)
    assert set(selected) == set(SELECTED)
    assert len(gltf['skins']) == 1 and len(gltf['skins'][0]['joints']) == 41
    skinned_nodes = [node for node in gltf['nodes'] if 'skin' in node and 'mesh' in node]
    assert len(skinned_nodes) == 9
    for node in skinned_nodes:
        for primitive in gltf['meshes'][node['mesh']]['primitives']:
            assert {'JOINTS_0', 'WEIGHTS_0'} <= primitive['attributes'].keys()
    image_view = gltf['bufferViews'][gltf['images'][0]['bufferView']]
    start = image_view.get('byteOffset', 0)
    embedded = binary[start:start + image_view['byteLength']]
    assert embedded == (source / 'skeleton_texture.png').read_bytes()
    assert b'Creative Commons Zero, CC0' in (source / 'LICENSE.txt').read_bytes()
    return {'ok': True, 'locked_commit': '15b62b9bad122f72926c10fb14d622c73819fa54',
            'glb_sha256': hashlib.sha256(data).hexdigest(), 'skin_count': 1, 'joint_count': 41,
            'skinned_mesh_nodes': 9, 'embedded_texture_equals_adjacent_png': True,
            'animation_count': len(inventory), 'inventory': inventory, 'selected': selected,
            'boundary': 'Binary curves and bindings verified here; evaluated deformation is checked separately in Blender.'}


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, required=True, help='External directory with the three pinned official author files; no download is performed')
    report = inspect(parser.parse_args().source_dir)
    OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('Verified one 41-joint skin, nine skinned meshes, actual selected varying curves and embedded texture')
