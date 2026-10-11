"""Rebuild the three static RV service visuals. Python + numpy; no gameplay edits."""
import argparse
import copy
import hashlib
import json
import math
import struct
from pathlib import Path

import numpy as np

PALETTE = {
    'OlivePaint': ([0.14, 0.18, 0.12, 1], 0.38, 0.86, True),
    'DarkPolymer': ([0.018, 0.024, 0.020, 1], 0.0, 0.86, False),
    'Steel': ([0.26, 0.28, 0.24, 1], 0.78, 0.62, True),
    'Rubber': ([0.004, 0.006, 0.005, 1], 0.0, 0.94, False),
    'SafetyOchre': ([0.45, 0.30, 0.08, 1], 0.25, 0.85, True),
    'PositiveLead': ([0.16, 0.02, 0.008, 1], 0.0, 0.82, False),
    'Terminal': ([0.42, 0.34, 0.20, 1], 0.85, 0.55, False),
}


def unit(v):
    v = np.asarray(v, dtype=float)
    length = np.linalg.norm(v)
    assert length > 1e-12
    return v/length


class Model:
    def __init__(self, name):
        self.name = name
        self.surfaces = {}

    def polygon(self, points, normal, material, uv=None):
        points = np.asarray(points, dtype=float); normal = unit(normal)
        if np.dot(np.cross(points[1]-points[0], points[2]-points[0]), normal) < 0:
            points = points[::-1]
            if uv is not None: uv = np.asarray(uv)[::-1]
        if uv is None:
            axes = [i for i in range(3) if i != np.argmax(np.abs(normal))]
            uv = points[:, axes]*3.2 + [0.37, 0.18]
        surface = self.surfaces.setdefault(material, {'v': [], 'n': [], 'uv': [], 'i': []})
        start = len(surface['v']); count = len(points)
        surface['v'].extend(points.tolist()); surface['n'].extend([normal.tolist()]*count)
        surface['uv'].extend(np.asarray(uv).tolist())
        for i in range(1, count-1): surface['i'].extend([start, start+i, start+i+1])

    def bevel(self, size, center, bevel, material, rotation=None):
        """Six faces, twelve chamfer strips, eight corners; no hidden inner boxes."""
        h = np.asarray(size)/2; center = np.asarray(center); b = min(bevel, min(h)*0.8)
        rot = np.eye(3) if rotation is None else np.asarray(rotation)
        def face(points, normal): self.polygon(np.asarray(points)@rot.T+center, rot@normal, material)
        for axis in range(3):
            other = [i for i in range(3) if i != axis]
            for sign in [-1, 1]:
                pts = []
                for u, v in [(-1, -1), (1, -1), (1, 1), (-1, 1)]:
                    p = np.zeros(3); p[axis] = sign*h[axis]
                    p[other[0]] = u*(h[other[0]]-b); p[other[1]] = v*(h[other[1]]-b); pts.append(p)
                normal = np.zeros(3); normal[axis] = sign; face(pts, normal)
        for length_axis in range(3):
            a, c = [i for i in range(3) if i != length_axis]
            for sa in [-1, 1]:
                for sc in [-1, 1]:
                    pts = []
                    for sl, side in [(-1, 0), (1, 0), (1, 1), (-1, 1)]:
                        p = np.zeros(3); p[length_axis] = sl*(h[length_axis]-b)
                        p[a] = sa*(h[a]-(b if side == 0 else 0)); p[c] = sc*(h[c]-(0 if side == 0 else b)); pts.append(p)
                    normal = np.zeros(3); normal[a] = sa; normal[c] = sc; face(pts, normal)
        for sx in [-1, 1]:
            for sy in [-1, 1]:
                for sz in [-1, 1]:
                    signs = np.array([sx, sy, sz]); pts = []
                    for axis in range(3):
                        p = signs*(h-b); p[axis] = signs[axis]*h[axis]; pts.append(p)
                    face(pts, signs)

    def lathe(self, profile, center, material, sides=24, axis=(0, 1, 0)):
        """Closed turned shape around local Y, optionally aimed along another axis."""
        axis = unit(axis); ref = np.eye(3)[np.argmin(np.abs(axis))]
        u = unit(np.cross(axis, ref)); v = np.cross(u, axis); center = np.asarray(center)
        rings = [np.array([center+axis*y+r*(u*math.cos(a)+v*math.sin(a)) for a in np.linspace(0, 2*math.pi, sides, endpoint=False)]) for y, r in profile]
        for i in range(len(rings)-1):
            y0, r0 = profile[i]; y1, r1 = profile[i+1]
            for j in range(sides):
                k = (j+1) % sides; angle = 2*math.pi*(j+0.5)/sides
                normal = (u*math.cos(angle)+v*math.sin(angle))*(y1-y0)+axis*(r0-r1)
                self.polygon([rings[i][j], rings[i][k], rings[i+1][k], rings[i+1][j]], normal, material)
        self.polygon(rings[0], -axis, material); self.polygon(rings[-1], axis, material)

    def tube(self, points, radius, material, sides=8):
        points = np.asarray(points)
        for i in range(len(points)-1):
            a, b = points[i:i+2]; length = np.linalg.norm(b-a)
            self.lathe([(0, radius), (length, radius)], a, material, sides, b-a)

    def bolt(self, center, axis=(0, 1, 0), radius=0.008):
        self.lathe([(0, radius*1.35), (0.002, radius*1.35)], center, 'Steel', 12, axis)
        self.lathe([(0.002, radius), (0.006, radius), (0.008, radius*0.83)], center, 'Steel', 6, axis)

    def lightning(self, center, up, right, scale=1, material='SafetyOchre'):
        center = np.asarray(center); up = np.asarray(up); right = np.asarray(right)
        # Concave shape split into three convex patches.
        for points in [[(-.018, .025), (.006, .025), (-.009, -.004), (-.023, -.004)],
                       [(-.009, -.004), (.019, .007), (.010, -.011), (-.017, -.013)],
                       [(.019, .007), (.011, -.011), (-.009, -.031), (-.001, -.008)]]:
            self.polygon([center+scale*(x*right+y*up) for x, y in points], np.cross(right, up), material)

    def export(self, repo, source):
        runtime = repo/'assets/models'/self.name; runtime.mkdir(parents=True, exist_ok=True)
        doc = {'asset': {'version': '2.0', 'generator': 'ApocalypseRV rv_service_parts/build_models.py'},
               'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'name': self.name, 'mesh': 0}],
               'meshes': [{'name': self.name, 'primitives': []}], 'buffers': [], 'bufferViews': [], 'accessors': [],
               'images': [{'uri': '../../materials/industrial/worn_paint.png'}],
               'samplers': [{'magFilter': 9728, 'minFilter': 9984, 'wrapS': 10497, 'wrapT': 10497}],
               'textures': [{'source': 0, 'sampler': 0}], 'materials': []}
        binary = bytearray(); vertices = 0; triangles = 0; all_positions = []
        def append(values, kind, dtype, component):
            array = np.asarray(values, dtype=dtype); binary.extend(b'\0'*(-len(binary) % 4)); start = len(binary)
            binary.extend(array.tobytes()); view = len(doc['bufferViews'])
            doc['bufferViews'].append({'buffer': 0, 'byteOffset': start, 'byteLength': array.nbytes})
            acc = {'bufferView': view, 'componentType': component, 'count': len(values), 'type': kind}
            if kind == 'VEC3': acc.update(min=array.min(0).tolist(), max=array.max(0).tolist())
            index = len(doc['accessors']); doc['accessors'].append(acc); return index
        for name, s in self.surfaces.items():
            color, metal, rough, textured = PALETTE[name]
            pbr = {'baseColorFactor': color, 'metallicFactor': metal, 'roughnessFactor': rough}
            if textured: pbr['baseColorTexture'] = {'index': 0}
            mat = len(doc['materials']); doc['materials'].append({'name': name, 'pbrMetallicRoughness': pbr})
            pos = np.asarray(s['v']); normals = np.asarray(s['n']); indices = np.asarray(s['i']).reshape(-1, 3)
            assert np.isfinite(pos).all() and np.allclose(np.linalg.norm(normals, axis=1), 1)
            crosses = np.cross(pos[indices[:, 1]]-pos[indices[:, 0]], pos[indices[:, 2]]-pos[indices[:, 0]])
            assert (np.linalg.norm(crosses, axis=1) > 1e-12).all()
            assert (np.sum(crosses*normals[indices[:, 0]], axis=1) > 0).all(), 'Wrong winding'
            attrs = {'POSITION': append(s['v'], 'VEC3', '<f4', 5126), 'NORMAL': append(s['n'], 'VEC3', '<f4', 5126),
                     'TEXCOORD_0': append(s['uv'], 'VEC2', '<f4', 5126)}
            doc['meshes'][0]['primitives'].append({'attributes': attrs, 'indices': append(s['i'], 'SCALAR', '<u4', 5125), 'material': mat, 'mode': 4})
            vertices += len(pos); triangles += len(indices); all_positions.extend(pos)
        doc['buffers'] = [{'byteLength': len(binary)}]
        js = json.dumps(doc, separators=(',', ':')).encode(); js += b' '*(-len(js) % 4)
        buf = bytes(binary)+b'\0'*(-len(binary) % 4)
        glb = (struct.pack('<4sII', b'glTF', 2, 28+len(js)+len(buf))+struct.pack('<II', len(js), 0x4e4f534a)+js
               +struct.pack('<II', len(buf), 0x004e4942)+buf)
        (runtime/(self.name+'.glb')).write_bytes(glb)
        editable = copy.deepcopy(doc); editable['buffers'][0]['uri'] = self.name+'.bin'
        editable['images'][0]['uri'] = '../../assets/materials/industrial/worn_paint.png'
        (source/(self.name+'.gltf')).write_text(json.dumps(editable, indent=2)+'\n', encoding='utf-8')
        (source/(self.name+'.bin')).write_bytes(binary)
        positions = np.asarray(all_positions)
        return {'triangles': triangles, 'vertices': vertices, 'surfaces': len(self.surfaces),
                'bounds_min_m': positions.min(0).tolist(), 'bounds_max_m': positions.max(0).tolist(),
                'glb_sha256': hashlib.sha256(glb).hexdigest(), 'origin': 'existing wrapper center', 'up': '+Y'}


