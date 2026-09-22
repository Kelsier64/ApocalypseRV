import bpy
import math
import json
from mathutils import Vector, Quaternion, Matrix
source_scene=bpy.data.scenes['MONSTER_218_DEFORMATION_FIXED']
rig=bpy.data.objects['MONSTER_Rig']
validation=bpy.data.actions['FIXED_218_POSE_VALIDATION']
rig.animation_data.action=validation
rig.animation_data.action_slot=validation.slots[0]
bpy.context.window.scene=source_scene
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
    m.translation = Vector((sign*.48,.28,.95))
    p.matrix = m
    bpy.context.view_layer.update()

scene=bpy.data.scenes.get('MONSTER_REFINED_V013')
if scene is None:
    scene=bpy.data.scenes.new('MONSTER_REFINED_V013')
    scene.render.fps=30
    out_rig=bpy.data.objects['Refined012_Rig'].copy()
    out_rig.data=out_rig.data.copy()
    out_rig.name='Refined013_Rig'
    scene.collection.objects.link(out_rig)
    out_mesh=bpy.data.objects['Refined012_Mesh'].copy()
    out_mesh.data=out_mesh.data.copy()
    out_mesh.name='Refined013_Mesh'
    out_mesh.parent=out_rig
    scene.collection.objects.link(out_mesh)
    for modifier in out_mesh.modifiers:
        if modifier.type=='ARMATURE': modifier.object=out_rig
    source=bpy.data.scenes['MONSTER_REFINED_V012']
    for ob in source.objects:
        if ob.name.startswith('Review012_'):
            c=ob.copy();c.data=ob.data.copy();c.name=ob.name.replace('012','013');scene.collection.objects.link(c)
            if c.type=='CAMERA': scene.camera=c
    scene.world=source.world.copy()
else:
    out_rig=bpy.data.objects['Refined013_Rig']
    out_mesh=bpy.data.objects['Refined013_Mesh']
for track in out_rig.animation_data.nla_tracks: track.mute=True
out_rig.animation_data.action=None

def gait(name,t):
    pose(1)
    phase=t*math.tau
    stride,lift,lower,lean,swing = {'walk':(.32,.08,.07,9,.10),'chase':(.48,.19,.14,16,.23),'sprint':(.64,.27,.20,23,.36)}[name]
    move('CTRL_pelvis',(0,.03,-lower+.025*math.cos(phase*2)))
    rotate('spine_01',(1,0,0),lean)
    rotate('spine_02',(1,0,0),lean*.55)
    rotate('spine_03',(1,0,0),lean*.30)
    rotate('head',(1,0,0),8 if name=='walk' else 2)
    rotate('spine_01',(0,0,1),(3 if name=='walk' else 6)*math.sin(phase))
    for side,sign in [('L',1),('R',-1)]:
        wave=math.sin(phase)*sign
        move('CTRL_foot_'+side,(sign*.025,-stride*wave,lift*max(0,math.cos(phase)*sign)**2))
        hand(side,(sign*(.45 if name=='walk' else .50),-.15+swing*wave,.63+(0 if name=='walk' else .10)+.07*wave))
    bpy.context.view_layer.update()

deform=[p.name for p in rig.pose.bones if p.bone.use_deform]
for name,seconds in [('walk',1.2),('chase',.8),('sprint',.6)]:
    for track in list(out_rig.animation_data.nla_tracks):
        if track.name==name: out_rig.animation_data.nla_tracks.remove(track)
    action=bpy.data.actions.new('raker_v013_'+name)
    action.use_fake_user=True
    out_rig.animation_data.action=action
    count=round(seconds*30)
    for frame in range(count+1):
        gait(name,frame/count)
        evaluated=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        matrices={n:evaluated.pose.bones[n].matrix.copy() for n in deform}
        for n in deform:
            pb=out_rig.pose.bones[n]
            rest=pb.bone.matrix_local
            pb.matrix_basis=rest.inverted() @ pb.parent.bone.matrix_local @ matrices[pb.parent.name].inverted() @ matrices[n] if pb.parent else rest.inverted() @ matrices[n]
            pb.keyframe_insert(data_path='location',frame=frame)
            pb.keyframe_insert(data_path='rotation_quaternion',frame=frame)
            pb.keyframe_insert(data_path='scale',frame=frame)
    track=out_rig.animation_data.nla_tracks.new()
    track.name=name
    strip=track.strips.new(name,0,action)
    strip.action_slot=action.slots[0]
    track.mute=True
    action['loop']=True
    print('BAKED',name,count+1)
rig.animation_data.action=validation
rig.animation_data.action_slot=validation.slots[0]
source_scene.frame_set(1)
bpy.context.window.scene=scene
try: scene.render.engine='BLENDER_EEVEE'
except TypeError: pass
scene.render.resolution_x=700
scene.render.resolution_y=850
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
OUT='C:/Users/evan4/Projects/ApocalypseRV/art_source/monster_refined_v013/'
for name,frame in [('walk',9),('chase',6),('sprint',4)]:
    action=next(t.strips[0].action for t in out_rig.animation_data.nla_tracks if t.name==name)
    out_rig.animation_data.action=action
    out_rig.animation_data.action_slot=action.slots[0]
    scene.frame_set(frame)
    scene.camera.location=(3,-6,2.2)
    scene.camera.rotation_euler=(Vector((0,-.15,1.05))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
    scene.camera.data.ortho_scale=2.6
    scene.render.filepath=OUT+name+'.png'
    bpy.ops.render.render(write_still=True)
print('AUTHORED v013')


