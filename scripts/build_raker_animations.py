"""Run in Blender with the repaired v007 file open. Authored in-place clips.

Blender MCP can run the file's contents; no external modules or source writes.
The active source rig is preserved in its reference scene.
"""
import bpy
import math
import json
from mathutils import Vector, Quaternion, Matrix

OUTPUT = 'C:/Users/evan4/Projects/ApocalypseRV/assets/models/raker/raker.glb'
WORKFILE = 'C:/Users/evan4/Projects/ApocalypseRV/.godot/monster-pose-audit/raker_animated.blend'
source_scene = bpy.data.scenes['MONSTER_218_DEFORMATION_FIXED']
rig = bpy.data.objects['MONSTER_Rig']
mesh = bpy.data.objects['MONSTER_Mesh']
validation = rig.animation_data.action
bpy.context.window.scene = source_scene

def capture(frame):
    source_scene.frame_set(frame)
    bpy.context.view_layer.update()
    return {p.name: (p.matrix_basis.copy(), [c.influence for c in p.constraints]) for p in rig.pose.bones}

poses = {frame: capture(frame) for frame in [1, 20, 60, 200, 240, 250, 260, 270, 280, 300, 370, 390, 430, 440]}
rig.animation_data.action = None

def pose(a, b=None, t=0):
    for p in rig.pose.bones:
        ma, ca = poses[a][p.name]
        if b is None:
            p.matrix_basis = ma.copy()
            influences = ca
        else:
            mb, cb = poses[b][p.name]
            la, qa, sa = ma.decompose()
            lb, qb, sb = mb.decompose()
            p.matrix_basis = Matrix.LocRotScale(la.lerp(lb,t),qa.slerp(qb,t),sa.lerp(sb,t))
            influences = [x+(y-x)*t for x,y in zip(ca,cb)]
        for c, influence in zip(p.constraints, influences):
            c.influence = influence
    bpy.context.view_layer.update()

def rotate(name, axis, degrees):
    p = rig.pose.bones[name]
    local_axis = p.bone.matrix_local.to_3x3().inverted() @ Vector(axis)
    p.rotation_quaternion = p.rotation_quaternion @ Quaternion(local_axis, math.radians(degrees))

def move(name, offset):
    bpy.context.view_layer.update()
    p = rig.pose.bones[name]
    m = p.matrix.copy()
    m.translation += Vector(offset)
    p.matrix = m
    bpy.context.view_layer.update()

def hand(side, point):
    for name in ['forearm_'+side, 'hand_'+side]:
        for c in rig.pose.bones[name].constraints:
            c.influence = 1
    p = rig.pose.bones['CTRL_hand_'+side]
    m = p.matrix.copy()
    m.translation = Vector(point)
    p.matrix = m
    sign = 1 if side=='L' else -1
    p = rig.pose.bones['POLE_elbow_'+side]
    m = p.matrix.copy()
    m.translation = Vector((sign*.65,.15,1.25))
    p.matrix = m
    bpy.context.view_layer.update()

def ease(t):
    t = max(0,min(1,t))
    return t*t*(3-2*t)

def chain(t, points):
    for i in range(len(points)-1):
        ta, a = points[i]
        tb, b = points[i+1]
        if t<=tb:
            pose(a,b,ease((t-ta)/(tb-ta)))
            return
    pose(points[-1][1])