def battery():
    m = Model('rv_service_battery')
    m.bevel((.438, .212, .286), (0, -.036, 0), .006, 'OlivePaint')
    m.bevel((.45, .018, .30), (0, -.141, 0), .004, 'DarkPolymer')
    m.bevel((.446, .012, .296), (0, .072, 0), .003, 'Rubber')
    m.bevel((.446, .042, .296), (0, .097, 0), .005, 'DarkPolymer')
    # Side stiffening ribs and the front inset identification panel.
    for x in [-.186, -.155, -.124, .124, .155, .186]:
        for z in [-.144, .144]: m.bevel((.012, .15, .009), (x, -.035, z), .002, 'DarkPolymer')
    m.bevel((.188, .085, .004), (0, -.026, .145), .002, 'Steel')
    m.bevel((.172, .071, .003), (0, -.026, .148), .001, 'DarkPolymer')
    m.lightning((0, -.026, .150), (0, 1, 0), (1, 0, 0), .65)
    # Actual handle hole; bar tops are lower than the terminals.
    for x in [-.062, .062]: m.bevel((.013, .025, .016), (x, .128, .029), .003, 'DarkPolymer')
    m.bevel((.137, .011, .016), (0, .139, .029), .003, 'DarkPolymer')
    for x in [-.15, .15]:
        m.lathe([(0, .027), (.004, .027), (.008, .023)], (x, .118, -.088), 'PositiveLead' if x > 0 else 'Rubber', 16)
        m.lathe([(0, .016), (.015, .014), (.024, .012)], (x, .126, -.088), 'Terminal', 16)
        m.bevel((.025, .0015, .005), (x, .1189, -.034), .0005, 'SafetyOchre')
        if x > 0: m.bevel((.005, .0015, .025), (x, .1189, -.034), .0005, 'SafetyOchre')
    for x in [-.095, -.057, -.019, .019, .057, .095]:
        m.lathe([(0, .010), (.004, .008)], (x, .118, -.085), 'Rubber', 8)
    return m


