"""Blender MCP authoring pass, after build_model.py. In-place, 60 Hz baked Actions."""
import bpy
import math
from mathutils import Vector, Matrix

ROOT='C:/Users/evan4/Projects/ApocalypseRV/'
scene=bpy.data.scenes['BARREL_MAN_AUTHORING']
bpy.context.window.scene=scene
rig=bpy.data.objects['BarrelManRig']
barrel=bpy.data.objects['Barrel_Reference']
rig.animation_data_create()
for track in list(rig.animation_data.nla_tracks): rig.animation_data.nla_tracks.remove(track)
rig.animation_data.action=None
for name in ['disguised','rise','idle','run','sprint','turn_left','turn_right','retract','fall','land']:
    old=bpy.data.actions.get(name)
    if old: bpy.data.actions.remove(old)
def smooth(t):
    t=max(0,min(1,t))
    return t*t*(3-2*t)
def set_bone(name,head,tail=None,tilt=0):
    pb=rig.pose.bones[name]
    rest=pb.bone.matrix_local.copy()
    if tail is not None:
        direction=Vector(tail)-Vector(head)
        original=pb.bone.tail_local-pb.bone.head_local
        rotation=original.rotation_difference(direction)
        matrix=rotation.to_matrix().to_4x4() @ rest
    else:
        matrix=Matrix.Rotation(tilt,4,'X') @ rest
    matrix.translation=Vector(head)
    pb.matrix=matrix
    bpy.context.view_layer.update()
def limb(suffix,hip,ankle,pitch=0,toe_pitch=0):
    hip=Vector(hip)
    ankle=Vector(ankle)
    a=rig.data.bones['thigh_'+suffix].length
    b=rig.data.bones['shin_'+suffix].length
    delta=ankle-hip
    distance=max(abs(a-b)+.001,min(a+b-.001,delta.length))
    direction=delta.normalized()
    ankle=hip+direction*distance
    along=(a*a-b*b+distance*distance)/(2*distance)
    lift=math.sqrt(max(0,a*a-along*along))
    pole=Vector((0,direction.z,-direction.y)).normalized()
    knee=hip+direction*along+pole*lift
    foot_rest=rig.data.bones['foot_'+suffix]
    ball=ankle+Matrix.Rotation(pitch,3,'X')@(foot_rest.tail_local-foot_rest.head_local)
    toe_rest=rig.data.bones['toes_'+suffix]
    tip=ball+Matrix.Rotation(toe_pitch,3,'X')@(toe_rest.tail_local-toe_rest.head_local)
    set_bone('thigh_'+suffix,hip,knee)
    set_bone('shin_'+suffix,knee,ankle)
    set_bone('foot_'+suffix,ankle,ball)
    set_bone('toes_'+suffix,ball,tip)

