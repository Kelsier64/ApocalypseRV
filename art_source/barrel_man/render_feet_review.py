"""Blender MCP close-up review of the second anatomical foot pass."""
import bpy
import bmesh
from mathutils import Vector

ROOT='C:/Users/evan4/Projects/ApocalypseRV/'
scene=bpy.data.scenes['BARREL_MAN_AUTHORING']
bpy.context.window.scene=scene
rig=bpy.data.objects['BarrelManRig']
camera=bpy.data.objects['BarrelReviewCamera']
scene.camera=camera
camera.data.type='ORTHO'
scene.render.engine='BLENDER_EEVEE'
scene.render.resolution_x=1500
scene.render.resolution_y=1100
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
for name,clip,frame,position,target,scale in [
    ('front','idle',1,(.6,-1.5,.73),(0,-.06,.16),.62),
    ('back','idle',1,(-.9,.9,.47),(0,0,.17),.63),
    ('medial-arch','idle',1,(-1.5,-.05,.29),(.145,-.06,.115),.44),
    ('toes','idle',1,(.18,-1,.86),(.145,-.17,.04),.32),
    ('push-off','run',9,(1,-2,.65),(0,0,.22),.82),
    ('sprint','sprint',7,(3,-5,2.7),(0,0,.90),3.0),
    ('rising','rise',26,(3,-5,2.7),(0,0,.75),2.75),
    ('disguised','disguised',1,(3,-5,2.7),(0,0,.55),2.0)]:
    rig.animation_data.action=bpy.data.actions[clip]
    scene.frame_set(frame)
    camera.location=position
    camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=scale
    for ob in rig.children:
        if ob.name=='Leg_R' or (ob.name.startswith('Nail_') and ob.name.endswith('_R')):
            ob.hide_render=name=='medial-arch'
    scene.render.filepath=ROOT+'docs/validation/barrel-man-feet/blender-'+name+'.png'
    bpy.ops.render.render(write_still=True)
for ob in rig.children: ob.hide_render=False
for suffix in ['R','L']:
    ob=bpy.data.objects['Leg_'+suffix]
    bm=bmesh.new()
    bm.from_mesh(ob.data)
    print('FOOT_TOPOLOGY',suffix,'boundary',sum(e.is_boundary for e in bm.edges),
        'nonmanifold',sum(not e.is_manifold for e in bm.edges),
        'loose',sum(not v.link_faces for v in bm.verts))
    bm.free()
rig.animation_data.action=bpy.data.actions['idle']
scene.frame_set(1)
camera.location=(.6,-1.5,.73)
camera.rotation_euler=(Vector((0,-.06,.16))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.ortho_scale=.62
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'art_source/barrel_man/barrel_man.blend',copy=True)
