"""Original low-poly WAYFARER ladders, metres / Y up / approach +Z.

Deterministic stdlib authoring: exports chamfered geometry with UVs and an
embedded 128px paint/grip texture. Physics and interactions stay in Godot.
"""
import json
import math
import random
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models/rv_ladders'
PALETTE = [
    ('worn_forest_paint', [.19, .29, .25, 1], .25, .88),
    ('aged_ivory', [.68, .65, .52, 1], .15, .9),
    ('galvanized_tread', [.38, .42, .39, 1], .65, .8),
    ('rubber_grip', [.065, .073, .065, 1], 0, .98),
    ('service_orange', [.78, .32, .095, 1], .1, .88),
]
vertices = []
normals = []
uvs = []


def texture():
    rng = random.Random(417)
    pixels = [[max(0, min(255, 227 + rng.randrange(-19, 15))) for _ in range(128)] for _ in range(128)]
    # Irregular chips and directional scratches remain readable at low resolution.
    for _ in range(185):
        x, y = rng.randrange(128), rng.randrange(128)
        for dy in range(rng.randrange(1, 4)):
            for dx in range(rng.randrange(1, 7)):
                pixels[(y+dy) % 128][(x+dx) % 128] = rng.randrange(95, 170)
    raw = b''.join(b'\0' + bytes(v for p in row for v in (p, p, p, 255)) for row in pixels)
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag+data))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 128, 128, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')


def face(points, mat):
    a = [points[1][i]-points[0][i] for i in range(3)]
    b = [points[2][i]-points[0][i] for i in range(3)]
    n = (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
    length = math.sqrt(sum(v*v for v in n))
    n = tuple(v/length for v in n)
    axis = max(range(3), key=lambda i: abs(n[i]))
    axes = [i for i in range(3) if i != axis]
    for i in range(1, len(points)-1):
        for p in (points[0], points[i], points[i+1]):
            vertices[mat].append(p)
            normals[mat].append(n)
            uvs[mat].append((p[axes[0]]*3, p[axes[1]]*3))


def box(center, size, mat, bevel=.012):
    x, y, z = [s/2 for s in size]
    b = min(bevel, x*.4, z*.4)
    ring = [(-x+b,-z),(x-b,-z),(x,-z+b),(x,z-b),(x-b,z),(-x+b,z),(-x,z-b),(-x,-z+b)]
    low = [(center[0]+a,center[1]-y,center[2]+c) for a,c in ring]
    high = [(center[0]+a,center[1]+y,center[2]+c) for a,c in ring]
    face(low, mat)
    face(high[::-1], mat)
    for i in range(8):
        j = (i+1)%8
        face([low[i], high[i], high[j], low[j]], mat)


def bolt(x, y, z):
    ring = [(x+math.cos(i*math.tau/6)*.018, y+math.sin(i*math.tau/6)*.018, z) for i in range(6)]
    face(ring, 2)


def build(height, short):
    global vertices, normals, uvs
    vertices, normals, uvs = [[[] for _ in PALETTE] for _ in range(3)]
    # The door ladder ends below the sill so the outward leaf clears it.
    rail_top = height if short else height+.37
    for x in (-.43,.43):
        box((x,rail_top/2,0),(.085,rail_top,.14),0)
        box((x,.035,0),(.095,.07,.15),3)
        box((x,rail_top-.17,.004),(.09,.26,.15),3)
        box((x,.26,.002),(.09,.115,.145),4)
        box((x,height-.15,.002),(.09,.1,.145),1)
        # Flat rear standoffs share a -Z wall mounting plane, not floor feet
        # or a projecting hook. They have no placement/snap behavior.
        for mount_y in ([.65, height-.16] if short else [.45,height-.45]):
            box((x,mount_y,-.095),(.07,.055,.11),2)
            box((x,mount_y,-.145),(.14,.14,.01),0,.002)
            bolt(x,mount_y+.042,-.138)
            bolt(x,mount_y-.042,-.138)
        box((x,rail_top,.0),(.09,.025,.145),1)
    count = 5 if short else 9
    for i in range(count):
        y = .22+i*(height-.32)/(count-1)
        box((0,y,.015),(.8,.055,.18),2)
        box((0,y+.031,.02),(.7,.01,.135),3)
        for k in range(3):
            box((0,y+.04,-.026+k*.045),(.69,.008,.012),2,.001)
        for x in (-.43,.43):
            bolt(x,y,.073)
    # Orange identification tab fixed to the lower crossbar.
    box((0,.22,.113),(.23,.055,.008),4,.001)
    write_glb('side_door_ladder' if short else 'roof_ladder')


def write_glb(name):
    binary, views, accessors, primitives = bytearray(), [], [], []
    def accessor(values, bounds=False):
        offset = len(binary)
        width = len(values[0])
        for value in values:
            binary.extend(struct.pack('<'+'f'*width,*value))
        views.append({'buffer':0,'byteOffset':offset,'byteLength':len(binary)-offset,'target':34962})
        data = {'bufferView':len(views)-1,'componentType':5126,'count':len(values),'type':'VEC'+str(width)}
        if bounds:
            data.update(min=[min(p[i] for p in values) for i in range(width)],max=[max(p[i] for p in values) for i in range(width)])
        accessors.append(data)
        return len(accessors)-1
    for i, verts in enumerate(vertices):
        primitives.append({'attributes':{'POSITION':accessor(verts,True),'NORMAL':accessor(normals[i]),'TEXCOORD_0':accessor(uvs[i])},'material':i})
    png = texture()
    views.append({'buffer':0,'byteOffset':len(binary),'byteLength':len(png)})
    binary.extend(png)
    data = {'asset':{'version':'2.0','generator':'ApocalypseRV original WAYFARER ladder authoring'},
        'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':name,'mesh':0}],
        'meshes':[{'name':name,'primitives':primitives}],
        'materials':[{'name':n,'pbrMetallicRoughness':{'baseColorFactor':c,'metallicFactor':m,'roughnessFactor':r,'baseColorTexture':{'index':0}}} for n,c,m,r in PALETTE],
        'images':[{'bufferView':len(views)-1,'mimeType':'image/png'}],
        'samplers':[{'magFilter':9728,'minFilter':9984,'wrapS':10497,'wrapT':10497}],
        'textures':[{'source':0,'sampler':0}],
        'buffers':[{'byteLength':len(binary)}],'bufferViews':views,'accessors':accessors}
    encoded=json.dumps(data,separators=(',',':')).encode()
    encoded+=b' '*(-len(encoded)%4)
    binary+=b'\0'*(-len(binary)%4)
    result=struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(binary),b'BIN\0')+binary
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/(name+'.glb')).write_bytes(result)
    (OUT/'ladder_wear.png').write_bytes(png)
    print(name, sum(len(v) for v in vertices)//3, 'triangles')


if __name__ == '__main__':
    build(1.3, True)
    build(2.21, False)
