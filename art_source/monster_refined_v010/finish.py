"""Bake portable skin color, export 22 clips, and render actual model views."""
import bpy
import json
from mathutils import Vector
OUT='C:/Users/evan4/Projects/ApocalypseRV/art_source/monster_refined_v010/'
scene=bpy.data.scenes['MONSTER_REFINED_V010']
bpy.context.window.scene=scene
rig=bpy.data.objects['Refined010_Rig']
mesh=bpy.data.objects['Refined010_Mesh']
skin=mesh.data.materials[0]
tex=next(n for n in skin.node_tree.nodes if n.type=='TEX_NOISE')
coord=skin.node_tree.nodes.new('ShaderNodeTexCoord')
skin.node_tree.links.new(coord.outputs['Object'],tex.inputs['Vector'])
tex.inputs['Scale'].default_value=23
image=bpy.data.images.new('Raker010_Albedo',width=1024,height=1024,alpha=False)
for mat in mesh.data.materials:
    node=mat.node_tree.nodes.new('ShaderNodeTexImage')
    node.image=image
    mat.node_tree.nodes.active=node
for ob in scene.objects: ob.select_set(False)
mesh.select_set(True)
bpy.context.view_layer.objects.active=mesh
rig.data.pose_position='REST'
try: scene.render.engine='CYCLES'
except TypeError: raise RuntimeError('Cycles required to bake portable albedo')
scene.cycles.samples=16
scene.render.bake.margin=8
scene.render.bake.use_clear=True
bpy.ops.object.bake(type='DIFFUSE',pass_filter={'COLOR'},use_selected_to_active=False)
image.filepath_raw=OUT+'raker_albedo_1k.png'
image.file_format='PNG'
image.save()
image.pack()
for i,mat in enumerate(list(mesh.data.materials)):
    mat.use_fake_user=True
    baked=mat.copy()
    baked.name='Raker010_BakedSkin' if i==0 else 'Raker010_BakedEyes'
    bsdf=next(n for n in baked.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    output=next(n for n in baked.node_tree.nodes if n.type=='OUTPUT_MATERIAL')
    for node in list(baked.node_tree.nodes):
        if node not in [bsdf,output]: baked.node_tree.nodes.remove(node)
    node=baked.node_tree.nodes.new('ShaderNodeTexImage')
    node.image=image
    baked.node_tree.links.new(node.outputs['Color'],bsdf.inputs['Base Color'])
    mesh.data.materials[i]=baked
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
    bpy.ops.export_scene.gltf(filepath=OUT+'raker_refined_v010.glb',use_selection=True,use_active_scene=True,
        export_animations=True,export_animation_mode='NLA_TRACKS',export_def_bones=True,
        export_force_sampling=True,export_skins=True,export_yup=True,export_vertex_color='NONE')
finally:
    mesh.name='Refined010_Mesh'
    rig.name='Refined010_Rig'
    source_mesh.name='Raker_Mesh'
    source_rig.name='Raker_Rig'
    for track in rig.animation_data.nla_tracks: track.mute=True
    rig.animation_data.action=bpy.data.actions['raker_idle']
    rig.animation_data.action_slot=rig.animation_data.action.slots[0]
    scene.frame_set(0)
views=[('front',(0,-6,1.15),'raker_idle',0,2.6,(0,0,1.09)),
       ('side',(6,0,1.15),'raker_idle',0,2.6,(0,0,1.09)),
       ('back',(0,6,2.7),'raker_idle',0,2.6,(0,0,1.09)),
       ('crouch',(3,-6,2.0),'raker_crouch_idle',0,2.75,(0,-.1,.76)),
       ('head',(2,-5,2.50),'raker_idle',0,.63,(0,-.02,1.96)),
       ('threequarter',(3,-6,2.65),'raker_idle',0,2.65,(0,0,1.10))]
for label,location,action,frame,scale,target in views:
    rig.animation_data.action=bpy.data.actions[action]
    rig.animation_data.action_slot=rig.animation_data.action.slots[0]
    scene.frame_set(frame)
    scene.camera.location=location
    scene.camera.rotation_euler=(Vector(target)-scene.camera.location).to_track_quat('-Z','Y').to_euler()
    scene.camera.data.ortho_scale=scale
    scene.render.filepath=OUT+label+'.png'
    bpy.ops.render.render(write_still=True)
for ob in scene.objects: ob.select_set(False)
mesh.select_set(True)
bpy.context.view_layer.objects.active=mesh
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_location=Vector((0,0,1.10))
            area.spaces.active.region_3d.view_distance=3.5
            area.spaces.active.region_3d.view_rotation=scene.camera.rotation_euler.to_quaternion()
bpy.ops.wm.save_as_mainfile(filepath=OUT+'monster_refined_v010.blend')
print('FINISHED',OUT)
