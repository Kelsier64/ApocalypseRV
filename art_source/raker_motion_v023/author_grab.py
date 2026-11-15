"""Raker v023 grab clips.

Re-authors the 18 grab_{stand,low,seat}_* clips on top of the v022 arm and
finger poses: struggle and wind-up in hold, a lunge, clamp and thrash in bite,
a rip and swallow in release, a stagger in escape and an overbalanced snap in
miss. The runtime still solves the face, the bite contact and the gripping arms
(enemies/raker_pose_modifier.gd); these clips carry the jaw, the body weight,
the planted legs and every pose the runtime leaves alone.
"""
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

FPS = 60
VARIANTS = {'stand': 1.0, 'low': 0.6, 'seat': 0.6}   # body amplitude per posture
FRAMES = {'reach': 36, 'hold': 60, 'bite': 40, 'release': 36, 'escape': 60, 'miss': 27}
# Mirrored by enemies/raker_grab.gd; tests/test_raker_grab.gd compares both sides.
BITE_CONTACT = 0.14
BITE_TEAR = 0.52
THRASH_CYCLES = 3.0
HOLD_TUGS = (0.06, 0.27, 0.48)
HOLD_TUG_ATTACK = 0.06
HOLD_TUG_RELEASE = 0.14
LEGS = (('L', 1), ('R', -1))
X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def ease(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


def ramp(a, b, x):
    return ease((x - a) / (b - a))


def lerp(a, b, t):
    return a + (b - a) * t


def keys(x, knots):
    """Eased piecewise curve through (time, value) knots."""
    if x <= knots[0][0]:
        return knots[0][1]
    for (xa, a), (xb, b) in zip(knots, knots[1:]):
        if x <= xb:
            return lerp(a, b, ease((x - xa) / (xb - xa)))
    return knots[-1][1]


def wave(cycles, x, phase=0.0):
    return math.sin(math.tau * cycles * x + phase)


# Heave timing, mirrored by RakerGrab.hold_tug()/yank()/thrash(). The runtime
# drags the victim on these beats; the clips only brace the body behind them,
# so the Raker never rocks on its own.

def _yank(x, attack, release):
    if x <= 0.0 or x >= attack + release:
        return 0.0
    if x < attack:
        return ease(x / attack)
    return 1.0 - ease((x - attack) / release)


def hold_tug(t):
    return max(_yank(t - at, HOLD_TUG_ATTACK, HOLD_TUG_RELEASE) for at in HOLD_TUGS)


def tear_progress(t):
    return max(0.0, min(1.0, (t - BITE_CONTACT) / BITE_TEAR))


def yank(t):
    tear = tear_progress(t)
    if tear <= 0.0 or tear >= 1.0:
        return 0.0
    cycle = tear * THRASH_CYCLES
    return _yank(cycle - math.floor(cycle), 0.3, 0.7) * lerp(0.6, 1.0, tear)


def thrash(t):
    return yank(t) * (1.0 if int(tear_progress(t) * THRASH_CYCLES) % 2 == 0 else -1.0)


# --- stances -----------------------------------------------------------------
# fwd/drop/sway in metres (toward the victim, down, to the Raker's left);
# lean/twist/roll/shrug/jaw/head_* in degrees; step = {side: (back, lift)}.

def reach(t, u):
    swell = math.sin(math.pi * u)
    return {'fwd': 0.05 * ease(u), 'drop': 0.035 * swell, 'lean': 3.0 * ease(u) + 4.0 * swell,
            'twist': 4.0 * swell, 'jaw': 4.0 * ease(u)}


def hold(t, u):
    struggle = 1.0 - ramp(0.66, 0.80, t)
    windup = ramp(0.70, 0.96, t)
    chomp = (t * 2.6) % 1.0
    gnash = 24.0 * (ease(chomp / 0.72) if chomp < 0.72 else 1.0 - ease((chomp - 0.72) / 0.28))
    # Planted and square to the victim: each heave sinks the hips back and
    # hunches the shoulders while the arms haul the head in.
    tug = hold_tug(t) * struggle
    return {'fwd': lerp(0.05 - 0.04 * tug, -0.03, windup),
            'drop': lerp(0.015 * tug, -0.015, windup),
            'lean': lerp(3.0 - 7.0 * tug, -7.0, windup),
            'shrug': lerp(2.0 + 6.0 * tug, 5.0, windup),
            'jaw': lerp(4.0 + gnash * struggle, 38.0, windup)}


def bite(t, u):
    lunge = ramp(0.02, BITE_CONTACT, t)
    tear = tear_progress(t)
    heave = yank(t)
    # Feet planted and hips square: every wrench sits the body back against
    # the clamped flesh. The head roll itself is solved at runtime.
    return {'fwd': lerp(-0.03, 0.12, lunge) - 0.04 * ease(tear) - 0.04 * heave,
            'drop': lerp(-0.015, 0.05, lunge) + 0.015 * heave,
            'lean': lerp(-7.0, 10.0, lunge) - 4.0 * ease(tear) - 6.0 * heave,
            'shrug': lerp(5.0, 0.0, lunge) + 6.0 * heave,
            'jaw': keys(t, [(0.0, 38.0), (0.085, 38.0), (BITE_CONTACT, 12.0)]) - 3.0 * heave}


def release(t, u):
    rip = ramp(0.0, 0.12, t)
    settle = ramp(0.30, 0.60, t)
    swing = math.sin(math.pi * min(1.0, t / 0.30))
    return {'fwd': lerp(lerp(0.04, -0.07, rip), 0.0, settle),
            'drop': lerp(lerp(0.03, -0.02, rip), 0.0, settle),
            'lean': lerp(lerp(4.0, -12.0, rip), 0.0, settle),
            'twist': 14.0 * swing,
            'roll': -8.0 * swing,
            'head_pitch': 24.0 * rip * (1.0 - settle),
            'head_yaw': 16.0 * swing,
            'head_roll': 10.0 * swing,
            'jaw': keys(t, [(0.0, 12.0), (0.10, 17.0), (0.22, 5.0), (0.32, 13.0), (0.42, 3.0), (0.52, 0.0)])}


def escape(t, u):
    hit = ramp(0.0, 0.10, t)
    recover = ramp(0.45, 0.95, t)
    reel = hit * (1.0 - recover)
    return {'fwd': lerp(lerp(0.05, -0.11, hit), 0.0, recover),
            'drop': 0.04 * math.sin(math.pi * ramp(0.05, 0.70, t)),
            'sway': 0.04 * wave(1.2, t, 0.5) * reel,
            'lean': lerp(lerp(3.0, -15.0, hit), 0.0, recover),
            'twist': -10.0 * wave(1.2, t) * reel,
            'roll': 5.0 * wave(1.2, t, 0.9) * reel,
            'shrug': 6.0 * reel,
            'head_pitch': 28.0 * ramp(0.0, 0.12, t) * (1.0 - ramp(0.30, 0.60, t)),
            'head_yaw': 10.0 * wave(3.0, t) * ramp(0.50, 0.60, t) * (1.0 - ramp(0.85, 1.0, t)),
            'jaw': keys(t, [(0.0, 6.0), (0.10, 32.0), (0.38, 26.0), (0.62, 4.0), (0.80, 0.0)]),
            'step': {'R': (0.14 * (ramp(0.08, 0.30, t) - ramp(0.62, 0.86, t)),
                           0.05 * (math.sin(math.pi * ramp(0.08, 0.30, t)) + math.sin(math.pi * ramp(0.62, 0.86, t))))}}


def miss(t, u):
    over = math.sin(math.pi * ramp(0.0, 0.75, u))
    back = 1.0 - ramp(0.60, 1.0, u)
    return {'fwd': 0.05 * back + 0.10 * over, 'drop': 0.06 * over, 'lean': 3.0 * back + 13.0 * over,
            'twist': 6.0 * over,
            'jaw': keys(u, [(0.0, 4.0), (0.16, 30.0), (0.27, 30.0), (0.34, 0.0)])}


STANCES = {'reach': reach, 'hold': hold, 'bite': bite, 'release': release, 'escape': escape, 'miss': miss}


def source_time(part, t, u):
    """Where in the v022 clip the arms and fingers come from, 0..1."""
    if part == 'release':
        return ease(min(1.0, t / 0.36))
    if part == 'escape':
        return ease(min(1.0, t / 0.50))
    if part == 'bite':
        return min(1.0, t / 0.65)
    return u


def author(scene, rig, report):
    pb = rig.pose.bones
    deform = [b.name for b in rig.data.bones if b.use_deform]
    constrained = [b.name for b in pb if b.name in deform and any(not c.mute for c in b.constraints)]
    assert not constrained, ('deform bones must be free of live constraints', constrained)
    tracks = {t.name: t for t in rig.animation_data.nla_tracks}
    for t in tracks.values():
        t.mute = True

    def frame(f):
        scene.frame_set(int(f), subframe=f - int(f))
        bpy.context.view_layer.update()

    def snapshot():
        return {b.name: b.matrix_basis.copy() for b in pb}

    def restore(pose):
        for name, matrix in pose.items():
            pb[name].matrix_basis = matrix
        bpy.context.view_layer.update()

    def turn(name, axis, degrees):
        if abs(degrees) < 1e-6:
            return
        bone = pb[name]
        m = bone.matrix.copy()
        at = Matrix.Translation(m.translation)
        bone.matrix = at @ Quaternion(axis, math.radians(degrees)).to_matrix().to_4x4() @ at.inverted() @ m
        bpy.context.view_layer.update()

    def shift(name, offset):
        m = pb[name].matrix.copy()
        m.translation += Vector(offset)
        pb[name].matrix = m
        bpy.context.view_layer.update()

    def solve_leg(side, sign, target):
        a, b, c = 'thigh_' + side, 'shin_' + side, 'foot_' + side
        hip = pb[a].matrix.translation.copy()
        l1 = (pb[b].matrix.translation - hip).length
        l2 = (pb[c].matrix.translation - pb[b].matrix.translation).length
        v = target.translation - hip
        distance = min(v.length, l1 + l2 - 0.003)
        axis = v.normalized()
        across = Vector((sign * 0.25, -1.3, 0.55)) - hip
        across = (across - axis * across.dot(axis)).normalized()
        along = (l1 * l1 - l2 * l2 + distance * distance) / (2 * distance)
        knee = hip + axis * along + across * math.sqrt(max(0.0, l1 * l1 - along * along))
        for name, child, destination in ((a, b, knee), (b, c, hip + axis * distance)):
            m = pb[name].matrix.copy()
            at = m.translation.copy()
            q = (pb[child].matrix.translation - at).rotation_difference(destination - at)
            pb[name].matrix = Matrix.Translation(at) @ q.to_matrix().to_4x4() @ Matrix.Translation(-at) @ m
            bpy.context.view_layer.update()
        m = target.copy()
        m.translation = pb[c].matrix.translation
        pb[c].matrix = m
        bpy.context.view_layer.update()
        return (pb[c].matrix.translation - target.translation).length

    def apply(stance, k):
        get = stance.get
        drop = get('drop', 0.0)
        lean = get('lean', 0.0)
        pitch = get('head_pitch', 0.0)
        shrug = get('shrug', 0.0) * k
        if k < 1.0:
            # Crouched under a ceiling: never rise, and rear back far less.
            drop = max(0.0, drop)
            lean = lean if lean > 0.0 else lean * 0.25
            pitch *= 0.3
            shrug = 0.0
        shift('pelvis', (get('sway', 0.0) * k, -get('fwd', 0.0) * k, -drop * k))
        twist = get('twist', 0.0) * k
        turn('pelvis', Z, twist * 0.5)
        turn('spine_01', Z, twist * 0.3)
        turn('spine_03', Z, twist * 0.2)
        turn('spine_01', X, lean * k * 0.40)
        turn('spine_02', X, lean * k * 0.35)
        turn('spine_03', X, lean * k * 0.25)
        turn('spine_02', Y, get('roll', 0.0) * k)
        turn('clavicle_L', Y, -shrug)
        turn('clavicle_R', Y, shrug)
        # Head motion shows wherever the runtime relaxes its face tracking.
        turn('neck_02', X, -pitch * 0.5)
        turn('head', X, -pitch * 0.5)
        turn('head', Z, get('head_yaw', 0.0))
        turn('head', Y, get('head_roll', 0.0))
        pb['jaw'].rotation_quaternion = Quaternion(X, math.radians(get('jaw', 0.0)))
        bpy.context.view_layer.update()

    for variant, k in VARIANTS.items():
        for part, frames in FRAMES.items():
            name = 'grab_%s_%s' % (variant, part)
            track = tracks[name]
            source = track.strips[0].action
            source_end = source.frame_range[1]
            rig.animation_data.action = source
            rig.animation_data.action_slot = source.slots[0]
            base = []
            for f in range(frames + 1):
                frame(source_time(part, f / FPS, f / frames) * source_end)
                base.append(snapshot())
            rig.animation_data.action = None
            output = []
            ankle_error = 0.0
            for f in range(frames + 1):
                restore(base[f])
                feet = {side: pb['foot_' + side].matrix.copy() for side, _ in LEGS}
                stance = STANCES[part](f / FPS, f / frames)
                apply(stance, k)
                for side, sign in LEGS:
                    back, lift = stance.get('step', {}).get(side, (0.0, 0.0))
                    feet[side].translation += Vector((0.0, back * k, lift * k))
                    ankle_error = max(ankle_error, solve_leg(side, sign, feet[side]))
                output.append({n: pb[n].matrix_basis.copy() for n in deform})
            action = source.copy()
            action.name = 'raker_v023_' + name
            bag = action.layers[0].strips[0].channelbag(action.slots[0])
            for curve in list(bag.fcurves):
                bag.fcurves.remove(curve)
            rig.animation_data.action = action
            rig.animation_data.action_slot = action.slots[0]
            for f, pose in enumerate(output):
                for n, m in pose.items():
                    bone = pb[n]
                    bone.matrix_basis = m
                    bone.keyframe_insert('location', frame=f, group=n)
                    bone.keyframe_insert('rotation_quaternion', frame=f, group=n)
            for curve in action.layers[0].strips[0].channelbag(action.slots[0]).fcurves:
                for point in curve.keyframe_points:
                    point.interpolation = 'LINEAR'
            rig.animation_data.action = None
            track.strips.remove(track.strips[0])
            strip = track.strips.new(name, 0, action)
            strip.action_slot = action.slots[0]
            report[name] = {'frames': frames + 1, 'seconds': round(frames / FPS, 4), 'max_ankle_error_m': round(ankle_error, 5)}
            print('CLIP', name, report[name])
