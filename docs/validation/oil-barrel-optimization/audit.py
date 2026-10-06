"""Inspect the original and optimized GLB without changing either asset."""
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
        assert 'byteStride' not in view and 'sparse' not in item
        return np.frombuffer(binary, dtype=dtype, count=item['count'] * columns,
                             offset=offset).reshape(item['count'], columns)

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
        images.append({'mime_type': item['mimeType'], 'size': list(image.size)})
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


report = {
    'original': inspect('art_source/retired_props/2026-09-29/oil_barrel.glb'),
    'optimized': inspect('assets/models/oil_barrel/oil_barrel.glb'),
}
candidate = report['optimized']
assert candidate['triangles'] == 3000
assert candidate['geometric_nonmanifold_edges'] == 0
assert candidate['degenerate_triangles'] == 0
assert candidate['scenes'] == candidate['nodes'] == candidate['meshes'] == candidate['materials'] == 1
assert len(candidate['images']) == 3 and all(i['size'] == [1024, 1024] for i in candidate['images'])
assert not candidate['extensions_required']
assert candidate['max_horizontal_radius'] <= 0.32958984 + 1e-7
assert abs(candidate['bounds_min'][1] + 0.5) < 1e-6
assert abs(candidate['bounds_max'][1] - 0.5) < 1e-6
(OUTPUT / 'audit.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, indent=2))

if (OUTPUT / 'original.png').exists() and (OUTPUT / 'optimized.png').exists():
    panels = [Image.open(OUTPUT / name).convert('RGB').resize((600, 510))
              for name in ['original.png', 'optimized.png']]
    comparison = Image.new('RGB', (1200, 555), (30, 35, 42))
    draw = ImageDraw.Draw(comparison)
    font_path = Path('C:/Windows/Fonts/arial.ttf')
    font = ImageFont.truetype(str(font_path), 22) if font_path.exists() else ImageFont.load_default()
    for i, panel in enumerate(panels):
        comparison.paste(panel, (600 * i, 45))
    draw.text((20, 12), 'Original | 499,846 triangles', font=font, fill='white')
    draw.text((620, 12), 'Optimized | 3,000 triangles', font=font, fill='white')
    comparison.save(OUTPUT / 'comparison.png')
