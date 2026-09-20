"""Original, deterministic GLB authoring source; Python standard library only.

Run from any directory. No Godot scene/physics is generated here. Reimport the
result in Godot (or Blender) and keep gameplay in the fuel_pump.tscn wrapper.
"""
import json
import math
import struct
from pathlib import Path

OUTPUT = Path(__file__).resolve().parents[1] / "assets/models/gas_station/fuel_pump.glb"
PALETTE = [
    ("aged_ivory", [0.68, 0.65, 0.53, 1], 0.0, 0.8),
    ("oxide_red", [0.39, 0.12, 0.075, 1], 0.0, 0.82),
    ("rubber", [0.028, 0.035, 0.032, 1], 0.0, 0.95),
    ("cast_metal", [0.22, 0.25, 0.23, 1], 0.65, 0.58),
    ("display", [0.025, 0.055, 0.048, 1], 0.15, 0.3),
    ("brass", [0.65, 0.49, 0.23, 1], 0.5, 0.5),
]
VERTICES = [[] for _ in PALETTE]
NORMALS = [[] for _ in PALETTE]


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def unit(a):
    length = math.sqrt(sum(x*x for x in a))
    return tuple(x / length for x in a)


def face(points, material):
    normal = unit(cross(sub(points[1], points[0]), sub(points[2], points[0])))
    for i in range(1, len(points)-1):
        VERTICES[material].extend((points[0], points[i], points[i+1]))
        NORMALS[material].extend((normal, normal, normal))


def box(center, size, material, bevel=0.025):
    """Chamfered vertical edges, flat normals and outward CCW glTF faces."""
    x, y, z = (s / 2 for s in size)
    b = min(bevel, x * .4, z * .4)
    ring = [(-x+b, -z), (x-b, -z), (x, -z+b), (x, z-b),
            (x-b, z), (-x+b, z), (-x, z-b), (-x, -z+b)]
    low = [(center[0]+px, center[1]-y, center[2]+pz) for px, pz in ring]
    high = [(center[0]+px, center[1]+y, center[2]+pz) for px, pz in ring]
    face(low, material)
    face(list(reversed(high)), material)
    for i in range(8):
        j = (i + 1) % 8
        face([low[i], high[i], high[j], low[j]], material)


def tube(a, b, radius, material, sides=8):
    axis = unit(sub(b, a))
    tangent = unit(cross(axis, (0, 0, 1) if abs(axis[2]) < .9 else (0, 1, 0)))
    bitangent = cross(axis, tangent)
    rings = []
    for center in (a, b):
        rings.append([tuple(center[k] + radius * (math.cos(i*math.tau/sides)*tangent[k]
                      + math.sin(i*math.tau/sides)*bitangent[k]) for k in range(3))
                      for i in range(sides)])
    face(list(reversed(rings[0])), material)
    face(rings[1], material)
    for i in range(sides):
        j = (i+1) % sides
        face([rings[0][i], rings[0][j], rings[1][j], rings[1][i]], material)


def build_geometry():
    # Existing gameplay envelope: foot 1.35 x 1.10, height 2.255 m.
    box((0, .11, 0), (1.35, .22, 1.10), 3, .10)
    box((0, .77, 0), (.94, 1.10, .72), 1, .065)
    box((0, 1.78, 0), (1.25, .95, .86), 0, .075)
    box((0, 1.34, 0), (1.26, .065, .87), 3)
    box((0, 2.22, 0), (1.25, .07, .86), 1, .075)
    for sign in (-1, 1):
        box((0, 1.96, sign*.444), (.98, .4, .025), 3, .01)
        box((0, 1.96, sign*.46), (.86, .30, .015), 4, .005)
        box((0, 1.61, sign*.445), (1.0, .17, .026), 1, .005)
        box((0, .78, sign*.369), (.76, .84, .018), 1, .015)
        box((.26, 1.13, sign*.384), (.11, .04, .024), 3, .005)
        # Vent strips on lower access panel and service fasteners.
        for i in range(5):
            box((0, .44+i*.047, sign*.382), (.49, .019, .015), 2, .003)
        for x in (-.33, .33):
            for y in (.41, 1.12):
                tube((x, y, sign*.38), (x, y, sign*.392), .014, 3)
        for x in (-.27, 0, .27):
            tube((x, 1.43, sign*.438), (x, 1.43, sign*.455), .028, 5)
    # Low-poly rubber loop; no collision detail is exported with this visual.
    hose = [(.61, 1.89, .04), (.72, 1.83, .04), (.8, 1.6, .04),
            (.8, .79, .04), (.76, .61, .04), (.63, .54, .04),
            (.53, .64, .04), (.53, .91, .04), (.58, 1.10, .04)]
    for a, b in zip(hose, hose[1:]):
        tube(a, b, .042, 2)
    tube((.58, 1.06, .04), (.66, 1.30, .04), .047, 3)
    tube((.66, 1.30, .04), (.52, 1.42, .04), .028, 3)
    box((.595, 1.16, .09), (.14, .20, .085), 2, .01)


def write_glb():
    build_geometry()
    binary = bytearray()
    views, accessors, primitives = [], [], []

    def accessor(values, bounds=False):
        offset = len(binary)
        for value in values:
            binary.extend(struct.pack('<3f', *value))
        views.append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(binary)-offset, 'target': 34962})
        entry = {'bufferView': len(views)-1, 'componentType': 5126, 'count': len(values), 'type': 'VEC3'}
        if bounds:
            entry['min'] = [min(v[i] for v in values) for i in range(3)]
            entry['max'] = [max(v[i] for v in values) for i in range(3)]
        accessors.append(entry)
        return len(accessors)-1

    for i, vertices in enumerate(VERTICES):
        primitives.append({'attributes': {'POSITION': accessor(vertices, True), 'NORMAL': accessor(NORMALS[i])}, 'material': i})
    data = {
        'asset': {'version': '2.0', 'generator': 'ApocalypseRV original fuel pump authoring script'},
        'scene': 0, 'scenes': [{'nodes': [0]}],
        'nodes': [{'name': 'FuelPumpModel', 'mesh': 0}],
        'meshes': [{'name': 'FuelPump', 'primitives': primitives}],
        'materials': [{'name': name, 'pbrMetallicRoughness': {'baseColorFactor': color,
                       'metallicFactor': metal, 'roughnessFactor': rough}} for name, color, metal, rough in PALETTE],
        'buffers': [{'byteLength': len(binary)}], 'bufferViews': views, 'accessors': accessors,
    }
    encoded = json.dumps(data, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    binary += b'\0' * (-len(binary) % 4)
    result = struct.pack('<4sII', b'glTF', 2, 12+8+len(encoded)+8+len(binary))
    result += struct.pack('<I4s', len(encoded), b'JSON') + encoded
    result += struct.pack('<I4s', len(binary), b'BIN\0') + binary
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(result)
    print(f'{OUTPUT.name}: {sum(len(v) for v in VERTICES)//3} triangles, {len(result)} bytes')


if __name__ == '__main__':
    write_glb()
