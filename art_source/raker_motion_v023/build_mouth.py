"""Raker v023 mouth rebuild.

Run on the v022 source (see README). Replaces the v018 oral cavity and its 18
cone teeth: continues the lip slit back across the cheeks, peels the lips off
an interlocking row of needle teeth, rebuilds the gums, lining, throat and
tongue, and re-solves the jaw weights so the cheeks stretch smoothly.
"""
import bisect
import heapq
import math
import random
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree

MESH = 'Motion022_Mesh'
RIG = 'Motion022_Rig'
PLANE_Z = 2.013          # v018 lip plane; the runtime mouth anchor stays on it
CORNER_Y = -0.090        # new mouth corners, measured back from the old -0.158
BACK_Y = -0.082          # throat line the lining converges on
BACK_X = 0.40            # throat width as a fraction of the lip footprint
COLUMNS = 80             # lining columns from the left to the right corner
R_UP = 0.0050            # how far the upper lip peels off the teeth
R_LOW = 0.0078
BAND = 0.020             # skin within this height of the lips follows the peel
# Lip rows: (mm inward, share of the peel, extra mm away from the plane).
UPPER_LIP = [(1.5, 1.0, 0.6), (3.0, 1.0, -0.8), (5.5, 1.0, -0.6), (8.0, 0.7, 3.5), (11.5, 0.4, 8.5)]
LOWER_LIP = [(1.5, 1.0, 0.6), (3.5, 1.0, -0.8), (6.5, 1.0, -0.6), (9.0, 0.7, 3.0), (12.0, 0.4, 6.5)]
# Deep rows: (fraction of the way to the throat line, mm away from the plane).
UPPER_DEEP = [(0.30, 14.0), (0.50, 18.0), (0.75, 18.0), (1.0, 14.0)]
LOWER_DEEP = [(0.30, 10.0), (0.50, 12.5), (0.75, 13.0), (1.0, 12.0)]
WALL_ROWS = 4
TOOTH_STEP = 0.0066      # one upper and one lower tooth per step, interleaved
MAT_LINING = 2
MAT_TEETH = 3


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def chain_from(edges, start):
    """Order an edge loop into vertices, beginning and ending at start."""
    links = {}
    for e in edges:
        a, b = e.verts
        links.setdefault(a, []).append(b)
        links.setdefault(b, []).append(a)
    order = [start]
    previous = None
    current = start
    while True:
        nxt = [v for v in links[current] if v is not previous]
        if not nxt:
            break
        previous, current = current, nxt[0]
        order.append(current)
        if current is start:
            break
    return order


def arc_lengths(points):
    out = [0.0]
    for a, b in zip(points, points[1:]):
        out.append(out[-1] + (b - a).length)
    return out


