"""Inspect meshoptimizer trials and compose their matching Godot previews."""
from pathlib import Path
import hashlib
import io
import json
import struct

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = Path(__file__).resolve().parent


def inspect(relative_path):
    path = ROOT / relative_path
    data = path.read_bytes()
    magic, version, length = struct.unpack_from('<III', data)
    assert magic == 0x46546C67 and version == 2 and length == len(data)
    json_length = struct.unpack_from('<I', data, 12)[0]
    document = json.loads(data[20:20 + json_length])
    binary = data[28 + json_length:]

    def accessor(index):
        item = document['accessors'][index]
        view = document['bufferViews'][item['bufferView']]
        dtype = {5123: '<u2', 5125: '<u4', 5126: '<f4'}[item['componentType']]
        columns = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[item['type']]
        offset = view.get('byteOffset', 0) + item.get('byteOffset', 0)
        assert 'sparse' not in item
        return np.ndarray((item['count'], columns), dtype=dtype, buffer=binary,
                          offset=offset, strides=(view.get('byteStride', columns * np.dtype(dtype).itemsize), np.dtype(dtype).itemsize))

    if not document.get('meshes'):
        return {'path': relative_path, 'bytes': len(data), 'triangles': 0,
                'vertices': 0, 'meshes': 0, 'usable_geometry': False,
                'sha256': hashlib.sha256(data).hexdigest()}
    assert len(document['meshes']) == 1
    primitive = document['meshes'][0]['primitives'][0]
    assert primitive.get('mode', 4) == 4
    positions = accessor(primitive['attributes']['POSITION'])
    indices = accessor(primitive['indices']).reshape(-1, 3)
    assert np.isfinite(positions).all() and indices.max() < len(positions)
    for index in primitive['attributes'].values():
        assert np.isfinite(accessor(index)).all()
    _, inverse = np.unique(positions, axis=0, return_inverse=True)
    faces = inverse[indices]
    edges = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
    _, edge_counts = np.unique(np.sort(edges, axis=1), axis=0, return_counts=True)
    triangles = positions[indices]
    areas = np.linalg.norm(np.cross(triangles[:, 1] - triangles[:, 0],
                                    triangles[:, 2] - triangles[:, 0]), axis=1) / 2
    images = []
    for item in document['images']:
        view = document['bufferViews'][item['bufferView']]
        offset = view.get('byteOffset', 0)
        image = Image.open(io.BytesIO(binary[offset:offset + view['byteLength']]))
        images.append({'mime_type': item['mimeType'], 'size': list(image.size),
                       'sha256': hashlib.sha256(binary[offset:offset + view['byteLength']]).hexdigest()})
    return {
        'path': relative_path, 'sha256': hashlib.sha256(data).hexdigest(),
        'bytes': len(data), 'scenes': len(document['scenes']),
        'nodes': len(document['nodes']), 'meshes': len(document['meshes']),
        'materials': len(document['materials']), 'vertices': len(positions),
        'unique_positions': int(inverse.max() + 1), 'triangles': len(indices),
        'bounds_min': positions.min(axis=0).tolist(),
        'bounds_max': positions.max(axis=0).tolist(),
        'dimensions': (positions.max(axis=0) - positions.min(axis=0)).tolist(),
        'max_horizontal_radius': float(np.linalg.norm(positions[:, [0, 2]], axis=1).max()),
        'geometric_boundary_edges': int((edge_counts == 1).sum()),
        'geometric_nonmanifold_edges': int((edge_counts != 2).sum()),
        'degenerate_triangles': int((areas <= 1e-12).sum()),
        'images': images, 'extensions_required': document.get('extensionsRequired', []),
    }


paths = {
    'original': 'art_source/retired_props/2026-09-29/oil_barrel.glb',
    'blender': 'assets/models/oil_barrel/oil_barrel.glb',
}
for name in ['strict', 'permissive', 'permissive-update', 'permissive-5pct',
             'aggressive', 'permissive-maxerror']:
    paths[name] = f'art_source/oil_barrel/meshoptimizer-v1.3/{name}.glb'
results = {name: inspect(path) for name, path in paths.items()}
assert results['original']['sha256'] == '58326447acdfb7d8ba9fc90c8efc345fd9b8e365d93393f287aba8b192646694'
assert results['blender']['sha256'] == '3efba222beaab8d1223d457372a8cf8eb46a40419718443e3a38ff248d6267e5'
source_images = [i['sha256'] for i in results['original']['images']]
for name in ['strict', 'permissive', 'permissive-update', 'permissive-5pct', 'aggressive']:
    assert [i['sha256'] for i in results[name]['images']] == source_images
report = {'tool': 'gltfpack 1.3', 'target_triangles': 3000,
          'quantization': False, 'mesh_compression': False, 'results': results}
(OUTPUT / 'audit.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
for name, result in results.items():
    print(name, json.dumps({k: result[k] for k in ['triangles', 'vertices', 'bytes']}))

font_path = Path('C:/Windows/Fonts/arial.ttf')
font = ImageFont.truetype(str(font_path), 19) if font_path.exists() else ImageFont.load_default()


def compose(names, filename, titles):
    canvas = Image.new('RGB', (500 * len(names), 470), (30, 35, 42))
    draw = ImageDraw.Draw(canvas)
    for i, (name, title) in enumerate(zip(names, titles)):
        panel = Image.open(OUTPUT / f'{name}.png').convert('RGB').resize((500, 425))
        canvas.paste(panel, (500 * i, 45))
        draw.text((500 * i + 12, 12), title, font=font, fill='white')
    canvas.save(OUTPUT / filename)


compose(['original', 'blender', 'permissive-update'], 'comparison.png',
        ['Original | 499,846 triangles', 'Blender + bake | 3,000 triangles',
         'meshoptimizer | 22,154 triangles'])
compose(['permissive-update', 'aggressive'], 'quality-limit.png',
        ['Preserve appearance | 22,154 triangles', 'Aggressive | 2,763 triangles'])


