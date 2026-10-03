"""Append authored prone/crawl actions to the separate dismemberment rig in Blender."""
import bpy
import math
import sys
from pathlib import Path
from mathutils import Vector, Matrix
ROOT = str(Path(__file__).resolve().parents[1])
scene = bpy.context.scene
rig = next(o for o in scene.objects if o.type == 'ARMATURE' and o.name.startswith('PLAYER_Rig'))
rest = {b.name:b.matrix_local.copy() for b in rig.data.bones}
rig.animation_data_clear()
rig.animation_data_create()
for p in rig.pose.bones: p.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
# This pass changes only animation; the refined head/cut meshes are separate.
FPS=60
scene.render.fps=FPS

def set_global(name,matrix):
    rig.pose.bones[name].matrix=matrix
    bpy.context.view_layer.update()

def floor_joint(start, end, l1, l2, height, side):
    """Two-bone solution with the elbow/knee on a specified support plane."""
    a = math.sqrt(max(.0001, l1*l1-(height-start.z)**2))
    b = math.sqrt(max(.0001, l2*l2-(height-end.z)**2))
    delta = Vector((end.x-start.x, end.y-start.y, 0))
    distance = delta.length
    assert abs(a-b) < distance < a+b, (start[:], end[:], height)
    direction = delta.normalized()
    along = (a*a-b*b+distance*distance)/(2*distance)
    perpendicular = Vector((-direction.y, direction.x, 0))
    if perpendicular.x * side < 0: perpendicular.negate()
    joint = start + direction*along + perpendicular*math.sqrt(max(0, a*a-along*along))
    joint.z = height
    return joint

def chain(first, second, tip, target, joint_height, side):
    start = rig.pose.bones[first].head.copy()
    l1 = (rest[second].translation-rest[first].translation).length
    l2 = (rest[tip].translation-rest[second].translation).length
    joint = floor_joint(start, target, l1, l2, joint_height, side)
    for name, at, end, child in [(first, start, joint, second), (second, joint, target, tip)]:
        natural = rest[child].translation-rest[name].translation
        m = natural.rotation_difference(end-at).to_matrix().to_4x4() @ rest[name]
        m.translation = at
        set_global(name, m)

def mesh_bottom(name):
    evaluated = scene.objects[name].evaluated_get(bpy.context.evaluated_depsgraph_get())
    geometry = evaluated.to_mesh()
    lowest = min(v.co.z for v in geometry.vertices)
    evaluated.to_mesh_clear()
    return lowest

def part_bottom(part):
    # Include collar, undershirt, laces and other skinned clothing surfaces.
    return min(mesh_bottom(o.name) for o in scene.objects if o.type == 'MESH' and o.name.startswith('Part_'+part+'__'))

def arm(side,target,lift):
    upper,lower,hand=[rig.pose.bones[n+'_'+side] for n in ['upper_arm','forearm','hand']]
    s=1 if side=='L' else -1
    chain(upper.name, lower.name, hand.name, target, .090+lift*.65, s)
    # Match wrist's anatomical axes; palms down, fingers forward along floor.
    forward=(rest['middle_01_'+side].translation-rest[hand.name].translation).normalized()
    radial=rest['index_01_'+side].translation-rest['pinky_01_'+side].translation
    radial=(radial-forward*radial.dot(forward)).normalized()
    source=Matrix((radial,forward,radial.cross(forward))).transposed()
    dest_radial=Vector((-s,0,0)); dest_forward=Vector((0,-1,0))
    destination=Matrix((dest_radial,dest_forward,dest_radial.cross(dest_forward))).transposed()
    m=(destination@source.transposed()).to_4x4()@rest[hand.name]
    m.translation=target; set_global(hand.name,m)

