"""Export v013 with unchanged v011 packed 2K textures and all 23 clips."""
import bpy
from mathutils import Vector
OUT='C:/Users/evan4/Projects/ApocalypseRV/art_source/monster_refined_v013/'
scene=bpy.data.scenes['MONSTER_REFINED_V013']
bpy.context.window.scene=scene
rig=bpy.data.objects['Refined013_Rig']
mesh=bpy.data.objects['Refined013_Mesh']
rig.data.pose_position='POSE'
scene.render.engine='BLENDER_EEVEE'
rig.animation_data.action=None
for track in rig.animation_data.nla_tracks: track.mute=False
for ob in scene.objects: ob.select_set(False)
rig.select_set(True)
mesh.select_set(True)
bpy.context.view_layer.objects.active=rig
# Stable runtime node names, restored in the editable scene after export.
source_mesh=bpy.data.objects['Raker_Mesh']
source_rig=bpy.data.objects['Raker_Rig']
source_mesh.name='V008_Raker_Mesh'
source_rig.name='V008_Raker_Rig'
mesh.name='Raker_Mesh'
rig.name='Raker_Rig'
try:
    bpy.ops.export_scene.gltf(filepath=OUT+'raker_refined_v013.glb',use_selection=True,use_active_scene=True,
        export_animations=True,export_animation_mode='NLA_TRACKS',export_def_bones=True,
        export_force_sampling=True,export_skins=True,export_yup=True,export_vertex_color='NONE')
finally:
    mesh.name='Refined013_Mesh'
    rig.name='Refined013_Rig'
    source_mesh.name='Raker_Mesh'
    source_rig.name='Raker_Rig'
    for track in rig.animation_data.nla_tracks: track.mute=True
    rig.animation_data.action=bpy.data.actions['raker_idle']
    rig.animation_data.action_slot=rig.animation_data.action.slots[0]
    scene.frame_set(0)

scene.camera.location=(3,-6,2.2)
scene.camera.rotation_euler=(Vector((0,-.15,1.05))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
scene.camera.data.ortho_scale=2.6
bpy.ops.wm.save_as_mainfile(filepath=OUT+'monster_refined_v013.blend')
print('FINISHED',OUT)

