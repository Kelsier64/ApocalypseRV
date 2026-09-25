"""Cautious lowered-centre walk; preserves idle and all other actions."""
import bpy,math,json
from mathutils import Vector,Matrix,Quaternion
from math import sin,cos,pi
scene=bpy.data.scenes['PLAYER_MASKED_SURVIVOR'];bpy.context.window.scene=scene
rig=bpy.data.objects['Survivor_Rig'];rig.animation_data.action=None
for track in rig.animation_data.nla_tracks:track.mute=True
def reset_pose():
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
def proportion_height(z):
    if scene.get('proportion_revision',0)<6:return z
    if z<=.13:return z
    if z<=.935:return .13+(z-.13)*(.699/.805)
    if z<=1.49:return .829+(z-.935)*(.511/.555)
    return z-.15
def turn(name,axis,angle):
    rig.pose.bones[name].rotation_quaternion=Quaternion(Vector(axis),math.radians(angle))
    bpy.context.view_layer.update()
def aim(name,direction):
    pb=rig.pose.bones[name];rest=pb.bone.matrix_local.to_quaternion()
    q=(rest@Vector((0,1,0))).rotation_difference(Vector(direction).normalized())@rest
    pb.matrix=Matrix.Translation(pb.head)@q.to_matrix().to_4x4()
    bpy.context.view_layer.update()
def limb(upper,lower,target,pole):
    a=rig.pose.bones[upper].head.copy();target=Vector(target)
    l1=rig.data.bones[upper].length;l2=rig.data.bones[lower].length
    d=target-a;dist=min(d.length,l1+l2-.0005);dist=max(dist,abs(l1-l2)+.001);axis=d.normalized()
    p=Vector(pole);bend=(p-axis*p.dot(axis)).normalized()
    x=(l1*l1-l2*l2+dist*dist)/(2*dist);y=math.sqrt(max(0,l1*l1-x*x))
    elbow=a+axis*x+bend*y
    aim(upper,elbow-a);aim(lower,a+axis*dist-elbow)
def wrist(side,target,pole=(0,-1,0),direction=(0,0,-1),palm=None):
    s='.'+side;limb('upper_arm'+s,'forearm'+s,target,pole)
    # Explicit palmar normal removes the ambiguous 180-degree wrist twist.
    y=Vector(direction).normalized();z=Vector(palm if palm is not None else ((-1,0,0) if side=='L' else (1,0,0)))
    z=(z-y*z.dot(y)).normalized();x=y.cross(z).normalized()
    basis=Matrix(((x.x,y.x,z.x),(x.y,y.y,z.y),(x.z,y.z,z.z))).to_4x4()
    pb=rig.pose.bones['hand'+s];pb.matrix=Matrix.Translation(pb.head)@basis;bpy.context.view_layer.update()
def foot(side,target):
    s='.'+side;limb('thigh'+s,'shin'+s,target,(0,-1,0))
    pb=rig.pose.bones['foot'+s];pb.matrix=Matrix.Translation(pb.head)@pb.bone.matrix_local.to_quaternion().to_matrix().to_4x4();bpy.context.view_layer.update()
def curl(side,amount):
    # Rotate each phalanx toward its palm normal, in its local frame.
    for finger in ['index','middle','ring','pinky','thumb']:
        for j in range(1,4):
            name=finger+'_%02d'%j+'.'+side;pb=rig.pose.bones[name]
            rest=pb.bone.matrix_local.to_quaternion();along=rest@Vector((0,1,0))
            axis=along.cross(Vector((0,-1,0))).normalized();local=rest.inverted()@axis
            pb.rotation_quaternion=Quaternion(local,math.radians(amount*(.62 if finger=='thumb' else 1)*(1 if j<3 else .8)))
    bpy.context.view_layer.update()

def pose_walk(phase):
    reset_pose()
    bob=.003*(1-math.cos(phase*4*pi))
    pelvis_drop=-.073+bob
    pelvis=rig.pose.bones['pelvis']
    pelvis.location=rig.data.bones['pelvis'].matrix_local.to_quaternion().inverted()@Vector((0,.012,pelvis_drop))
    bpy.context.view_layer.update()
    turn('spine_01',(1,0,0),6)
    turn('spine_02',(1,0,0),2)
    turn('chest',(0,0,1),1.5*math.sin(phase*2*pi))
    for side,sg in [('L',1),('R',-1)]:
        t=(phase+(0 if side=='L' else .5))%1
        # Half-cycle planted travel; smooth toe lift through the return swing.
        if t<.5:
            y=-.105+.42*t;z=.13
        else:
            u=(t-.5)*2;y=.105-.21*(u*u*(3-2*u));z=.13+.038*math.sin(pi*u)**2
        foot(side,(sg*.126,y,z))
        swing=.030*math.sin(phase*2*pi+(pi if side=='L' else 0))
        wrist(side,(sg*.282,-.094+swing,.768+bob),pole=(0,1,0),direction=(0,-.15,-1))
        curl(side,18)
    rig.pose.bones['root'].matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()

old=bpy.data.actions.get('walk')
if old:old.name='HISTORY9_walk';old.use_fake_user=True
action=bpy.data.actions.new('walk');action.use_fake_user=True;rig.animation_data.action=action
for f in range(1,38):
    pose_walk((f-1)/36)
    for pb in rig.pose.bones:
        pb.keyframe_insert('location',frame=f,group=pb.name)
        pb.keyframe_insert('rotation_quaternion',frame=f,group=pb.name)
        pb.keyframe_insert('scale',frame=f,group=pb.name)
action['loop']=True;action['fps']=30;action['duration_seconds']=1.2
for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for fc in bag.fcurves:
                for k in fc.keyframe_points:k.interpolation='LINEAR'
track=rig.animation_data.nla_tracks.get('walk')
for strip in track.strips:strip.action=action;strip.action_slot=action.slots[0]
rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0];scene.frame_set(1)
print('WALK10: 7.3cm lower pelvis, 6mm bob, bent knees, short cautious strides; idle unchanged')
