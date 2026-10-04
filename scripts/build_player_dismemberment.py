"""Author segmented clothing and paired wound caps from the accepted GLB.

Runs in Blender; never overwrites the accepted v020/v021 assets. The same body can
be sent to Blender MCP (imports, geometry and export only; no external .blend load).
"""
import bpy
import bmesh
import math
from mathutils import Vector, Matrix, Quaternion

ROOT = 'C:/Users/evan4/Projects/ApocalypseRV'
scene = bpy.context.scene
rig = next(o for o in scene.objects if o.type == 'ARMATURE' and o.name.startswith('PLAYER_Rig'))
rig.animation_data_clear()
for p in rig.pose.bones:
    p.matrix_basis = Matrix.Identity(4)
    p.rotation_mode = 'QUATERNION'
    for c in p.constraints: c.influence = 0
bpy.context.view_layer.update()
rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
roots = {'head': 'head', 'left_arm': 'upper_arm_L', 'right_arm': 'upper_arm_R', 'left_leg': 'thigh_L', 'right_leg': 'thigh_R'}
HEAD_CUT_Z = 1.36 # Neck cylinder below the hood; do not cut through the shoulders.
chains = {part: {bone, *[c.name for c in rig.data.bones[bone].children_recursive]} for part, bone in roots.items()}
originals = [o for o in scene.objects if o.type == 'MESH' and o.name.startswith('PLAYER_')]
pieces = []
seams = {part: [] for part in roots}

def point_key(v): return tuple(round(float(x), 5) for x in v)

for obj in originals:
    # Split intersecting triangles at a real neck plane. Classifying whole
    # triangles by weights produced a concave zigzag with overlapping cap fans.
    if obj.name == 'PLAYER_Mesh':
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces), dist=.000001, plane_co=(0,0,HEAD_CUT_Z), plane_no=(0,0,1), clear_inner=False, clear_outer=False)
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data)
        bm.free()
    mesh = obj.data
    groups = {g.index: g.name for g in obj.vertex_groups}
    weights = [{groups[g.group]: g.weight for g in v.groups if g.weight > 0.00001} for v in mesh.vertices]
    labels = []
    head_accessory = any(s in obj.name for s in ['Hood', 'Mask'])
    for face in mesh.polygons:
        score = {part: sum(sum(w for n, w in weights[i].items() if n in bones) for i in face.vertices) / len(face.vertices) for part, bones in chains.items()}
        best = max((p for p in score if p != 'head'), key=score.get)
        above_neck = min(mesh.vertices[i].co.z for i in face.vertices) >= HEAD_CUT_Z-.000001
        labels.append('head' if head_accessory or above_neck else best if score[best] >= .5 else 'torso')
    adjacency = {}
    for face in mesh.polygons:
        verts = list(face.vertices)
        for a, b in zip(verts, verts[1:] + verts[:1]):
            key = tuple(sorted((point_key(mesh.vertices[a].co), point_key(mesh.vertices[b].co))))
            if key[0] == key[1]: continue
            adjacency.setdefault(key, []).append((labels[face.index], a, b))
    for contacts in adjacency.values():
        regions = {entry[0] for entry in contacts}
        if 'torso' not in regions: continue
        for part in regions - {'torso'}:
            _, a, b = next(c for c in contacts if c[0] == part)
            seams[part].append(((mesh.vertices[a].co.copy(), weights[a]), (mesh.vertices[b].co.copy(), weights[b])))
    for part in sorted(set(labels)):
        copy = obj.copy()
        copy.data = obj.data.copy()
        copy.name = 'Part_' + part + '__' + obj.name
        scene.collection.objects.link(copy)
        bm = bmesh.new()
        bm.from_mesh(copy.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if labels[f.index] != part], context='FACES')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
        bm.to_mesh(copy.data)
        bm.free()
        pieces.append(copy)
    bpy.data.objects.remove(obj, do_unlink=True)

def material(name, color, roughness):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    node = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    node.inputs['Base Color'].default_value = (*color, 1)
    node.inputs['Roughness'].default_value = roughness
    return m

flesh = material('Severed_Muscle', (.28, .014, .027), .32)
dark = material('Torn_Cloth_Blood', (.055, .008, .012), .64)
bone = material('Exposed_Bone', (.62, .47, .32), .57)
marrow = material('Bone_Marrow', (.19, .024, .021), .4)