def pose(name,t):
    for p in rig.pose.bones:
        p.rotation_mode='QUATERNION'; p.matrix_basis=Matrix.Identity(4)
    moving=name.startswith('crawl_')
    phase=t*math.tau
    one='onearm' in name
    lean_side=1 if name.endswith('_L') else -1
    yaw=math.radians((2.5*lean_side if one else 1.2)*math.sin(phase)) if moving else 0
    rot=Matrix.Rotation(yaw,4,'Z')@Matrix.Rotation(math.radians(89),4,'X')
    center=Vector(((lean_side*.012 if one else 0)+.006*math.sin(phase) if moving else 0,.18,.14))
    world=Matrix.Translation(center)@rot@Matrix.Translation(-rest['pelvis'].translation)
    for b in rig.data.bones:
        if b.name!='root': set_global(b.name,world@rest[b.name])
    # Ground the clothing surface, not merely the pelvis bone. A few millimetres
    # of breathing avoids the old push-up silhouette without floor penetration.
    center.z += .009+.003*(1+math.cos(phase*2))-part_bottom('torso')
    world=Matrix.Translation(center)@rot@Matrix.Translation(-rest['pelvis'].translation)
    for b in rig.data.bones:
        if b.name!='root': set_global(b.name,world@rest[b.name])
    # Look forward without asking the first-person camera to inherit body roll.
    head=rig.pose.bones['head']; m=Matrix.Rotation(math.radians(18),4,'X')@rest['head']; m.translation=head.head.copy(); set_global('head',m)
    for side,s in [('L',1),('R',-1)]:
        cycle=(t+(0 if side=='L' or one else .5))%1
        support=.67
        if cycle<support:
            travel=-.17+.34*cycle/support; lift=0
        else:
            u=(cycle-support)/(1-support)
            travel=.17*math.cos(math.pi*u); lift=.045*math.sin(math.pi*u)**2
        if not moving: travel=0; lift=0
        target=Vector((s*(.28 if one else .26),-.50+travel,.056+lift))
        arm(side,target,lift)
        # Residual leg trails behind the pelvis; avoid a standing/kneeling pose.
        thigh='thigh_'+side; shin='shin_'+side; foot='foot_'+side
        hip=rig.pose.bones[thigh].head.copy()
        ankle=Vector((hip.x+s*.035,hip.y+.595,.12))
        chain(thigh, shin, foot, ankle, .095, s)
        m=Matrix.Rotation(math.radians(90),4,'X')@rest[foot]
        m.translation=ankle
        set_global(foot,m)
        # The boot points back along the floor. Solve the leg again after its
        # contact height is known, retaining anatomical segment lengths.
        part=('left' if side=='L' else 'right')+'_leg'
        for iteration in range(3):
            ankle.z += .009-part_bottom(part)
            chain(thigh, shin, foot, ankle, .095, s)
            m.translation=ankle
            set_global(foot,m)
    bpy.context.view_layer.update()

clips={'prone_idle':2.0,'crawl_missing_left_leg':1.1,'crawl_missing_right_leg':1.1,'crawl_no_legs':1.25,'crawl_onearm_L':1.45,'crawl_onearm_R':1.45}
if '--inspect-prone' in sys.argv:
    for name in clips:
        for phase in [0, .25, .5, .75]:
            pose(name, phase)
            print('PRONE_POSE', name, phase, {n:round(part_bottom(n),4) for n in ['torso','left_arm','right_arm','left_leg','right_leg','head']}, 'JOINTS', {n:[round(v,3) for v in rig.pose.bones[n].head] for n in ['pelvis','spine_02','head','forearm_L','hand_L','shin_L','foot_L']}, flush=True)
    raise SystemExit(0)
for name,seconds in clips.items():
    frames=[]
    count=round(seconds*FPS)
    for frame in range(count+1):
        pose(name,frame/count)
        frames.append({p.name:p.matrix.copy() for p in rig.pose.bones})
    frames[-1]={n:m.copy() for n,m in frames[0].items()}
    action=bpy.data.actions.new(name); action.use_fake_user=True; rig.animation_data.action=action
    for frame,matrices in enumerate(frames):
        for b in rig.data.bones:
            p=rig.pose.bones[b.name]
            p.matrix_basis=rest[b.name].inverted()@rest[b.parent.name]@matrices[b.parent.name].inverted()@matrices[b.name] if b.parent else rest[b.name].inverted()@matrices[b.name]
            p.keyframe_insert('location',frame=frame);p.keyframe_insert('rotation_quaternion',frame=frame);p.keyframe_insert('scale',frame=frame)
    track=rig.animation_data.nla_tracks.new();track.name=name
    strip=track.strips.new(name,0,action);strip.action_slot=action.slots[0]
    print('BAKED_INJURY',name,flush=True)
rig.animation_data.action=None
for o in scene.objects:
    o.hide_set(False);o.select_set(o==rig or o.name.startswith(('Part_','Wound_','Cap_')))
bpy.context.view_layer.objects.active=rig
export_props=bpy.ops.export_scene.gltf.get_rna_type().properties
import io_scene_gltf2
assert 'GLB' in [i[0] for i in io_scene_gltf2.get_format_items(None, bpy.context)]
assert 'NLA_TRACKS' in [i.identifier for i in export_props['export_animation_mode'].enum_items]
bpy.ops.export_scene.gltf(filepath=ROOT+'/assets/models/player_dismemberment/player_injury_animations.glb',use_selection=True,use_active_scene=True,export_format='GLB',export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_skins=True,export_yup=True)
for track in rig.animation_data.nla_tracks:track.mute=True
rig.animation_data.action=rig.animation_data.nla_tracks['crawl_missing_left_leg'].strips[0].action
rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_set(0)
for o in scene.objects:
    if o.type=='MESH':o.hide_set(o.name.startswith(('Cap_','Wound_','Part_left_leg')) or o.name=='Icosphere')
    if o.name.startswith('Wound_left_leg'):o.hide_set(False)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/art_source/player_dismemberment/player_dismemberment.blend')
print('PLAYER_INJURY_ANIMATIONS_COMPLETE',flush=True)