def socket():
    m = Model('rv_battery_bay')
    m.bevel((.036, .49, .87), (-.142, 0, 0), .006, 'OlivePaint')
    m.bevel((.014, .38, .71), (-.117, 0, 0), .003, 'Rubber')
    for y in [-.2525, .2525]: m.bevel((.32, .055, .95), (0, y, 0), .006, 'OlivePaint')
    for z in [-.4475, .4475]: m.bevel((.32, .45, .055), (0, 0, z), .006, 'OlivePaint')
    # Recessed channel and front rubber edging leave a real open compartment.
    for y in [-.216, .216]: m.bevel((.20, .016, .80), (-.025, y, 0), .003, 'Steel')
    for z in [-.405, .405]: m.bevel((.012, .40, .015), (.143, 0, z), .003, 'Rubber')
    for z in [-.315, .315]:
        m.bevel((.17, .026, .07), (.01, -.185, z), .003, 'DarkPolymer')
        m.bevel((.018, .095, .055), (.142, -.155, z), .003, 'Steel')
        m.bevel((.019, .055, .039), (.143, -.152, z), .003, 'SafetyOchre')
    # One fixed pair of service leads, not an extra visible battery when empty.
    for sign, mat in [(-1, 'PositiveLead'), (1, 'Rubber')]:
        points = [(-.09, .15, sign*.32), (-.083, .19, sign*.28), (-.052, .196, sign*.24),
                  (-.018, .177, sign*.20), (-.024, .15, sign*.1875)]
        m.tube(points, .006, mat)
    for y in [-.25, .25]:
        for z in [-.426, .426]: m.bolt((.152, y, z), (1, 0, 0), .009)
    for y in [-.1, .1]:
        for z in [-.45, .45]: m.bolt((.152, y, z), (1, 0, 0), .007)
    m.bevel((.007, .040, .252), (.1565, -.25, 0), .002, 'DarkPolymer')
    m.lightning((.161, .2525, -.365), (0, 1, 0), (0, 0, -1), .65)
    return m


