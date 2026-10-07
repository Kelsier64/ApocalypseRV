"""Blender MCP review renders. The studio is excluded by selected-only GLB export."""
import bpy
from mathutils import Vector
ROOT = 'C:/Users/evan4/Projects/ApocalypseRV/'
scene = bpy.data.scenes['BARREL_MAN_AUTHORING']
bpy.context.window.scene = scene
rig = bpy.data.objects['BarrelManRig']
if not bpy.data.objects.get('BarrelReviewCamera'):
    camera = bpy.data.objects.new('BarrelReviewCamera', bpy.data.cameras.new('BarrelReviewCamera'))
    scene.collection.objects.link(camera)
    for name, position, energy, size in [('BarrelReviewKey',(2,-4,5),700,4),('BarrelReviewFill',(-3,-2,2),350,3),('BarrelReviewRim',(1,3,4),650,3)]:
        data = bpy.data.lights.new(name,'AREA')
        data.energy = energy
        data.shape = 'DISK'
        data.size = size
        light = bpy.data.objects.new(name,data)
        scene.collection.objects.link(light)
        light.location = position
        light.rotation_euler = (Vector((0,0,1))-light.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.mesh.primitive_plane_add(size=200)
    floor = bpy.context.object
    floor.name = 'BarrelReviewFloor'
    floor.location.z = -.002
    material = bpy.data.materials.new('BarrelReviewFloor')
    material.diffuse_color = (.065,.08,.09,1)
    floor.data.materials.append(material)
scene.camera = bpy.data.objects['BarrelReviewCamera']
camera = scene.camera
camera.data.type = 'ORTHO'
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 1200
scene.render.resolution_y = 1200
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
for name,clip,frame,position,target,scale in [
    ('standing','idle',1,(3,-5,2.7),(0,0,.95),2.25),
    ('feet','idle',1,(1,-2,.65),(0,-.07,.28),.85),
    ('disguised','disguised',1,(3,-5,2.7),(0,0,.65),1.65),
    ('rising','rise',26,(3,-5,2.7),(0,0,.75),2.0),
    ('sprint','sprint',7,(3,-5,2.7),(0,0,.90),2.25)]:
    rig.animation_data.action = bpy.data.actions[clip]
    scene.frame_set(frame)
    camera.location = position
    camera.rotation_euler = (Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale = scale
    scene.render.filepath = ROOT+'docs/validation/barrel-man/blender-'+name+'.png'
    bpy.ops.render.render(write_still=True)
rig.animation_data.action = bpy.data.actions['idle']
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'art_source/barrel_man/barrel_man.blend',copy=True)
