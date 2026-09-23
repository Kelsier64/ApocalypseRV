"""Repair finger bind geometry and retarget every clip; preserve v019 thumbs."""
import bpy,math,json
from mathutils import Vector,Matrix,Quaternion
from pathlib import Path
OUT=Path(__file__).resolve().parent
src_scene=bpy.data.scenes['MONSTER_REFINED_V019']
src=bpy.data.objects['Refined019_Rig'];src_mesh=bpy.data.objects['Refined019_Mesh']
scene=bpy.data.scenes.new('MONSTER_REFINED_V020');scene.world=src_scene.world.copy();scene.render.fps=60
bpy.context.window.scene=scene
rig=src.copy();rig.data=src.data.copy();rig.name='Refined020_Rig';scene.collection.objects.link(rig)
mesh=src_mesh.copy();mesh.data=src_mesh.data.copy();mesh.name='Refined020_Mesh';mesh.parent=rig;scene.collection.objects.link(mesh)
for mod in mesh.modifiers:
    if mod.type=='ARMATURE':mod.object=rig
assert all(mod.type=='ARMATURE' for mod in mesh.modifiers),'Rest deformation requires unchanged topology'
for ob in src_scene.objects:
    if ob.name.startswith('Review019_'):
        copy=ob.copy();copy.data=ob.data.copy();copy.name=ob.name.replace('019','020');scene.collection.objects.link(copy)
        if copy.type=='CAMERA':scene.camera=copy
for track in rig.animation_data.nla_tracks:
    track.mute=True
    action=track.strips[0].action.copy();action.name='raker_v020_'+track.name
    track.strips[0].action=action;track.strips[0].action_slot=action.slots[0]
rig.animation_data.action=None;rig.data.pose_position='POSE'
for bone in rig.pose.bones:bone.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
FINGERS=['index','middle','ring','pinky']

def anatomy(matrices,side):
    def at(name):return matrices[name+'_'+side].translation
    forward=(at('middle_01')-at('hand')).normalized()
    thumb=at('thumb_01')-at('middle_01');thumb=(thumb-forward*thumb.dot(forward)).normalized()
    return forward,forward.cross(thumb)*(1 if side=='L' else -1)

def fixed_fingers(matrices,lengths):
    """Set flexion in the anatomical palm plane, never a global Euler axis."""
    for side in ['L','R']:
        forward,palm=anatomy(matrices,side)
        for finger in FINGERS:
            n1=finger+'_01_'+side;n2=finger+'_02_'+side
            old1,old2=matrices[n1],matrices[n2]
            proximal=old1.to_3x3().col[1].normalized()
            distal=old2.to_3x3().col[1].normalized()
            mcp=math.atan2(proximal.dot(palm),proximal.dot(forward))
            pip_normal=(palm-proximal*palm.dot(proximal)).normalized()
            pip=math.atan2(distal.dot(pip_normal),distal.dot(proximal))
            mcp=max(math.radians(3),min(math.radians(55),abs(mcp)))
            pip=max(math.radians(12),min(math.radians(70),abs(pip)))
            flat=(proximal-palm*proximal.dot(palm)).normalized()
            new_proximal=(flat*math.cos(mcp)+palm*math.sin(mcp)).normalized()
            q1=proximal.rotation_difference(new_proximal)
            rig.pose.bones[n1].matrix=Matrix.Translation(old1.translation)@(q1.to_matrix()@old1.to_3x3()).to_4x4()
            bpy.context.view_layer.update()
            normal=(palm-new_proximal*palm.dot(new_proximal)).normalized()
            new_distal=(new_proximal*math.cos(pip)+normal*math.sin(pip)).normalized()
            q2=distal.rotation_difference(new_distal)
            joint=old1.translation+new_proximal*lengths[n1]
            rig.pose.bones[n2].matrix=Matrix.Translation(joint)@(q2.to_matrix()@old2.to_3x3()).to_4x4()
            bpy.context.view_layer.update()

# Rest mesh and rest bones must change together; rotating only animated joints
# would leave the backward hinge visible in Blender REST/edit mode.
rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
lengths={b.name:b.length for b in rig.data.bones}
fixed_fingers(rest,lengths)
corrected={b.name:b.matrix.copy() for b in rig.pose.bones if any(b.name.startswith(f+'_') for f in FINGERS)}
obj=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());evaluated=obj.to_mesh()
assert len(evaluated.vertices)==len(mesh.data.vertices)
vertices=[v.co.copy() for v in evaluated.vertices];obj.to_mesh_clear()
for vertex,point in zip(mesh.data.vertices,vertices):vertex.co=point
mesh.data.update()
for ob in scene.objects:ob.select_set(False)
rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='EDIT')
for name,transform in corrected.items():
    bone=rig.data.edit_bones[name];bone.matrix=transform;bone.length=lengths[name]
bpy.ops.object.mode_set(mode='OBJECT')
for bone in rig.pose.bones:bone.matrix_basis=Matrix.Identity(4)

# Evaluate the untouched source separately. Sample first, then write to private
# actions so source interpolation/previous keys cannot contaminate retargeting.
for t in src.animation_data.nla_tracks:t.mute=True
src.data.pose_position='POSE'
for track in rig.animation_data.nla_tracks:
    old=next(t.strips[0].action for t in src.animation_data.nla_tracks if t.name==track.name)
    bpy.context.window.scene=src_scene;src.animation_data.action=old;src.animation_data.action_slot=old.slots[0]
    frames=[]
    for f in range(int(old.frame_range[1])+1):
        src_scene.frame_set(f);bpy.context.view_layer.update()
        frames.append({b.name:b.matrix.copy() for b in src.pose.bones})
    bpy.context.window.scene=scene
    action=track.strips[0].action;rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
    for f,matrices in enumerate(frames):
        scene.frame_set(f);bpy.context.view_layer.update()
        fixed_fingers(matrices,lengths)
        for name in corrected:
            bone=rig.pose.bones[name];bone.rotation_quaternion.normalize()
            bone.keyframe_insert(data_path='rotation_quaternion',frame=f)
            # Translation is the new bind offset, not an animated stretch.
            bone.location=Vector();bone.keyframe_insert(data_path='location',frame=f)
    print('RETARGETED',track.name,flush=True)
rig.animation_data.action=next(t.strips[0].action for t in rig.animation_data.nla_tracks if t.name=='idle')
rig.animation_data.action_slot=rig.animation_data.action.slots[0];scene.frame_set(0)
scene['revision']='v020 palmar finger flexion in bind geometry and every action; v019 thumbs unchanged'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'monster_refined_v020.blend'))
print('SAVED',OUT,flush=True)