def pose(clip,t,duration):
    progress=t/duration
    hipz=.94
    hipy=.02
    barrelz=1.4
    barreltilt=0
    feet={s:[Vector((x,.008,.115)),0,0] for x,s in [(-.145,'R'),(.145,'L')]}
    if clip in ['disguised','rise','retract']:
        p=0 if clip=='disguised' else smooth(progress if clip=='rise' else 1-progress)
        hipz=.16+(.94-.16)*p
        hipy=.11+.12*math.sin(math.pi*p)-.09*p
        barrelz=.5+.9*p
        for data in feet.values():
            data[0].x*=.09/.145+(1-.09/.145)*p
            data[0].y=.03-.022*p-.22*math.sin(math.pi*max(0,min(1,(p-.09)/.41)))
            data[0].z=.145+(.115-.145)*smooth(min(1,p*5))
    elif clip=='idle':
        hipz+=.002*math.sin(math.tau*progress)
        barrelz+=.003*math.sin(math.tau*progress)
    elif clip in ['run','sprint','turn_left','turn_right']:
        fast=clip=='sprint'
        speed=10 if fast else 6
        duty=.18 if fast else .25
        amplitude=speed*duration*duty*.5
        hipz=.865+.012*math.sin(math.tau*progress*2)
        hipy=-.015
        barrelz=hipz+.49
        barreltilt=.06 if fast else .045
        for index,suffix in enumerate(['R','L']):
            p=(progress+index*.5)%1
            ankle=feet[suffix][0]
            if p<duty:
                q=p/duty
                ankle.y=-amplitude+2*amplitude*q
                pitch=-.14*(1-smooth(q*4))+.43*smooth((q-.70)/.30)
                ankle.z=.115+max(0,math.sin(pitch))*.19
                feet[suffix][1]=pitch
            else:
                q=(p-duty)/(1-duty)
                ankle.y=amplitude*math.cos(math.pi*q)
                ankle.z=.115+.25*math.sin(math.pi*q)**.8+.075*(1-smooth(q*5))
                feet[suffix][1]=.43*(1-q)-.14*q+.24*math.sin(math.pi*q)
                feet[suffix][2]=feet[suffix][1]*.5
            if clip.startswith('turn_'):
                sign=1 if clip=='turn_left' else -1
                ankle.x+=sign*.028*math.sin(math.tau*p)
    elif clip=='fall':
        hipz=.85
        barrelz=1.31
        barreltilt=.10
        for i,data in enumerate(feet.values()):
            data[0].y=.10 if i==0 else -.08
            data[0].z=.28 if i==0 else .20
            data[1]=.25
    elif clip=='land':
        compression=math.sin(math.pi*min(1,progress*1.6)) if progress<.625 else 0
        hipz=.94-.17*compression
        barrelz=1.4-.17*compression
        hipy=.02+.05*compression
        barreltilt=.10*compression
    set_bone('root',(0,0,0))
    set_bone('pelvis',(0,hipy,hipz))
    set_bone('barrel',(0,0,barrelz),tilt=barreltilt)
    for x,suffix in [(-.145,'R'),(.145,'L')]:
        data=feet[suffix]
        tucked=clip in ['disguised','rise','retract']
        hx=data[0].x if tucked else x
        limb(suffix,(hx,hipy,hipz),data[0],data[1],data[2])

clips=[('disguised',60),('rise',48),('idle',120),('run',34),('sprint',28),('turn_left',34),('turn_right',34),('retract',48),('fall',60),('land',24)]
for clip,frames in clips:
    action=bpy.data.actions.new(clip)
    rig.animation_data.action=action
    for frame in range(frames+1):
        scene.frame_set(frame+1)
        pose(clip,frame/60,frames/60)
        for pb in rig.pose.bones:
            pb.keyframe_insert(data_path='location',frame=frame+1,group=pb.name)
            pb.keyframe_insert(data_path='rotation_quaternion',frame=frame+1,group=pb.name)
            pb.keyframe_insert(data_path='scale',frame=frame+1,group=pb.name)
    action.use_fake_user=True
    rig.animation_data.action=None
    track=rig.animation_data.nla_tracks.new()
    track.name=clip
    strip=track.strips.new(clip,1,action)
    track.mute=True
    print('Baked',clip,frames/60)
rig.animation_data.action=bpy.data.actions['idle']
scene.frame_start=1
scene.frame_end=121
scene.frame_set(1)
bpy.ops.object.select_all(action='DESELECT')
for ob in scene.objects:
    if ob==rig or (ob.parent==rig and ob!=barrel): ob.select_set(True)
bpy.context.view_layer.objects.active=rig
# Query exporter RNA instead of relying on version-specific enum guesses.
props=bpy.ops.export_scene.gltf.get_rna_type().properties
options={'filepath':ROOT+'assets/models/barrel_man/barrel_man.glb','export_format':'GLB','use_selection':True,'use_active_scene':True,'export_yup':True,'export_animations':True}
if 'export_animation_mode' in props:
    modes=[item.identifier for item in props['export_animation_mode'].enum_items]
    options['export_animation_mode']='ACTIONS' if 'ACTIONS' in modes else modes[0]
if 'export_force_sampling' in props: options['export_force_sampling']=True
if 'export_anim_single_armature' in props: options['export_anim_single_armature']=True
if 'export_optimize_animation_size' in props: options['export_optimize_animation_size']=False
if 'export_all_influences' in props: options['export_all_influences']=False
if 'export_anim_slide_to_zero' in props: options['export_anim_slide_to_zero']=True
bpy.ops.export_scene.gltf(**options)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'art_source/barrel_man/barrel_man.blend',copy=True)
print('Exported legs/rig/10 clips; original barrel remains a reference only in Blender.')