def build(report):
    mesh = bpy.data.objects[MESH]
    me = mesh.data
    jaw_group = mesh.vertex_groups['jaw'].index
    head_group = mesh.vertex_groups['head'].index
    bm = bmesh.new()
    bm.from_mesh(me)
    deform = bm.verts.layers.deform.verify()
    uv_layer = bm.loops.layers.uv.active

    # --- remove the old lining and teeth, leaving the lips as an open boundary
    old = [f for f in bm.faces if f.material_index in (MAT_LINING, MAT_TEETH)]
    report['removed_faces'] = len(old)
    bmesh.ops.delete(bm, geom=old, context='FACES')
    bm.verts.ensure_lookup_table()
    old_lip = [v for v in bm.verts if v.is_boundary and abs(v.co.z - PLANE_Z) < 1e-4 and v.co.y < -0.12]
    old_corner = {1: max(old_lip, key=lambda v: v.co.x), -1: min(old_lip, key=lambda v: v.co.x)}

    # --- continue the slit across the cheeks
    crossing = []
    for f in bm.faces:
        if f.material_index != 0:
            continue
        zs = [v.co.z for v in f.verts]
        c = f.calc_center_median()
        if min(zs) < PLANE_Z < max(zs) and abs(c.x) > 0.03 and -0.175 < c.y < CORNER_Y and c.z > 1.95:
            crossing.append(f)
    geom = set(crossing)
    for f in crossing:
        geom.update(f.edges)
        geom.update(f.verts)
    bmesh.ops.bisect_plane(bm, geom=list(geom), dist=1e-6, plane_co=(0, 0, PLANE_Z), plane_no=(0, 0, 1))
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    # The v018 corner sits in a shallow crease just off the bisected curve, so
    # route along the plane with a shortest path and flatten it afterwards.
    path = []
    goals = {}
    for side in (1, -1):
        band = [v for v in bm.verts if v.co.x * side > 0.03 and abs(v.co.z - PLANE_Z) < 0.003
                and -0.175 < v.co.y < CORNER_Y + 0.006 and not (v.is_boundary and v is not old_corner[side])]
        allowed = set(band)
        goal = min((v for v in band if abs(v.co.z - PLANE_Z) < 1e-5 and v is not old_corner[side]),
                   key=lambda v: abs(v.co.y - CORNER_Y))
        best = {old_corner[side]: 0.0}
        parent = {}
        queue = [(0.0, old_corner[side].index, old_corner[side])]
        while queue:
            cost, _, v = heapq.heappop(queue)
            if v is goal:
                break
            if cost > best.get(v, 1e9):
                continue
            for e in v.link_edges:
                o = e.other_vert(v)
                if o not in allowed or e.is_boundary:
                    continue
                off = abs((v.co.z + o.co.z) * 0.5 - PLANE_Z)
                step = cost + e.calc_length() * (1.0 + off / 0.0004)
                if step < best.get(o, 1e9):
                    best[o] = step
                    parent[o] = v
                    heapq.heappush(queue, (step, o.index, o))
        assert goal in parent, ('no slit path', side)
        goals[side] = goal
        walk = [goal]
        while walk[-1] is not old_corner[side]:
            walk.append(parent[walk[-1]])
        for v in walk:
            v.co.z = PLANE_Z
        for a, b in zip(walk, walk[1:]):
            path.append(bm.edges.get((a, b)))
    bmesh.ops.split_edges(bm, edges=path)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()

    # --- ordered upper and lower lip chains, both running left to right
    rim = [e for e in bm.edges if e.is_boundary]
    loop = chain_from(rim, goals[-1])
    assert loop[-1] is goals[-1] and goals[1] in loop and len(loop) == len(rim) + 1, 'lips must form one closed loop'
    cut = loop.index(goals[1])
    halves = [loop[:cut + 1], list(reversed(loop[cut:]))]

    def height(chain):
        faces = {f for v in chain[1:-1] for f in v.link_faces}
        return sum(f.calc_center_median().z for f in faces) / len(faces)

    halves.sort(key=height)
    lower, upper = halves
    for v in loop:
        v.co.z = PLANE_Z
    upper_set = set(upper)
    lower_set = set(lower)
    corner = {-1: upper[0].co.copy(), 1: upper[-1].co.copy()}
    report['lip'] = {'upper_verts': len(upper), 'lower_verts': len(lower),
                     'corner_left': [round(c, 4) for c in corner[-1]], 'corner_right': [round(c, 4) for c in corner[1]]}

    # --- footprint of the closed lips, parameterised by arc length
    points = [Vector((v.co.x, v.co.y)) for v in upper]
    lengths = arc_lengths(points)
    total = lengths[-1]
    report['lip']['arc_m'] = round(total, 4)

    def footprint(distance):
        distance = max(0.0, min(total, distance))
        i = max(0, min(len(points) - 2, bisect.bisect_right(lengths, distance) - 1))
        span = lengths[i + 1] - lengths[i]
        return points[i].lerp(points[i + 1], (distance - lengths[i]) / span if span > 0 else 0.0)

    def project(xy):
        """Arc distance of the footprint point nearest to xy, and its distance."""
        best_d, best_gap = 0.0, 1e9
        for i in range(len(points) - 1):
            a, b = points[i], points[i + 1]
            ab = b - a
            t = max(0.0, min(1.0, (xy - a).dot(ab) / ab.length_squared)) if ab.length_squared > 0 else 0.0
            gap = (a + ab * t - xy).length
            if gap < best_gap:
                best_gap = gap
                best_d = lengths[i] + (lengths[i + 1] - lengths[i]) * t
        return best_d, best_gap

    def from_corner(d):
        return min(d, total - d)

    def ragged(d):
        return 1.0 + 0.22 * math.sin(d * 290.0 + 1.3) + 0.13 * math.sin(d * 670.0 + 0.4)

    def peel(d, sign):
        if sign > 0:
            return R_UP * smoothstep(0.018, 0.060, from_corner(d)) * ragged(d)
        return R_LOW * smoothstep(0.018, 0.060, from_corner(d)) * ragged(d * 1.07 + 0.5)

    def taper(d):
        return smoothstep(0.0, 0.035, from_corner(d))

    def set_jaw(v, w):
        w = max(0.0, min(1.0, w))
        others = {g: x for g, x in v[deform].items() if g != jaw_group and x > 0.0}
        if not others:
            others = {head_group: 1.0}
        scale = (1.0 - w) / sum(others.values())
        v[deform].clear()
        for g, x in others.items():
            if x * scale > 1e-5:
                v[deform][g] = x * scale
        if w > 1e-5:
            v[deform][jaw_group] = w

    # --- jaw weights: fixed on the skull, the chin and the open lips, and
    # relaxed everywhere between so the cheeks and the throat stretch evenly.
    def chain_arc(chain):
        arc = arc_lengths([Vector((v.co.x, v.co.y)) for v in chain])
        return [a * total / arc[-1] for a in arc]

    upper_arc = chain_arc(upper)
    lower_arc = chain_arc(lower)
    skin = [v for v in bm.verts if any(f.material_index == 0 for f in v.link_faces)]
    region = [v for v in skin if 1.93 < v.co.z < 2.10 and v.co.y < 0.0]
    weight = {v: v[deform].get(jaw_group, 0.0) for v in region}
    fixed = {}
    for v in region:
        y, z = v.co.y, v.co.z
        if z > 2.06 or y > -0.035 or z < 1.95:
            fixed[v] = 0.0
        elif z > PLANE_Z + 0.001 and y < CORNER_Y - 0.02:
            fixed[v] = 0.0
        elif 1.99 < z < PLANE_Z - 0.001 and y < CORNER_Y - 0.04:
            fixed[v] = 1.0
    for chain, arc, value in ((upper, upper_arc, 0.0), (lower, lower_arc, 1.0)):
        for v, d in zip(chain, arc):
            if v in upper_set and v in lower_set:
                fixed.pop(v, None)
            elif from_corner(d) > 0.02:
                fixed[v] = value
            else:
                fixed.pop(v, None)
    weight.update(fixed)
    free = [v for v in region if v not in fixed]
    links = {}
    for v in free:
        links[v] = [(e.other_vert(v), 1.0 / max(e.calc_length(), 1e-5)) for e in v.link_edges]
    for _ in range(400):
        for v in free:
            numerator = 0.0
            denominator = 0.0
            for o, k in links[v]:
                numerator += k * (weight[o] if o in weight else o[deform].get(jaw_group, 0.0))
                denominator += k
            weight[v] = numerator / denominator
    for v in region:
        set_jaw(v, weight[v])
    report['weights'] = {'region': len(region), 'relaxed': len(free), 'corner': round(weight[upper[0]], 3)}

    def lip_weight(chain, arc, d):
        i = max(0, min(len(arc) - 2, bisect.bisect_right(arc, d) - 1))
        span = arc[i + 1] - arc[i]
        return lerp(weight[chain[i]], weight[chain[i + 1]], (d - arc[i]) / span if span > 0 else 0.0)

    def column_weight(d, sign):
        return lip_weight(upper, upper_arc, d) if sign > 0 else lip_weight(lower, lower_arc, d)

    # The floor of the mouth rides on the skin under the jaw, whose weight
    # fades toward the neck; follow it or that skin rises through the floor.
    under = KDTree(len(region))
    under_weights = []
    for v in region:
        if v.co.z < PLANE_Z - 0.004:
            under.insert(v.co, len(under_weights))
            under_weights.append(weight[v])
    under.balance()

    def under_weight(co):
        numerator = 0.0
        denominator = 0.0
        for _, index, distance in under.find_n(co, 4):
            k = 1.0 / max(distance, 1e-4)
            numerator += k * under_weights[index]
            denominator += k
        return numerator / denominator

    def floor_weight(d, row, co):
        return lerp(column_weight(d, -1), under_weight(co), smoothstep(2.0, 5.0, row))

    # --- peel the lips off the teeth
    peeled = 0
    for v in skin:
        dz = v.co.z - PLANE_Z
        if abs(dz) >= BAND:
            continue
        d, gap = project(Vector((v.co.x, v.co.y)))
        if gap > 0.03:
            continue
        if v in upper_set and v in lower_set:
            continue
        if v in upper_set:
            sign = 1
        elif v in lower_set:
            sign = -1
        elif abs(dz) < 1e-6:
            continue
        else:
            sign = 1 if dz > 0 else -1
        r = peel(d, sign)
        a = abs(dz)
        moved = r + a * (BAND - r) / BAND
        v.co.z = PLANE_Z + sign * lerp(a, moved, 1.0 - smoothstep(0.012, 0.03, gap))
        peeled += 1
    report['peeled_skin_verts'] = peeled

    # --- lining: gums, palate and floor as two sheets joined at the corners
    def lining_point(d, row, sign):
        p = footprint(d)
        back = Vector((p.x * BACK_X, BACK_Y))
        inward = back - p
        span = inward.length
        inward.normalize()
        t = taper(d)
        lip_rows = UPPER_LIP if sign > 0 else LOWER_LIP
        deep_rows = UPPER_DEEP if sign > 0 else LOWER_DEEP
        reach = min(lip_rows[-1][0] * 0.001 * (0.25 + 0.75 * t), span * 0.4)
        if row < len(lip_rows):
            mm, share, extra = lip_rows[row]
            along = min(mm * 0.001 * (0.25 + 0.75 * t), span * 0.4)
            h = peel(d, sign) * share + extra * 0.001 * t
        else:
            fraction, extra = deep_rows[row - len(lip_rows)]
            along = lerp(reach, span, fraction)
            h = extra * 0.001 * t
        h = max(h, 0.0002 * t)
        q = p + inward * along
        return Vector((q.x, q.y, PLANE_Z + sign * h))

    rows = len(UPPER_LIP) + len(UPPER_DEEP)
    depth_of = {}
    lining_faces = []
    max_depth = rows + WALL_ROWS + 1

    def face(verts):
        unique = []
        for v in verts:
            if v not in unique:
                unique.append(v)
        if len(unique) < 3 or bm.faces.get(unique) is not None:
            return
        lining_faces.append(bm.faces.new(unique))

    def sheet(sign, seam):
        table = []
        for row in range(rows):
            line = []
            for column in range(COLUMNS):
                if seam is not None and column in (0, COLUMNS - 1):
                    line.append(seam[row][column])
                    continue
                d = total * column / (COLUMNS - 1)
                co = lining_point(d, row, sign)
                v = bm.verts.new(co)
                set_jaw(v, column_weight(d, 1) if sign > 0 else floor_weight(d, row, co))
                depth_of[v] = row + 1
                line.append(v)
            table.append(line)
        for r in range(rows - 1):
            for c in range(COLUMNS - 1):
                face((table[r][c], table[r][c + 1], table[r + 1][c + 1], table[r + 1][c]))
        return table

    roof = sheet(1, None)
    floor = sheet(-1, roof)

    def zipper(a, b):
        """Triangulate between two polylines of different vertex counts."""
        ta = arc_lengths([v.co for v in a])
        tb = arc_lengths([v.co for v in b])
        ta = [x / ta[-1] for x in ta]
        tb = [x / tb[-1] for x in tb]
        i = j = 0
        while i < len(a) - 1 or j < len(b) - 1:
            advance_a = j == len(b) - 1 or (i < len(a) - 1 and ta[i + 1] <= tb[j + 1])
            face((a[i], a[i + 1], b[j]) if advance_a else (a[i], b[j + 1], b[j]))
            if advance_a:
                i += 1
            else:
                j += 1

    for v in loop:
        depth_of[v] = 0
    zipper(upper, roof[0])
    zipper(lower, floor[0])

    # --- throat: a dark pocket closing the back between palate and floor
    wall = [roof[-1]]
    for k in range(1, WALL_ROWS + 1):
        f = k / (WALL_ROWS + 1)
        line = []
        for column in range(COLUMNS):
            top, bottom = roof[-1][column], floor[-1][column]
            if top is bottom:
                line.append(top)
                continue
            co = top.co.lerp(bottom.co, f)
            co.y += 0.03 * ((top.co.z - bottom.co.z) / 0.026) * math.sin(math.pi * f)
            v = bm.verts.new(co)
            set_jaw(v, lerp(top[deform].get(jaw_group, 0.0), bottom[deform].get(jaw_group, 0.0), f))
            depth_of[v] = rows + k
            line.append(v)
        wall.append(line)
    wall.append(floor[-1])
    for r in range(len(wall) - 1):
        for c in range(COLUMNS - 1):
            face((wall[r][c], wall[r][c + 1], wall[r + 1][c + 1], wall[r + 1][c]))

    # Lining U runs lips -> throat; V < .5 selects the flesh ramp.
    for f in lining_faces:
        f.material_index = MAT_LINING
        f.smooth = True
        for corner_loop in f.loops:
            corner_loop[uv_layer].uv = (min(0.98, max(0.02, depth_of[corner_loop.vert] / max_depth)), 0.25)

    # --- teeth: needles rooted on both gum ridges, interleaved like a zipper
    rng = random.Random(23)
    tooth_faces = []

    def tooth(root, axis, inward, length, radius, w):
        side = axis.cross(inward).normalized()
        rings = []
        for along, scale in ((-0.16, 1.10), (0.22, 0.90), (0.62, 0.55), (1.0, 0.0)):
            centre = root + axis * (length * along) + inward * (length * 0.14 * max(0.0, along) ** 2)
            if scale == 0.0:
                v = bm.verts.new(centre)
                set_jaw(v, w)
                rings.append([v])
                continue
            ring = []
            for n in range(6):
                angle = math.tau * n / 6
                v = bm.verts.new(centre + (side * math.cos(angle) + inward * math.sin(angle) * 0.85) * radius * scale)
                set_jaw(v, w)
                ring.append(v)
            rings.append(ring)
        ring_v = (0.04, 0.34, 0.68, 0.97)
        for index, (a, b) in enumerate(zip(rings, rings[1:])):
            for n in range(6):
                if len(b) == 1:
                    f = bm.faces.new((a[n], a[(n + 1) % 6], b[0]))
                    values = (ring_v[index], ring_v[index], ring_v[index + 1])
                else:
                    f = bm.faces.new((a[n], a[(n + 1) % 6], b[(n + 1) % 6], b[n]))
                    values = (ring_v[index], ring_v[index], ring_v[index + 1], ring_v[index + 1])
                f.material_index = MAT_TEETH
                f.smooth = True
                for corner_loop, value in zip(f.loops, values):
                    corner_loop[uv_layer].uv = (0.5, value)
                tooth_faces.append(f)

    def tooth_row(sign, offset, ridge_mm, fang_every):
        made = 0
        slots = int(total / TOOTH_STEP)
        for n in range(slots):
            d = (n + offset) * TOOTH_STEP + rng.uniform(-0.0008, 0.0008)
            gap = peel(d, 1) + peel(d, -1)
            if gap < 0.0045 or rng.random() < 0.07:
                continue
            p = footprint(d)
            inward2 = Vector((p.x * BACK_X, BACK_Y)) - p
            inward2.normalize()
            inward = Vector((inward2.x, inward2.y, 0.0))
            tangent = Vector((-inward.y, inward.x, 0.0))
            root = Vector((p.x, p.y, PLANE_Z + sign * (peel(d, sign) - 0.0008))) + inward * (ridge_mm * 0.001)
            length = gap * rng.uniform(0.62, 0.9)
            if fang_every and made % fang_every == fang_every // 2:
                length = gap * rng.uniform(0.98, 1.08)
            radius = rng.uniform(0.0015, 0.0020) * (0.85 + 0.25 * length / 0.011)
            axis = (Vector((0.0, 0.0, -sign)) - inward * rng.uniform(0.04, 0.24) + tangent * rng.uniform(-0.14, 0.14)).normalized()
            tooth(root, axis, inward, length + 0.0015, radius, column_weight(d, sign))
            made += 1
        return made

    report['upper_teeth'] = tooth_row(1, 0.25, 4.2, 4)
    report['lower_teeth'] = tooth_row(-1, 0.75, 4.9, 5)

    # --- tongue: rests on the floor, rigid with the jaw
    tongue_faces = []
    floor_z = PLANE_Z - LOWER_DEEP[1][1] * 0.001
    sections = 12
    around = 10
    tongue_rings = []
    tongue_u = {}
    for k in range(sections + 1):
        f = k / sections
        y = lerp(BACK_Y - 0.004, -0.166, f)
        half = lerp(0.0135, 0.0165, math.sin(math.pi * min(1.0, f * 1.25))) * (1.0 - smoothstep(0.62, 1.0, f) * 0.86)
        thick = lerp(0.0070, 0.0034, f)
        lift = 0.0010 + 0.0020 * math.sin(math.pi * f)
        ring = []
        for n in range(around):
            angle = math.tau * n / around
            x = math.cos(angle) * half
            groove = 1.0 if math.sin(angle) < 0 else 1.0 - 0.38 * math.exp(-(x / (half * 0.35 + 1e-6)) ** 2)
            v = bm.verts.new(Vector((x, y, floor_z + lift + thick * 0.7 + math.sin(angle) * thick * groove)))
            set_jaw(v, under_weight(Vector((x, y, floor_z))))
            tongue_u[v] = 1.0 - f
            ring.append(v)
        tongue_rings.append(ring)
    tip = bm.verts.new(Vector((0.0, -0.1705, floor_z + 0.0040)))
    set_jaw(tip, 1.0)
    tongue_u[tip] = 0.0
    for a, b in zip(tongue_rings, tongue_rings[1:]):
        for n in range(around):
            tongue_faces.append(bm.faces.new((a[n], a[(n + 1) % around], b[(n + 1) % around], b[n])))
    for n in range(around):
        tongue_faces.append(bm.faces.new((tongue_rings[-1][n], tongue_rings[-1][(n + 1) % around], tip)))
    for f in tongue_faces:
        f.material_index = MAT_LINING
        f.smooth = True
        for corner_loop in f.loops:
            corner_loop[uv_layer].uv = (min(0.98, max(0.02, tongue_u[corner_loop.vert])), 0.75)

    lining_faces = [f for f in lining_faces if f.is_valid]
    bmesh.ops.recalc_face_normals(bm, faces=lining_faces + tooth_faces + tongue_faces)
    # recalc works per island; orient the lining so the palate faces down.
    centre = Vector((0.0, -0.14, PLANE_Z))
    facing = sum(1 if f.normal.dot(centre - f.calc_center_median()) > 0 else -1 for f in lining_faces)
    if facing < 0:
        bmesh.ops.reverse_faces(bm, faces=lining_faces)
    report['new_faces'] = len(lining_faces) + len(tooth_faces) + len(tongue_faces)
    report['boundary_edges'] = sum(1 for e in bm.edges if e.is_boundary)
    report['verts'] = len(bm.verts)
    report['triangles'] = sum(len(f.verts) - 2 for f in bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.update()
    materials(mesh)


def ramp_image(name, width, height, pixel):
    image = bpy.data.images.get(name) or bpy.data.images.new(name, width, height, alpha=False)
    image.scale(width, height)
    data = []
    for y in range(height):
        for x in range(width):
            r, g, b = pixel((x + 0.5) / width, (y + 0.5) / height)
            data.extend((r, g, b, 1.0))
    image.pixels = data
    image.pack()
    return image


def gradient(stops, t):
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        if t <= b:
            f = smoothstep(a, b, t)
            return tuple(lerp(x, y, f) for x, y in zip(ca, cb))
    return stops[-1][1]


def materials(mesh):
    rng = random.Random(7)
    flesh = [(0.0, (0.105, 0.040, 0.036)), (0.08, (0.190, 0.042, 0.040)), (0.28, (0.150, 0.026, 0.026)),
             (0.50, (0.060, 0.010, 0.010)), (0.75, (0.010, 0.002, 0.002)), (1.0, (0.002, 0.0, 0.0))]
    tongue = [(0.0, (0.210, 0.050, 0.055)), (0.45, (0.150, 0.030, 0.036)), (1.0, (0.030, 0.006, 0.008))]

    def lining_pixel(u, v):
        base = gradient(flesh if v < 0.5 else tongue, u)
        grain = 1.0 + rng.uniform(-0.10, 0.10)
        return tuple(max(0.0, c * grain) for c in base)

    stained = [(0.0, (0.130, 0.070, 0.034)), (0.20, (0.400, 0.280, 0.140)), (0.6, (0.640, 0.560, 0.380)), (1.0, (0.780, 0.740, 0.580))]

    def tooth_pixel(u, v):
        base = gradient(stained, v)
        grain = 1.0 + rng.uniform(-0.07, 0.07)
        return tuple(c * grain for c in base)

    lining_image = ramp_image('Raker023_MouthLining', 64, 32, lining_pixel)
    tooth_image = ramp_image('Raker023_Teeth', 8, 64, tooth_pixel)
    for slot, image, roughness in ((MAT_LINING, lining_image, 0.28), (MAT_TEETH, tooth_image, 0.34)):
        material = mesh.material_slots[slot].material
        tree = material.node_tree
        shader = next(n for n in tree.nodes if n.type == 'BSDF_PRINCIPLED')
        texture = next((n for n in tree.nodes if n.type == 'TEX_IMAGE'), None) or tree.nodes.new('ShaderNodeTexImage')
        texture.image = image
        texture.interpolation = 'Linear'
        tree.links.new(texture.outputs['Color'], shader.inputs['Base Color'])
        shader.inputs['Roughness'].default_value = roughness
        material.use_backface_culling = False
    stale = bpy.data.images.get('Raker018_InternalTeeth_Color')
    if stale is not None and stale.users == 0:
        bpy.data.images.remove(stale)


if __name__ == '__main__':
    result = {}
    build(result)
    print('MOUTH', result)
    arguments = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if arguments:
        bpy.ops.wm.save_as_mainfile(filepath=arguments[0], compress=True)