def author(name, t):
    phase = t*math.tau
    pose(1)
    if name in ['idle','walk','chase','crouch_idle','crouch_walk']:
        crouch = name.startswith('crouch')
        if crouch:
            pose(1,240,.93)
        if name.endswith('idle'):
            move('CTRL_pelvis',(0,0,.009*math.sin(phase)))
            rotate('spine_02',(1,0,0),1.5*math.sin(phase))
            rotate('head',(0,0,1),4*math.sin(phase))
        else:
            stride = .12 if crouch else (.40 if name=='chase' else .34)
            lift = .025 if crouch else (.17 if name=='chase' else .10)
            if not crouch: move('CTRL_pelvis',(0,0,-.035+.022*math.cos(phase*2)))
            for side, sign in [('L',1),('R',-1)]:
                wave = math.sin(phase)*sign
                move('CTRL_foot_'+side,(0,-stride*wave,lift*max(0,math.cos(phase)*sign)))
                if not crouch:
                    rotate('upper_arm_'+side,(1,0,0),wave*13)
            rotate('spine_01',(0,0,1),4*math.sin(phase))
    elif name in ['attack_left','attack_right']:
        a,b = (250,280) if name=='attack_left' else (430,440)
        chain(t,[(0,1),(.43,a),(.52,a),(.66,b),(.79,b),(1,1)])
    elif name=='crouch_attack':
        pose(1,240,.93)
        hand('L',(.55,-.65-.25*math.sin(math.pi*t),.85))
        hand('R',(-.55,-.62,.72))
    elif name in ['climb_loop','hang_idle','attack_door','slip_loop','mantle']:
        pose(1,300,.72)
        for side, sign in [('L',1),('R',-1)]:
            wave=math.sin(phase)*sign
            if name=='climb_loop':
                hand(side,(sign*.40,-.55,1.86+wave*.21))
                move('CTRL_foot_'+side,(0,-.20,.18+.16*wave))
            elif name=='attack_door':
                pull=math.sin(math.pi*min(t/.65,1))
                hand(side,(sign*.4,-.55+(.28*pull if side=='L' else 0),1.9))
            elif name=='mantle':
                hand(side,(sign*.48,-.78,1.9-.45*ease(t)))
                move('CTRL_foot_'+side,(0,-.25,.36*math.sin(math.pi*t)))
                rotate('spine_01',(1,0,0),15*math.sin(math.pi*t))
            else:
                hand(side,(sign*.40,-.52,1.9+(.08 if name=='slip_loop' else .015)*math.sin(phase)))
                move('CTRL_foot_'+side,(0,-.12,.10))
    elif name=='attack_down':
        bend=ease((t-.48)/.22) if t<.8 else 1-ease((t-.8)/.2)
        pose(1,240,bend)
        reach=2.12-1.92*bend
        for side, sign in [('L',1),('R',-1)]:
            rotate('clavicle_'+side,(0,1,0),-10*bend*sign)
            hand(side,(sign*.70,-.78+.28*bend,reach))
    elif name in ['roof_settle','land']:
        chain(t,[(0,1),(.3,200),(1,1)])
    elif name=='fall_loop':
        pose(1,20,.4)
        rotate('spine_01',(1,0,0),-8)
        for side, sign in [('L',1),('R',-1)]:
            move('CTRL_foot_'+side,(0,0,.12+.06*math.sin(phase)*sign))
    elif name in ['crouch_hit_react','crouch_land']:
        pose(1,240,.93)
        pulse=math.sin(math.pi*t)
        rotate('spine_02',(1,0,0),(-3 if name=='crouch_hit_react' else 3)*pulse)
        rotate('head',(1,0,0),6*pulse)
        move('CTRL_pelvis',(0,0,-.008*pulse))
    elif name=='hit_react':
        pulse=math.sin(math.pi*t)
        rotate('spine_01',(1,0,0),-12*pulse)
        rotate('head',(1,0,0),10*pulse)
        rotate('spine_03',(0,0,1),8*pulse)
    elif name in ['death','crouch_death']:
        # Collapse forward onto the side; root remains fixed for engine ownership.
        amount=ease(min(t/.8,1))
        low=name=='crouch_death'
        if low:
            pose(1,240,.93)
            evaluated=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
            held={p.name:p.matrix.copy() for p in evaluated.pose.bones}
        for p in rig.pose.bones:
            for c in p.constraints: c.influence=0
        if low:
            for p in rig.pose.bones:
                p.matrix_basis=p.bone.matrix_local.inverted() @ p.parent.bone.matrix_local @ held[p.parent.name].inverted() @ held[p.name] if p.parent else p.bone.matrix_local.inverted() @ held[p.name]
        rotate('pelvis',(1,0,0),78*amount)
        if not low: rotate('pelvis',(0,1,0),18*amount)
        move('pelvis',(0,-.12*amount,(-.4 if low else -.78)*amount))
        if not low:
            rotate('thigh_L',(1,0,0),-28*amount)
            rotate('shin_L',(1,0,0),50*amount)
            rotate('shin_R',(1,0,0),24*amount)
            rotate('upper_arm_L',(0,1,0),-25*amount)
            rotate('upper_arm_R',(0,1,0),25*amount)
        bpy.context.view_layer.update()
        evaluated_mesh=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
        verts=evaluated_mesh.to_mesh()
        bottom=min(v.co.z for v in verts.vertices)
        evaluated_mesh.to_mesh_clear()
        if bottom<0: move('pelvis',(0,0,-bottom))
    bpy.context.view_layer.update()