def fuel_port():
    m = Model('rv_fuel_inlet')
    m.bevel((.60, .023, .40), (0, -.1385, 0), .005, 'Steel')
    m.bevel((.565, .21, .365), (0, -.022, 0), .018, 'OlivePaint')
    m.bevel((.574, .013, .373), (0, .0805, 0), .004, 'Rubber')
    m.bevel((.578, .025, .378), (0, .097, 0), .007, 'OlivePaint')
    m.lathe([(0, .139), (.009, .139), (.017, .13)], (0, .1095, 0), 'Steel', 32)
    m.lathe([(0, .126), (.006, .126)], (0, .1265, 0), 'Rubber', 32)
    m.lathe([(0, .117), (.008, .126), (.039, .126), (.048, .115)], (0, .1325, 0), 'SafetyOchre', 32)
    m.bevel((.20, .045, .035), (0, .203, 0), .005, 'Steel')
    m.bevel((.142, .012, .039), (0, .2295, 0), .003, 'Rubber')
    # Cap perimeter grooves, plate fasteners and a short contained safety tether.
    for angle in np.linspace(0, 2*math.pi, 12, endpoint=False):
        c, s = math.cos(angle), math.sin(angle)
        rot = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
        m.bevel((.009, .024, .007), (.124*c, .155, -.124*s), .0015, 'DarkPolymer', rot)
    for x in [-.245, .245]:
        for z in [-.148, .148]: m.bolt((x, .1095, z), radius=.012)
    m.tube([(.102, .166, .048), (.15, .144, .076), (.185, .115, .065), (.20, .114, .018)], .004, 'Rubber')
    m.lightning((-.222, .110, 0), (0, 0, -1), (1, 0, 0), .9, 'SafetyOchre')
    return m


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[2])
    a = parser.parse_args(); source = a.repo/'art_source/rv_service_parts'; source.mkdir(parents=True, exist_ok=True)
    metadata = {model.name: model.export(a.repo, source) for model in [battery(), socket(), fuel_port()]}
    texture = a.repo/'assets/materials/industrial/worn_paint.png'
    metadata['shared_texture'] = {'path': 'assets/materials/industrial/worn_paint.png', 'sha256': hashlib.sha256(texture.read_bytes()).hexdigest()}
    (source/'model_parameters.json').write_text(json.dumps(metadata, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(metadata))


if __name__ == '__main__': main()
