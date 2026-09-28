"""Blender background authoring; reads v020 and writes a separate v021 asset.

Run: blender -b <player_godot_export_v020.blend> --python scripts/build_player_animations.py
Only pose animation is authored. Meshes, bind/rest matrices and weights stay intact.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models/player_animations_v021'
SOURCE = ROOT / 'art_source/player_animations_v021'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / '.gdignore').touch()
rig = bpy.data.objects['PLAYER_Rig']
scene = bpy.context.scene
FPS = 60
scene.render.fps = FPS
bpy.context.preferences.filepaths.save_version = 0
scene.frame_set(1)
rig.animation_data_clear()
rig.animation_data_create()
deform = [b.name for b in rig.data.bones if b.use_deform]
constraints = [(c, c.influence) for p in rig.pose.bones for c in p.constraints]
meshes = [o for o in bpy.data.collections['PLAYER_GAME'].all_objects if o.type == 'MESH']
assert len(meshes) == 11 and len(deform) == 41
rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
body = bpy.data.objects['PLAYER_Mesh']
boot_vertices = {side: [v.index for v in body.data.vertices if v.co.z < .26 and v.co.x * sign > 0] for side, sign in [('L', 1), ('R', -1)]}

def rotate(name, axis, degrees):
    p = rig.pose.bones[name]
    local = p.bone.matrix_local.to_3x3().inverted() @ Vector(axis)
    p.rotation_quaternion = p.rotation_quaternion @ Quaternion(local, math.radians(degrees))

def move(name, offset):
    bpy.context.view_layer.update()
    p = rig.pose.bones[name]
    m = p.matrix.copy()
    m.translation += Vector(offset)
    p.matrix = m
    bpy.context.view_layer.update()

def place_arm(side, target):
    """Pose a two-bone arm; bind matrices and skinning stay untouched."""
    bpy.context.view_layer.update()
    upper = rig.pose.bones['upper_arm_' + side]
    forearm = rig.pose.bones['forearm_' + side]
    shoulder = upper.head.copy()
    aim = Vector(target) - shoulder
    distance = min(aim.length, upper.length + forearm.length - .008)
    forward = aim.normalized()
    pole = Vector((1 if side == 'L' else -1, .1, -.35))
    bend = (pole - forward * pole.dot(forward)).normalized()
    along = (upper.length ** 2 - forearm.length ** 2 + distance ** 2) / (2 * distance)
    elbow = shoulder + forward * along + bend * math.sqrt(max(0, upper.length ** 2 - along ** 2))
    wrist = shoulder + forward * distance
    for bone, start, end in [(upper, shoulder, elbow), (forearm, elbow, wrist)]:
        rotation = (bone.bone.tail_local - bone.bone.head_local).rotation_difference(end - start)
        matrix = rotation.to_matrix().to_4x4() @ rest[bone.name]
        matrix.translation = start
        bone.matrix = matrix
        bpy.context.view_layer.update()
    # Anatomical radial direction points toward the thumb. Map it inward,
    # with fingers upward: both palms face the wall (Blender -Y).
    hand = rig.pose.bones['hand_' + side]
    long = (hand.bone.tail_local - hand.bone.head_local).normalized()
    radial = rig.data.bones['index_01_' + side].head_local - rig.data.bones['pinky_01_' + side].head_local
    radial = (radial - long * radial.dot(long)).normalized()
    source = Matrix((radial, long, radial.cross(long))).transposed()
    target_radial = Vector((-1 if side == 'L' else 1, 0, 0))
    target_long = Vector((0, 0, 1))
    destination = Matrix((target_radial, target_long, target_radial.cross(target_long))).transposed()
    matrix = (destination @ source.transposed()).to_4x4() @ rest[hand.name]
    matrix.translation = wrist
    hand.matrix = matrix
    bpy.context.view_layer.update()

def author(clip, t):
    for p in rig.pose.bones:
        p.rotation_mode = 'QUATERNION'
        p.matrix_basis = Matrix.Identity(4)
    for c, influence in constraints:
        c.influence = influence
    for side in ['L', 'R']:
        for c in rig.pose.bones['forearm_' + side].constraints: c.influence = 0
        for c in rig.pose.bones['hand_' + side].constraints: c.influence = 0
        for c in rig.pose.bones['shin_' + side].constraints: c.influence = 1
        for c in rig.pose.bones['foot_' + side].constraints: c.influence = 1
    phase = t * math.tau
    running = clip.startswith('run')
    jumping = clip.startswith('jump_')
    climbing = clip.startswith('climb_')
    moving = clip != 'idle' and not jumping and not climbing
    sole_targets = {'L': 0.0, 'R': 0.0}
    sideways = clip.endswith('left') or clip.endswith('right')
    direction = Vector((-1 if clip.endswith('right') else 1, 0, 0)) if sideways else Vector((0, 1 if clip.endswith('back') else -1, 0))
    # Authored stance is relaxed, rather than the skinning reference A pose.
    for side, sign in [('L', 1), ('R', -1)]:
        rotate('upper_arm_' + side, (0, 1, 0), 19 * sign)
        if clip == 'jump_rise': elbow = 25 + 20 * (t * t * (3 - 2 * t))
        elif clip == 'jump_fall': elbow = 38 - 10 * (t * t * (3 - 2 * t))
        elif clip == 'jump_land': elbow = 8 + 20 * (1 - t)
        else: elbow = 60 if running else (40 if moving else 8)
        rotate('forearm_' + side, (1, 0, 0), -elbow)
        # Palms inward, thumbs forward, using wrist roll only.
        # Keep the original forearm animation unchanged.
        p = rig.pose.bones['hand_' + side]
        p.rotation_quaternion = p.rotation_quaternion @ Quaternion((0, 1, 0), math.radians(-90 * sign))
        # A loose resting cascade, with slightly more curl toward the little
        # finger; keep the thumb soft and the fingertips clear of the palm.
        for finger, angles in {'index': (18, 24), 'middle': (22, 28),
                               'ring': (26, 32), 'pinky': (30, 36),
                               'thumb': (6, 10)}.items():
            for segment, angle in zip(['01', '02'], angles):
                rotate(finger + '_' + segment + '_' + side, (1, 0, 0), angle)
    if climbing:
        exit_pose = clip == 'climb_exit'
        exit_weight = 1 - t * t * (3 - 2 * t) if exit_pose else 1.0
        move('CTRL_pelvis', (0, .015 * exit_weight, -.014 - .036 * exit_weight))
        rotate('spine_01', (1, 0, 0), 4 * exit_weight)
        for side, sign in [('L', 1), ('R', -1)]:
            cycle = (t + (0 if side == 'L' else .5)) % 1
            # Half-cycle support travels down relative to the ascending body;
            # the free hand returns upward with a small release from the wall.
            wave = math.cos(cycle * math.tau)
            release = max(0, -math.sin(cycle * math.tau))
            height = 1.30 + (.14 * wave if clip == 'climb_up' else .04 * sign)
            x = .25 * sign
            if clip in ['climb_left', 'climb_right']:
                x += (.07 if clip == 'climb_left' else -.07) * wave
            if exit_pose:
                # Blend pose matrices back to the exact relaxed standing arm.
                bpy.context.view_layer.update()
                relaxed = {n: rig.pose.bones[n + '_' + side].matrix.copy() for n in ['upper_arm', 'forearm', 'hand']}
            place_arm(side, (x, -.34 + (.05 * release if clip != 'climb_hold' else 0), height))
            if exit_pose:
                for n in ['upper_arm', 'forearm', 'hand']:
                    p = rig.pose.bones[n + '_' + side]
                    p.matrix = relaxed[n].lerp(p.matrix, exit_weight)
                    bpy.context.view_layer.update()
            for finger, relaxed_angles in {'index': (18, 24), 'middle': (22, 28), 'ring': (26, 32), 'pinky': (30, 36), 'thumb': (6, 10)}.items():
                for segment, angle in zip(['01', '02'], relaxed_angles):
                    p = rig.pose.bones[finger + '_' + segment + '_' + side]
                    p.rotation_quaternion = Quaternion()
                    rotate(p.name, (1, 0, 0), angle * (1 - exit_weight) + (5 if segment == '01' else 10) * exit_weight)
            lift = (.18 - .10 * wave) if clip == 'climb_up' else (.15 if side == 'L' else .25)
            if clip in ['climb_left', 'climb_right']: lift = .16 + .04 * release
            lift *= exit_weight
            move('CTRL_foot_' + side, (0, -.07 * exit_weight, lift))
            sole_targets[side] = lift
    elif jumping:
        ease = t * t * (3 - 2 * t)
        if clip == 'jump_rise':
            dip, lean, arm = -.014 - .016 * ease, 4 * ease, -8 - 14 * ease
            lifts = (.18 * ease, .12 * ease)
            travel = (-.08 * ease, .035 * ease)
        elif clip == 'jump_fall':
            dip, lean, arm = -.03, 4, -18 + 8 * ease
            lifts = (.12 * (1 - ease) + .015, .08 * (1 - ease) + .015)
            travel = (-.04 * (1 - ease), .02 * (1 - ease))
        else:
            compression = math.sin(math.pi * t)
            dip = -.014 - .016 * (1 - t) - .09 * compression
            lean, arm = 4 * (1 - t) + 4 * compression, -10 * (1 - t)
            lifts, travel = (0, 0), (0, 0)
        move('CTRL_pelvis', (0, -.015 * (1 - ease) if clip == 'jump_land' else -.015, dip))
        rotate('spine_01', (1, 0, 0), lean)
        rotate('head', (1, 0, 0), -lean * .5)
        for index, side in enumerate(['L', 'R']):
            move('CTRL_foot_' + side, (0, travel[index], lifts[index]))
            sole_targets[side] = lifts[index]
            rotate('upper_arm_' + side, (1, 0, 0), arm)
    elif not moving:
        move('CTRL_pelvis', (0, 0, -.014 + .002 * math.sin(phase)))
        rotate('spine_02', (1, 0, 0), .7 * math.sin(phase))
    else:
        amplitude = .36 if running else .30
        if sideways: amplitude = .13
        support = 2 * amplitude / ((8 if running else 5) * .5)
        dip = -.14 if running else -.11
        bounce = .065 if running else .045
        move('CTRL_pelvis', (0, -.035 if running else -.02, dip + bounce * (1 - math.cos(4 * math.pi * (t - support / 2)))))
        rotate('spine_01', (1, 0, 0), 12 if running else 6)
        rotate('spine_02', (0, 0, 1), 3 * math.sin(phase))
        for side, sign in [('L', 1), ('R', -1)]:
            cycle = (t + (0 if side == 'L' else .5)) % 1
            # Constant stance travel; smoothly return and lift during swing.
            support = 2 * amplitude / ((8 if running else 5) * .5)
            if cycle < support:
                distance = amplitude * (1 - 2 * cycle / support)
                lift = 0
            else:
                u = (cycle - support) / (1 - support)
                distance = amplitude * (-math.cos(math.pi * u))
                lift = (.22 if running else .15) * math.sin(math.pi * u) ** 2
            offset = direction * distance + Vector((0, 0, lift))
            sole_targets[side] = lift
            move('CTRL_foot_' + side, offset)
            rotate('upper_arm_' + side, (1, 0, 0), (38 if running else 28) * math.sin(phase) * sign)
    bpy.context.view_layer.update()
    # The boot blends ankle and shin weights. Ground its evaluated sole,
    # rather than assuming that an ankle controller implies a flat sole.
    for iteration in range(3):
        evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        geometry = evaluated.to_mesh()
        offsets = {side: sole_targets[side] - min(geometry.vertices[i].co.z for i in ids) for side, ids in boot_vertices.items()}
        evaluated.to_mesh_clear()
        for side, offset in offsets.items(): move('CTRL_foot_' + side, (0, 0, offset))

# Directional variants retain forward-facing torso for first-person strafing.
clips = {'idle': 2.4}
for gait, seconds in [('jog', .5), ('run', .5)]:
    for direction in ['forward', 'back', 'left', 'right']:
        clips[gait + '_' + direction] = seconds
clips.update({'jump_rise': .2, 'jump_fall': .2, 'jump_land': .2})
clips.update({'climb_hold': 1.0, 'climb_up': .4, 'climb_left': .5, 'climb_right': .5, 'climb_exit': .3})
samples = {}
for name, seconds in clips.items():
    count = round(seconds * FPS)
    frames = []
    for frame in range(count + 1):
        author(name, frame / count)
        evaluated = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        matrices = {n: evaluated.pose.bones[n].matrix.copy() for n in deform}
        frames.append(matrices)
    samples[name] = frames

# Bake evaluated deform transforms, with no constraints evaluated a second time.
for c, _ in constraints: c.influence = 0
for name, frames in samples.items():
    action = bpy.data.actions.new('PLAYER_' + name)
    action.use_fake_user = True
    rig.animation_data.action = action
    for frame, matrices in enumerate(frames):
        for n in deform:
            p = rig.pose.bones[n]
            parent = p.parent
            p.matrix_basis = rest[n].inverted() @ rest[parent.name] @ matrices[parent.name].inverted() @ matrices[n] if parent else rest[n].inverted() @ matrices[n]
            p.keyframe_insert('location', frame=frame)
            p.keyframe_insert('rotation_quaternion', frame=frame)
            p.keyframe_insert('scale', frame=frame)
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 0, action)
    strip.action_slot = action.slots[0]
    print('BAKED', name, len(frames), flush=True)
rig.animation_data.action = None
for obj in bpy.context.selected_objects: obj.select_set(False)
for obj in [rig] + meshes: obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT / 'player_animations_v021.glb'), use_selection=True, use_active_scene=True,
    export_format='GLB', export_animations=True, export_animation_mode='NLA_TRACKS',
    export_def_bones=True, export_force_sampling=True, export_skins=True, export_yup=True)
for track in rig.animation_data.nla_tracks: track.mute = True
rig.animation_data.action = bpy.data.actions['PLAYER_idle']
rig.animation_data.action_slot = rig.animation_data.action.slots[0]
scene.frame_set(0)
scene['animation_notes'] = 'Baked deform Actions; original controls retained; constraints disabled while playing baked Actions. Original v020 remains unmodified.'
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / 'player_animations_v021.blend'))
(OUT / 'clips.json').write_text(json.dumps({'fps': FPS, 'clips': {n: (len(samples[n])-1)/FPS for n in clips}, 'non_looping_clips': [n for n in clips if n.startswith('jump_') or n == 'climb_exit'], 'deform_bones': deform, 'source': 'player_godot_export_v020.blend'}, indent=2))
print('PLAYER_ANIMATIONS_COMPLETE', flush=True)