clips = {
    'idle':(2.4,True), 'walk':(1.2,True), 'chase':(.8,True),
    'attack_left':(1.2,False),'attack_right':(1.2,False),
    'crouch_idle':(2.4,True),'crouch_walk':(1.2,True),'crouch_attack':(1.2,False),
    'climb_loop':(1.0,True),'hang_idle':(1.6,True),'attack_door':(1.2,False),
    'mantle':(.7,False),'roof_settle':(.65,False),'attack_down':(1.4,False),
    'slip_loop':(.6,True),'fall_loop':(.8,True),'land':(.4,False),
    'hit_react':(.3,False),'death':(1.3,False),
    'crouch_hit_react':(.3,False),'crouch_land':(.4,False),'crouch_death':(1.3,False)
}
# Bake constrained source poses to a separate rig, never modifying v007 weights.
old_scene=bpy.data.scenes.get('RAKER_GAME_EXPORT')
if old_scene:
    for ob in list(old_scene.objects): bpy.data.objects.remove(ob,do_unlink=True)
    bpy.data.scenes.remove(old_scene)
for name in clips:
    old_action=bpy.data.actions.get('raker_'+name)
    if old_action: bpy.data.actions.remove(old_action,do_unlink=True)
game_scene = bpy.data.scenes.new('RAKER_GAME_EXPORT')
game_scene.render.fps=30
out_rig=rig.copy()
out_rig.data=rig.data.copy()
out_rig.animation_data_clear()
out_rig.name='Raker_Rig'
game_scene.collection.objects.link(out_rig)
out_rig.hide_set(False)
for p in out_rig.pose.bones:
    for c in list(p.constraints): p.constraints.remove(c)
out_mesh=mesh.copy()
out_mesh.data=mesh.data.copy()
out_mesh.name='Raker_Mesh'
out_mesh.parent=out_rig
for modifier in out_mesh.modifiers:
    if modifier.type=='ARMATURE': modifier.object=out_rig
game_scene.collection.objects.link(out_mesh)
out_rig.animation_data_create()
deform=[p.name for p in rig.pose.bones if p.bone.use_deform]
for name,(seconds,loop) in clips.items():
    action=bpy.data.actions.new('raker_'+name)
    action.use_fake_user=True
    out_rig.animation_data.action=action
    count=round(seconds*30)
    for frame in range(count+1):
        author(name,frame/count)
        evaluated=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        matrices={n:evaluated.pose.bones[n].matrix.copy() for n in deform}
        for n in deform:
            pb=out_rig.pose.bones[n]
            rest=pb.bone.matrix_local
            if pb.parent:
                pb.matrix_basis=rest.inverted() @ pb.parent.bone.matrix_local @ matrices[pb.parent.name].inverted() @ matrices[n]
            else:
                pb.matrix_basis=rest.inverted() @ matrices[n]
            pb.keyframe_insert(data_path='location',frame=frame)
            pb.keyframe_insert(data_path='rotation_quaternion',frame=frame)
            pb.keyframe_insert(data_path='scale',frame=frame)
    track=out_rig.animation_data.nla_tracks.new()
    track.name=name
    strip=track.strips.new(name,0,action)
    strip.action_slot=action.slots[0]
    track.mute=False
    action['loop']=loop
    print('BAKED',name,count+1)
out_rig.animation_data.action=None
rig.animation_data.action=validation
rig.animation_data.action_slot=validation.slots[0]
source_scene.frame_set(1)
bpy.context.window.scene=game_scene
game_scene.frame_set(0)
for obj in game_scene.objects: obj.select_set(True)
bpy.context.view_layer.objects.active=out_rig
# NLA exporter treats each named track as an independent clip.
bpy.ops.export_scene.gltf(filepath=OUTPUT,use_selection=True,use_active_scene=True,export_animations=True,
    export_animation_mode='NLA_TRACKS',export_def_bones=True,export_force_sampling=True,
    export_skins=True,export_yup=True)
game_scene['clip_manifest']=json.dumps(clips)
bpy.ops.wm.save_as_mainfile(filepath=WORKFILE)
print('RAKER_EXPORT_COMPLETE',OUTPUT)
