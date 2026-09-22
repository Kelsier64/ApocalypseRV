import bpy
import math
from mathutils import Vector, Matrix, Quaternion
scene=bpy.data.scenes["MONSTER_REFINED_V016"]
bpy.context.window.scene=scene
rig=bpy.data.objects["Refined016_Rig"]
for track in list(rig.animation_data.nla_tracks):
    if track.name.startswith("grab_"): rig.animation_data.nla_tracks.remove(track)
def capture(clip):
    action = next(t.strips[0].action for t in rig.animation_data.nla_tracks if t.name == clip)
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    scene.frame_set(0)
    bpy.context.view_layer.update()
    return {p.name:p.matrix_basis.copy() for p in rig.pose.bones}

bases = {'stand':capture('idle'), 'low':capture('crouch_idle'), 'seat':capture('crouch_idle')}
rig.animation_data.action = None

def smooth(t):
    t = max(0,min(1,t))
    return t*t*(3-2*t)

def rotate(name, axis, degrees):
    p = rig.pose.bones[name]
    local = p.bone.matrix_local.to_3x3().inverted() @ Vector(axis)
    p.rotation_quaternion = p.rotation_quaternion @ Quaternion(local, math.radians(degrees))

def aim(name, child, target):
    bpy.context.view_layer.update()
    p = rig.pose.bones[name]
    origin = p.matrix.translation.copy()
    old = rig.pose.bones[child].matrix.translation-origin
    q = old.normalized().rotation_difference((target-origin).normalized())
    p.matrix = Matrix.Translation(origin) @ q.to_matrix().to_4x4() @ p.matrix.to_3x3().to_4x4()
    bpy.context.view_layer.update()

def arm(side, target, weight):
    upper,fore,hand = ['upper_arm_'+side,'forearm_'+side,'hand_'+side]
    bpy.context.view_layer.update()
    shoulder = rig.pose.bones[upper].matrix.translation.copy()
    elbow = rig.pose.bones[fore].matrix.translation.copy()
    wrist = rig.pose.bones[hand].matrix.translation.copy()
    target = wrist.lerp(Vector(target),weight)
    a,b = (elbow-shoulder).length,(wrist-elbow).length
    direction = (target-shoulder).normalized()
    distance = min((target-shoulder).length,a+b-.001)
    along = (a*a-b*b+distance*distance)/(2*distance)
    height = math.sqrt(max(0,a*a-along*along))
    down = Vector((.20 if side=='L' else -.20,0,1 if variant=='seat' else -1))
    bend = (down-direction*down.dot(direction)).normalized()
    aim(upper,fore,shoulder+direction*along+bend*height)
    aim(fore,hand,shoulder+direction*distance)
    # Palm across the shoulder, fingers hanging toward the victim's chest.
    p=rig.pose.bones[hand]
    current=p.matrix.to_quaternion()
    axis=(p.bone.tail_local-p.bone.head_local).normalized()
    rest=p.bone.matrix_local.to_quaternion()
    desired=Vector((0,-.22,-1)).normalized()
    orientation=current if variant=="seat" else axis.rotation_difference(desired) @ rest
    p.matrix=Matrix.Translation(p.matrix.translation) @ current.slerp(orientation,weight).to_matrix().to_4x4()

durations={'reach':.6,'hold':1.0,'bite':.65,'release':.35,'escape':.45,'miss':.45}
for variant in ['stand','low','seat']:
    for phase, seconds in durations.items():
        name='grab_'+variant+'_'+phase
        action=bpy.data.actions.new('raker_v016_'+name)
        action.use_fake_user=True
        rig.animation_data.action=action
        count=round(seconds*60)
        for frame in range(count+1):
            t=frame/count
            for p in rig.pose.bones: p.matrix_basis=bases[variant][p.name].copy()
            weight=smooth(t) if phase=='reach' else (1-smooth(t) if phase in ['release','escape','miss'] else 1)
            jaw_angle=0
            if phase=='hold':
                rotate('spine_03',(1,0,0),math.sin(t*math.tau)*1.0)
                jaw_angle=7+3*math.sin(t*math.tau)
            elif phase=='bite':
                seconds_now=frame/60
                opening=smooth(seconds_now/.22) if seconds_now<.22 else 1-smooth((seconds_now-.22)/.16)
                jaw_angle=38*opening
                nod=(-10*opening+0*smooth((seconds_now-.22)/.16))*(1-smooth((seconds_now-.42)/.23))
                for bone,fraction in [('neck_01',.35),('neck_02',.35),('head',.30)]: rotate(bone,(1,0,0),nod*fraction)
            elif phase=='escape':
                rotate('spine_02',(1,0,0),-8*math.sin(t*math.pi))
                rotate('spine_03',(0,0,1),8*math.sin(t*math.pi))
            height={'stand':1.2,'low':1.06,'seat':1.46}[variant]
            for side,sign in [('L',1),('R',-1)]:
                rotate("clavicle_"+side,(0,0,1),-sign*(35 if variant=="seat" else 22)*weight)
                if variant=="seat": rotate("clavicle_"+side,(0,1,0),-sign*35*weight)
                arm(side,(sign*.23,-.87,height),weight)
                for finger in ['index','middle','ring','pinky']:
                    bone=finger+'_02_'+side
                    if bone in rig.pose.bones: rotate(bone,(1,0,0),12*weight)
            rotate('jaw',(1,0,0),jaw_angle)
            for p in rig.pose.bones:
                p.keyframe_insert(data_path='location',frame=frame)
                p.keyframe_insert(data_path='rotation_quaternion',frame=frame)
                p.keyframe_insert(data_path='scale',frame=frame)
        track=rig.animation_data.nla_tracks.new()
        track.name=name
        strip=track.strips.new(name,0,action)
        strip.action_slot=action.slots[0]
        track.mute=True
        print('BAKED',name,seconds)
scene['revision']='v016 articulated jaw, 18 grab clips; 2.18 m neutral height'
print('AUTHORED',len(rig.data.bones),'bones',len(rig.animation_data.nla_tracks),'clips')
