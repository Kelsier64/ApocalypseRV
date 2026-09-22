"""Clone v015; articulated jaw and three sets of fixed-root grab animations."""
import bpy
import math
from mathutils import Vector, Matrix, Quaternion
source = bpy.data.scenes['MONSTER_REFINED_V015']
scene = bpy.data.scenes.new('MONSTER_REFINED_V016')
scene.render.fps = 60  # exact .35/.45/.65 second authored endpoints
bpy.context.window.scene = scene
rig = bpy.data.objects['Refined015_Rig'].copy()
rig.data = rig.data.copy()
rig.name = 'Refined016_Rig'
scene.collection.objects.link(rig)
mesh = bpy.data.objects['Refined015_Mesh'].copy()
mesh.data = mesh.data.copy()
mesh.name = 'Refined016_Mesh'
mesh.parent = rig
scene.collection.objects.link(mesh)
for mod in mesh.modifiers:
    if mod.type == 'ARMATURE': mod.object = rig
for ob in source.objects:
    if ob.name.startswith('Review015_'):
        copy = ob.copy()
        copy.data = ob.data.copy()
        copy.name = ob.name.replace('015', '016')
        scene.collection.objects.link(copy)
        if copy.type == 'CAMERA': scene.camera = copy
scene.world = source.world.copy()
for track in rig.animation_data.nla_tracks: track.mute = True
rig.animation_data.action = None
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
jaw = rig.data.edit_bones.new('jaw')
jaw.head = (0, -.045, 2.023)
jaw.tail = (0, -.155, 1.989)
jaw.parent = rig.data.edit_bones['head']
jaw.use_deform = True
bpy.ops.object.mode_set(mode='OBJECT')
rig.pose.bones['jaw'].rotation_mode = 'QUATERNION'
jaw_group = mesh.vertex_groups.new(name='jaw')
head_group = mesh.vertex_groups['head']
# The existing recessed, UV-dark mouth bowl becomes an articulated oral cavity.
# Lower lip/chin follow the jaw; upper lip/skull stay fixed and cheeks feather.
for vertex in mesh.data.vertices:
    x,y,z = vertex.co
    if 1.956 < z < 2.02 and y < -.065:
        edge = max(0, min(1, (.083-abs(x))/.022))
        lower = max(0, min(1, (2.017-z)/.012))
        front = max(0, min(1, (-y-.065)/.060))
        weight = edge * lower * front
        old = 0
        for group in vertex.groups:
            if group.group == head_group.index: old = group.weight
        if old > 0 and weight > 0:
            jaw_group.add([vertex.index], old*weight, 'REPLACE')
            head_group.add([vertex.index], old*(1-weight), 'REPLACE')
# Copy every old action so jaw keys cannot modify historical source actions.
# Original actions were 30 fps: scale their frame coordinates to 60 fps.
for track in rig.animation_data.nla_tracks:
    strip = track.strips[0]
    action = strip.action.copy()
    action.name = 'raker_v016_' + track.name
    strip.action = action
    strip.action_slot = action.slots[0]
    for layer in action.layers:
        for action_strip in layer.strips:
            for bag in action_strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.co.x *= 2
                        key.handle_left.x *= 2
                        key.handle_right.x *= 2
    strip.action_frame_end = action.frame_range[1]
    strip.frame_end = action.frame_range[1]
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    rig.pose.bones['jaw'].rotation_quaternion = Quaternion()
    for frame in [0, action.frame_range[1]]:
        rig.pose.bones['jaw'].keyframe_insert(data_path='rotation_quaternion', frame=frame)

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
