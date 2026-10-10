"""Prepare single-mesh static GLBs; publish only after visual review. Requires numpy."""
import argparse
import copy
import hashlib
import json
import math
import re
import struct
import subprocess
from collections import Counter
from pathlib import Path

import numpy as np


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def decode(path):
    data = Path(path).read_bytes()
    require(len(data) >= 28 and struct.unpack_from('<4sII', data) == (b'glTF', 2, len(data)), 'Invalid GLB header')
    n, kind = struct.unpack_from('<II', data, 12)
    require(kind == 0x4e4f534a and 28+n <= len(data), 'Invalid JSON chunk')
    doc = json.loads(data[20:20+n])
    bn, kind = struct.unpack_from('<II', data, 20+n)
    require(kind == 0x004e4942 and 28+n+bn == len(data), 'Expected one embedded binary chunk')
    return doc, bytearray(data[28+n:]), data


def accessor(doc, binary, index):
    acc = doc['accessors'][index]
    require(not acc.get('sparse') and not acc.get('normalized'), 'Sparse/normalized accessor unsupported')
    view = doc['bufferViews'][acc['bufferView']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[acc['type']]
    dtype = np.dtype({5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}[acc['componentType']])
    start = view.get('byteOffset', 0)
    offset = acc.get('byteOffset', 0)
    stride = view.get('byteStride', dtype.itemsize*width)
    end = offset + (acc['count']-1)*stride + dtype.itemsize*width
    require(view.get('buffer', 0) == 0 and acc['count'] > 0 and stride >= dtype.itemsize*width
            and offset >= 0 and start >= 0 and end <= view['byteLength']
            and start+view['byteLength'] <= len(binary), 'Accessor exceeds buffer')
    return np.ndarray((acc['count'], width), dtype=dtype, buffer=binary,
                      offset=start+offset, strides=(stride, dtype.itemsize))


def supported(doc, binary):
    require(not any(doc.get(k) for k in ['animations', 'skins', 'extensionsUsed', 'extensionsRequired']),
            'Animation, skin or extensions require another tool')
    require(len(doc['nodes']) == len(doc['meshes']) == len(doc['buffers']) == 1, 'Expected one mesh node/buffer')
    node = doc['nodes'][0]
    require(node.get('mesh') == 0 and not any(k in node for k in ['matrix', 'translation', 'rotation', 'scale', 'children']),
            'Bake node transforms with another tool first')
    require(len(doc['meshes'][0]['primitives']) == 1, 'Multi-primitive model requires another tool')
    prim = doc['meshes'][0]['primitives'][0]
    require(prim.get('mode', 4) == 4 and not prim.get('targets') and not prim.get('extensions'), 'Only static TRIANGLES supported')
    require(set(prim['attributes']) in ({'POSITION', 'NORMAL', 'TEXCOORD_0'},
                                      {'POSITION', 'NORMAL', 'TEXCOORD_0', 'TANGENT'}), 'Unsupported vertex attributes')
    for semantic, index in prim['attributes'].items():
        expected = {'POSITION': 'VEC3', 'NORMAL': 'VEC3', 'TEXCOORD_0': 'VEC2', 'TANGENT': 'VEC4'}[semantic]
        require(doc['accessors'][index]['componentType'] == 5126 and doc['accessors'][index]['type'] == expected,
                'Expected float vertex attributes')
        require(np.isfinite(accessor(doc, binary, index)).all(), 'Non-finite attributes')
    pos = accessor(doc, binary, prim['attributes']['POSITION'])
    require(all(len(accessor(doc, binary, i)) == len(pos) for i in prim['attributes'].values()), 'Attribute count mismatch')
    ids = accessor(doc, binary, prim['indices'])
    require(ids.dtype.kind == 'u' and ids.shape[1] == 1 and len(ids) % 3 == 0 and ids.max() < len(pos), 'Invalid triangle indices')
    require(doc.get('images') and all(im.get('mimeType') == 'image/png' and 'bufferView' in im and not im.get('uri')
                                    for im in doc['images']), 'Expected embedded PNG textures')
    return prim


def encode(doc, binary):
    doc['buffers'][0]['byteLength'] = len(binary)
    js = json.dumps(doc, separators=(',', ':')).encode()
    js += b' '*(-len(js) % 4)
    buf = bytes(binary) + b'\0'*(-len(binary) % 4)
    return (struct.pack('<4sII', b'glTF', 2, 28+len(js)+len(buf))
            + struct.pack('<II', len(js), 0x4e4f534a) + js
            + struct.pack('<II', len(buf), 0x004e4942) + buf)


def image_bytes(doc, binary):
    result = []
    for im in doc['images']:
        view = doc['bufferViews'][im['bufferView']]
        start = view.get('byteOffset', 0)
        require(view.get('buffer', 0) == 0 and start >= 0 and view['byteLength'] > 0
                and start+view['byteLength'] <= len(binary), 'Invalid image buffer')
        result.append(bytes(binary[start:start+view['byteLength']]))
    return result


def normalize(rows):
    lengths = np.linalg.norm(rows, axis=1, keepdims=True)
    require(np.isfinite(lengths).all() and np.min(lengths) > 1e-8, 'Zero normal/tangent requires mesh repair')
    return rows/lengths


def fit(source, dest, size, origin, rotation_y):
    doc, binary, original = decode(source)
    prim = supported(doc, binary)
    target = np.asarray(size, dtype=np.float64)
    require(target.shape == (3,) and np.isfinite(target).all() and (target > 0).all()
            and math.isfinite(rotation_y) and origin in ['center', 'bottom-center'], 'Invalid fit parameters')
    theta = math.radians(rotation_y)
    rot = np.array([[math.cos(theta), 0, math.sin(theta)], [0, 1, 0], [-math.sin(theta), 0, math.cos(theta)]])
    positions = accessor(doc, binary, prim['attributes']['POSITION'])
    pts = positions.astype(np.float64) @ rot.T
    low, high = pts.min(axis=0), pts.max(axis=0)
    require(((high-low) > 1e-6).all(), 'Flat/empty geometry cannot fit a 3D envelope')
    scale = target/(high-low)
    pivot = (low+high)/2
    shift = np.array([0, target[1]/2 if origin == 'bottom-center' else 0, 0])
    normals = accessor(doc, binary, prim['attributes']['NORMAL'])
    nr = normalize((normals.astype(np.float64) @ rot.T)/scale)
    positions[:] = (pts-pivot)*scale + shift
    normals[:] = nr
    if 'TANGENT' in prim['attributes']:
        tangents = accessor(doc, binary, prim['attributes']['TANGENT'])
        require(np.isin(tangents[:, 3], [-1, 1]).all(), 'Invalid tangent handedness requires mesh repair')
        tr = (tangents[:, :3].astype(np.float64) @ rot.T)*scale
        tr -= nr*np.sum(tr*nr, axis=1, keepdims=True)
        # Derive collapsed tangents from UV triangles; fall back to an orthogonal axis.
        bad = np.linalg.norm(tr, axis=1) < 1e-8
        if bad.any():
            ids = accessor(doc, binary, prim['indices']).reshape(-1, 3)
            uv = accessor(doc, binary, prim['attributes']['TEXCOORD_0']).astype(np.float64)
            e1 = positions[ids[:, 1]]-positions[ids[:, 0]]; e2 = positions[ids[:, 2]]-positions[ids[:, 0]]
            u1 = uv[ids[:, 1]]-uv[ids[:, 0]]; u2 = uv[ids[:, 2]]-uv[ids[:, 0]]
            det = u1[:, 0]*u2[:, 1]-u1[:, 1]*u2[:, 0]; good = np.abs(det) > 1e-12
            tri_t = np.zeros_like(e1, dtype=np.float64)
            tri_t[good] = (e1[good]*u2[good, 1, None]-e2[good]*u1[good, 1, None])/det[good, None]
            tri_t *= np.linalg.norm(np.cross(e1, e2), axis=1, keepdims=True)
            sums = np.zeros_like(tr)
            for col in range(3): np.add.at(sums, ids[:, col], tri_t)
            sums -= nr*np.sum(sums*nr, axis=1, keepdims=True)
            for i in np.flatnonzero(bad):
                tr[i] = sums[i] if np.linalg.norm(sums[i]) >= 1e-8 else np.cross(np.eye(3)[np.argmin(np.abs(nr[i]))], nr[i])
        tangents[:, :3] = normalize(tr)
    acc = doc['accessors'][prim['attributes']['POSITION']]
    acc['min'] = positions.min(axis=0).tolist(); acc['max'] = positions.max(axis=0).tolist()
    require(np.allclose(positions.max(axis=0)-positions.min(axis=0), target, atol=1e-6, rtol=1e-6), 'Fit failed')
    dest.write_bytes(encode(doc, binary))
    require(Path(source).read_bytes() == original, 'Source changed')
    return {'source_sha256': sha(original), 'size_m': target.tolist(), 'origin': origin,
            'rotation_y_degrees': rotation_y, 'fit_scale_xyz': scale.tolist(),
            'collapsed_tangents_repaired': int(bad.sum()) if 'TANGENT' in prim['attributes'] else 0}


def editable(doc, binary, folder, asset):
    folder.mkdir()
    ext = copy.deepcopy(doc); compact = bytearray(); views = []; mapping = {}
    image_views = {im['bufferView'] for im in doc['images']}
    require(not any(acc['bufferView'] in image_views for acc in doc['accessors']), 'Shared image/geometry view unsupported')
    for i, view in enumerate(doc['bufferViews']):
        if i in image_views: continue
        compact.extend(b'\0'*(-len(compact) % 4)); new = copy.deepcopy(view)
        start = view.get('byteOffset', 0); new['byteOffset'] = len(compact)
        compact.extend(binary[start:start+view['byteLength']]); mapping[i] = len(views); views.append(new)
    for acc in ext['accessors']: acc['bufferView'] = mapping[acc['bufferView']]
    for i, (im, data) in enumerate(zip(ext['images'], image_bytes(doc, binary))):
        im.pop('bufferView'); im['uri'] = f'{asset}_texture_{i}.png'
        (folder/im['uri']).write_bytes(data)
    ext['bufferViews'] = views; ext['buffers'] = [{'uri': asset+'.bin', 'byteLength': len(compact)}]
    for i in range(len(doc['accessors'])):
        require(np.array_equal(accessor(doc, binary, i), accessor(ext, compact, i)), 'Editable export changed geometry')
    (folder/(asset+'.bin')).write_bytes(compact)
    save_json(folder/(asset+'.gltf'), ext)


def prepare(a):
    source = Path(a.source).resolve(); output = Path(a.output).resolve()
    require(not output.exists(), 'Use a new ignored output folder')
    require(re.fullmatch(r'[a-z][a-z0-9_\-]*', a.asset), 'Invalid asset name')
    require(a.ratio is None or (a.gltfpack and math.isfinite(a.ratio) and 0 < a.ratio <= 1), 'Ratio needs gltfpack and must be in (0,1]')
    require(math.isfinite(a.error) and a.error > 0, 'Invalid reduction error')
    original = source.read_bytes(); doc, binary, _ = decode(source); prim = supported(doc, binary)
    raw_triangles = len(accessor(doc, binary, prim['indices']))//3
    original_images = image_bytes(doc, binary)
    output.mkdir(parents=True)
    first = fit(source, output/'fitted.glb', a.size, a.origin, a.rotation_y)
    candidate = output/'fitted.glb'; args = []
    if a.ratio is not None:
        candidate = output/'reduced.glb'
        args = ['-si', str(a.ratio), '-se', str(a.error), '-sp', '-sv', '-noq', '-kn', '-km']
        process = subprocess.run([a.gltfpack, '-i', str(output/'fitted.glb'), '-o', str(candidate), *args], capture_output=True, text=True)
        (output/'gltfpack.log').write_text(process.stdout+process.stderr, encoding='utf-8')
        require(process.returncode == 0, 'gltfpack failed; inspect gltfpack.log')
        version = subprocess.run([a.gltfpack, '-v'], capture_output=True, text=True)
        require(version.returncode == 0, 'Cannot identify gltfpack version')
        first['gltfpack_version'] = (version.stdout+version.stderr).strip()
    fit(candidate, output/'final.glb', a.size, a.origin, 0)
    doc, binary, final = decode(output/'final.glb'); prim = supported(doc, binary)
    require(image_bytes(doc, binary) == original_images, 'Embedded textures changed')
    pos = accessor(doc, binary, prim['attributes']['POSITION']); faces = accessor(doc, binary, prim['indices']).reshape(-1, 3)
    _, mapping = np.unique(np.round(pos/1e-6).astype(np.int64), axis=0, return_inverse=True)
    welded = mapping[faces]
    edges = Counter(tuple(sorted([int(f[x]), int(f[y])])) for f in welded for x, y in [(0, 1), (1, 2), (2, 0)])
    area = np.linalg.norm(np.cross(pos[faces[:, 1]]-pos[faces[:, 0]], pos[faces[:, 2]]-pos[faces[:, 0]]), axis=1)
    first.update({'asset': a.asset, 'up': '+Y', 'front_intended': a.front, 'raw_triangles': raw_triangles,
                  'triangles': len(faces), 'vertices': len(pos), 'final_sha256': sha(final),
                  'texture_sha256': [sha(im) for im in original_images], 'gltfpack_args': args,
                  'bounds_min_m': pos.min(axis=0).tolist(), 'bounds_max_m': pos.max(axis=0).tolist(),
                  'topology': {'weld_m': 1e-6, 'boundary_edges': sum(n == 1 for n in edges.values()),
                               'nonmanifold_edges': sum(n > 2 for n in edges.values()),
                               'duplicate_triangles': len(faces)-len(np.unique(np.sort(welded, axis=1), axis=0)),
                               'zero_area_triangles': int((area < 1e-12).sum())},
                  'visual_review': 'required',
                  'source_path': source.relative_to(Path.cwd()).as_posix() if source.is_relative_to(Path.cwd()) else str(source)})
    job_path = source.parent/'job.json'
    if job_path.exists():
        job = json.loads(job_path.read_text(encoding='utf-8'))
        first['generation'] = {k: job[k] for k in ['profile', 'profile_sha256', 'seed', 'resolution', 'prompt_id', 'reference_sha256'] if k in job}
    editable(doc, binary, output/'editable', a.asset)
    require(source.read_bytes() == original, 'Source changed during preparation')
    save_json(output/'model_parameters.json', first)
    return first


def wrapper_bytes(before, asset, hide):
    text = before.decode('utf-8')
    require(re.match(r'^\ufeff?\[gd_scene[^\r\n]*\]', text), 'Missing Godot scene header')
    headers = re.findall(r'(?m)^\[node [^\r\n]*\]', text)
    require('id="generated_model"' not in text and not any('name="Asset"' in h and 'parent="Visuals/Model"' in h for h in headers),
            'Already integrated; edit the existing instance directly')
    heading = '[node name="Model" type="Node3D" parent="Visuals"]'
    require(text.count(heading) == 1, 'Expected Visuals/Model Node3D wrapper')
    newline = '\r\n' if '\r\n' in text else '\n'
    resource = f'[ext_resource type="PackedScene" path="res://assets/models/{asset}/{asset}.glb" id="generated_model"]'
    text = re.sub(r'^(\ufeff?\[gd_scene[^\r\n]*\])', lambda m: m[0]+newline+newline+resource, text, count=1)
    # Godot uses load_steps as a hint; keep it correct when the original declares it.
    text = re.sub(r'^(\ufeff?\[gd_scene[^\r\n]*load_steps=)(\d+)', lambda m: m[1]+str(int(m[2])+1), text, count=1)
    model_block = re.search(r'(?ms)^'+re.escape(heading)+r'.*?(?=^\[|\Z)', text)
    require(model_block is not None, 'Missing Model block')
    tail = model_block.end()
    separator = '' if text[:tail].endswith(newline+newline) else newline+newline
    text = text[:tail]+separator+'[node name="Asset" parent="Visuals/Model" instance=ExtResource("generated_model")]'+newline+newline+text[tail:]
    for name in hide:
        require(re.fullmatch(r'[A-Za-z0-9_]+', name), 'Invalid graybox child name')
        pattern = r'(?ms)^\[node name="'+re.escape(name)+r'" [^\r\n]*parent="Visuals/Model"[^\r\n]*\].*?(?=^\[|\Z)'
        matches = list(re.finditer(pattern, text))
        require(len(matches) == 1, 'Expected exactly one graybox child: '+name)
        block = matches[0][0]
        changed = re.sub(r'(?m)^visible = [^\r\n]+', 'visible = false', block) if re.search(r'(?m)^visible = ', block) else block.replace(newline, newline+'visible = false'+newline, 1)
        text = text[:matches[0].start()]+changed+text[matches[0].end():]
    return text.encode('utf-8')


def publish(a):
    repo = Path(a.repo).resolve(); prepared = Path(a.prepared).resolve()
    scene = (repo/a.scene).resolve()
    require(scene.is_relative_to(repo) and scene.suffix == '.tscn', 'Scene must be inside repository')
    before = Path(a.expected_scene).read_bytes()
    require(scene.read_bytes() == before, 'Wrapper changed since snapshot; preserve new edits')
    params = json.loads((prepared/'model_parameters.json').read_text(encoding='utf-8'))
    asset = params['asset']; require(re.fullmatch(r'[a-z][a-z0-9_\-]*', asset), 'Invalid asset name')
    final = (prepared/'final.glb').read_bytes()
    require(sha(final) == params['final_sha256'], 'Prepared model changed; prepare and review again')
    changed = wrapper_bytes(before, asset, a.hide)
    runtime = repo/'assets/models'/asset; source = repo/'art_source'/asset
    require(not runtime.exists() and not (source/'editable').exists() and not (source/'model_parameters.json').exists(),
            'Delivery already exists; use a new asset name or edit explicitly')
    # Rebuild the editable source from the reviewed GLB, rather than trust mutable intermediate exports.
    doc, binary, _ = decode(prepared/'final.glb'); supported(doc, binary)
    require([sha(im) for im in image_bytes(doc, binary)] == params['texture_sha256'], 'Texture hash mismatch')
    source.mkdir(parents=True, exist_ok=True)
    editable(doc, binary, source/'editable', asset)
    save_json(source/'model_parameters.json', params)
    runtime.mkdir(parents=True)
    (runtime/(asset+'.glb')).write_bytes(final)
    require(scene.read_bytes() == before, 'Wrapper changed during publish; assets saved, scene untouched')
    scene.write_bytes(changed)
    return {'asset': asset, 'scene': str(scene), 'graybox_retained_hidden': a.hide}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest='command', required=True)
    p = subs.add_parser('prepare', help='Fit, optionally reduce, export editable copy; no game scene writes')
    for flag in ['source', 'output', 'asset']: p.add_argument('--'+flag, required=True)
    p.add_argument('--size', type=float, nargs=3, required=True, metavar=('X', 'Y', 'Z'))
    p.add_argument('--origin', choices=['center', 'bottom-center'], required=True)
    p.add_argument('--rotation-y', type=float, default=0, help='Degrees; choose after inspecting source facing')
    p.add_argument('--front', choices=['+X', '-X', '+Z', '-Z'], required=True, help='Intended facing; must verify visually')
    p.add_argument('--gltfpack'); p.add_argument('--ratio', type=float); p.add_argument('--error', type=float, default=0.025)
    p = subs.add_parser('publish', help='Invoke only after art review; retain Visuals/Model and hidden graybox')
    p.add_argument('--prepared', required=True); p.add_argument('--repo', default='.')
    p.add_argument('--scene', required=True); p.add_argument('--expected-scene', required=True)
    p.add_argument('--hide', nargs='+', required=True)
    a = parser.parse_args()
    try:
        print(json.dumps(prepare(a) if a.command == 'prepare' else publish(a)))
    except (ValueError, KeyError, OSError, struct.error) as exc:
        parser.exit(1, str(exc)+'\n')


if __name__ == '__main__':
    main()
