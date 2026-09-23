"""Correct anatomical hand orientation in Blender's baked source actions."""
import bpy, math, json
from mathutils import Vector, Matrix, Quaternion
from pathlib import Path
OUT=Path(__file__).resolve().parent
source=bpy.data.scenes['MONSTER_REFINED_V018']
scene=bpy.data.scenes.new('MONSTER_REFINED_V019');scene.render.fps=60
scene.world=source.world.copy();bpy.context.window.scene=scene
rig=bpy.data.objects['Refined018_Rig'].copy();rig.data=rig.data.copy();rig.name='Refined019_Rig';scene.collection.objects.link(rig)
mesh=bpy.data.objects['Refined018_Mesh'].copy();mesh.data=mesh.data.copy();mesh.name='Refined019_Mesh';mesh.parent=rig;scene.collection.objects.link(mesh)
for mod in mesh.modifiers:
    if mod.type=='ARMATURE':mod.object=rig
for ob in source.objects:
    if ob.name.startswith('Review018_'):
        copy=ob.copy();copy.data=ob.data.copy();copy.name=ob.name.replace('018','019');scene.collection.objects.link(copy)
        if copy.type=='CAMERA':scene.camera=copy
for track in rig.animation_data.nla_tracks:
    track.mute=True
    action=track.strips[0].action.copy();action.name='raker_v019_'+track.name
    track.strips[0].action=action;track.strips[0].action_slot=action.slots[0]
rig.data.pose_position='POSE'
HANGING={'idle','walk','chase','sprint','crouch_idle','crouch_walk','land','hit_react','death','crouch_land','crouch_hit_react','crouch_death'}

def smooth(t):
    t=max(0,min(1,t));return t*t*(3-2*t)

def frame(side,rest=False):
    def at(name):
        b=rig.data.bones[name+'_'+side] if rest else rig.pose.bones[name+'_'+side]
        return b.head_local.copy() if rest else b.matrix.translation.copy()
    h,mi,th=at('hand'),at('middle_01'),at('thumb_01')
    fingers=(mi-h).normalized()
    thumb=th-mi;thumb=(thumb-fingers*thumb.dot(fingers)).normalized()
    return Matrix((thumb,fingers,thumb.cross(fingers))).transposed()

def desired_frame(fingers,thumb):
    fingers=fingers.normalized();thumb=(thumb-fingers*thumb.dot(fingers)).normalized()
    return Matrix((thumb,fingers,thumb.cross(fingers))).transposed()

def orient(side,goal):
    fore=rig.pose.bones['forearm_'+side];hand=rig.pose.bones['hand_'+side]
    wrist=hand.matrix.translation.copy();origin=fore.matrix.translation.copy();axis=(wrist-origin).normalized()
    # Measure pronation from the BIND palm, not the already inverted old hand.
    # This avoids baking a 180-degree corrective twist into forearm skin.
    thumb=fore.matrix.to_3x3()@fore.bone.matrix_local.to_3x3().inverted()@frame(side,True).col[0]
    a=(thumb-axis*thumb.dot(axis)).normalized();b=goal.col[0];b=(b-axis*b.dot(axis)).normalized()
    if a.length>.001 and b.length>.001:
        angle=math.atan2(axis.dot(a.cross(b)),a.dot(b))*.65
        fore.matrix=Matrix.Translation(origin)@Quaternion(axis,angle).to_matrix().to_4x4()@fore.matrix.to_3x3().to_4x4()
        bpy.context.view_layer.update()
    correction=goal@frame(side).inverted()
    hand.matrix=Matrix.Translation(wrist)@(correction@hand.matrix.to_3x3()).to_4x4()
    bpy.context.view_layer.update()

report=[]
for track in rig.animation_data.nla_tracks:
    if track.name not in HANGING and not track.name.startswith('grab_'):continue
    action=track.strips[0].action;rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
    last=int(action.frame_range[1]);samples=[]
    for f in range(last+1):
        scene.frame_set(f);bpy.context.view_layer.update()
        phase=track.name.split('_')[-1]
        weight=(smooth(f/max(1,last)) if phase=='reach' else 1-smooth(f/max(1,last)) if phase in ['release','escape','miss'] else 1) if track.name.startswith('grab_') else 0
        for side,sign in [('L',1),('R',-1)]:
            old=frame(side)
            hanging=desired_frame(old.col[1],Vector((0,-1,0)))
            gripping=desired_frame(Vector((0,-.9,-.4)),Vector((-sign,0,0)))
            goal=hanging.to_quaternion().slerp(gripping.to_quaternion(),weight).to_matrix()
            orient(side,goal)
            if weight>0:
                for digit in ['index','middle','ring','pinky']:
                    bone=rig.pose.bones[digit+'_02_'+side]
                    axis=bone.matrix.to_3x3().col[1].normalized()
                    q=axis.rotation_difference(Vector((0,-.3,-.95)).normalized())
                    bone.matrix=Matrix.Translation(bone.matrix.translation)@Quaternion().slerp(q,weight).to_matrix().to_4x4()@bone.matrix.to_3x3().to_4x4()
                    bpy.context.view_layer.update()
            for name in ['forearm','hand','index_02','middle_02','ring_02','pinky_02']:
                bone=rig.pose.bones[name+'_'+side]
                bone.rotation_quaternion.normalize()
                bone.keyframe_insert(data_path='rotation_quaternion',frame=f)
            if f in [0,last//2,last]:
                actual=frame(side);palm=actual.col[1].cross(actual.col[0])*sign
                samples.append({'frame':f,'side':side,'thumb':list(actual.col[0]),'fingers':list(actual.col[1]),'palm':list(palm)})
    report.append({'clip':track.name,'samples':samples})
    print('CORRECTED',track.name,flush=True)
(OUT/'hand_orientation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
rig.animation_data.action=next(t.strips[0].action for t in rig.animation_data.nla_tracks if t.name=='idle')
rig.animation_data.action_slot=rig.animation_data.action.slots[0];scene.frame_set(0)
scene['revision']='v019 source hand correction: thumbs forward, palms inward; authored grip anatomy'
for ob in scene.objects:ob.select_set(False)
rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'monster_refined_v019.blend'))
print('SAVED',OUT,flush=True)