def add_cap(part, loop, end):
    # Identical weighted rim on both sides: there is no open hollow cut surface.
    center = sum((p for p, _ in loop), Vector()) / len(loop)
    normal = Vector()
    for i, (p, _) in enumerate(loop): normal += (p-center).cross(loop[(i+1)%len(loop)][0]-center)
    if normal.length < .000001: return
    normal.normalize()
    expected = (rig.data.bones[roots[part]].tail_local - rig.data.bones[roots[part]].head_local).normalized()
    if normal.dot(expected) < 0: loop = list(reversed(loop)); normal = -normal
    if end == 'Cap': loop = list(reversed(loop)); normal = -normal
    verts, influence, faces, slots = [], [], [], []
    count = len(loop)
    mean = {}
    for _, ws in loop:
        for n, w in ws.items(): mean[n] = mean.get(n, 0) + w / count
    # Rim, recessed torn cloth, irregular muscle, bone cortex, marrow.
    for ring, radius in enumerate([1, .88, .34, .21, .10]):
        for i, (p, ws) in enumerate(loop):
            ripple = 1 if ring == 0 else 1 + .065 * math.sin(i * 2.31 + ring)
            depth = (0 if ring == 0 else -.001 + .0005*math.sin(i*1.7)) if part == 'head' else (.002 if ring == 0 else -.003 + .004 * math.sin(i * 1.7))
            verts.append(center + (p-center) * radius * ripple + normal * depth)
            influence.append(ws if ring == 0 else {n: ws.get(n,0)*radius + mean.get(n,0)*(1-radius) for n in set(ws)|set(mean)})
        if ring:
            for i in range(count):
                j = (i+1)%count
                faces.append(((ring-1)*count+i, (ring-1)*count+j, ring*count+j, ring*count+i))
                slots.append([1,0,2,3][ring-1])
    verts.append(center-normal*.003); influence.append(mean)
    for i in range(count): faces.append((4*count+i,4*count+(i+1)%count,len(verts)-1)); slots.append(3)
    data = bpy.data.meshes.new(end+'_'+part)
    data.from_pydata(verts, [], faces)
    data.update()
    cap = bpy.data.objects.new(end+'_'+part, data)
    scene.collection.objects.link(cap)
    cap.parent = rig
    modifier = cap.modifiers.new('Skin','ARMATURE'); modifier.object = rig
    for m in [flesh,dark,bone,marrow]: data.materials.append(m)
    for f, slot in zip(data.polygons,slots): f.material_index = slot; f.use_smooth = True
    for n in rest:
        group = cap.vertex_groups.new(name=n)
        for i, ws in enumerate(influence):
            if ws.get(n,0) > .00001: group.add([i], ws[n], 'REPLACE')
    pieces.append(cap)

for part, edges in seams.items():
    by_key = {}; neighbors = {}
    for a,b in edges:
        ka,kb = point_key(a[0]),point_key(b[0])
        by_key[ka] = a; by_key[kb] = b
        neighbors.setdefault(ka,set()).add(kb); neighbors.setdefault(kb,set()).add(ka)
    visited = set(); loops = []
    for start in neighbors:
        if start in visited: continue
        current, previous, loop = start, None, []
        while current not in visited:
            visited.add(current); loop.append(by_key[current])
            choices = neighbors[current] - {previous}
            if not choices: break
            nxt = next((k for k in choices if k not in visited), start)
            previous,current = current,nxt
        if len(loop) >= 3: loops.append(loop)
    # Clothing overlays may add smaller contours. Each receives a closed cap.
    for loop in loops:
        add_cap(part,loop,'Wound'); add_cap(part,loop,'Cap')
    print('SEAM', part, 'loops', [len(loop) for loop in loops], flush=True)

# This export is a mesh donor: runtime keeps accepted v020 skeleton/rest/skin.
for obj in scene.objects: obj.select_set(False)
for obj in [rig]+pieces: obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=ROOT+'/assets/models/player_dismemberment/player_dismemberment.glb', use_selection=True, use_active_scene=True, export_format='GLB', export_animations=False, export_skins=True, export_yup=True)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/art_source/player_dismemberment/player_dismemberment.blend')
print('PLAYER_DISMEMBERMENT_MESH_COMPLETE', flush=True)
