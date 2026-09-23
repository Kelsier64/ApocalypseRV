"""Blender source previews; gold marks thumb skin only in diagnostic renders."""
import bpy
from mathutils import Vector
from pathlib import Path
OUT=Path(__file__).resolve().parent
for version in ['018','019']:
    s=bpy.data.scenes['MONSTER_REFINED_V'+version];bpy.context.window.scene=s
    r=bpy.data.objects['Refined'+version+'_Rig'];m=bpy.data.objects['Refined'+version+'_Mesh']
    r.data.pose_position='POSE'
    for t in r.animation_data.nla_tracks:t.mute=True
    s.render.engine='BLENDER_EEVEE';s.render.resolution_x=1000;s.render.resolution_y=850;s.render.resolution_percentage=100
    s.render.image_settings.file_format='PNG'
    cam=s.camera;cam.data.type='ORTHO'
    for clip in ['idle','walk','grab_stand_hold']:
        action=next(t.strips[0].action for t in r.animation_data.nla_tracks if t.name==clip)
        r.animation_data.action=action;r.animation_data.action_slot=action.slots[0];s.frame_set(0 if clip!='walk' else 18);bpy.context.view_layer.update()
        for view in ['front','side']:
            focus=Vector((0,-.1,1.05))
            cam.location=focus+Vector((0,-5,.15) if view=='front' else (5,0,.1))
            cam.rotation_euler=(focus-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=2.55
            s.render.filepath=str(OUT/(version+'_'+clip+'_'+view+'.png'));bpy.ops.render.render(write_still=True)
    # Anatomical landmark close-up, independent of inferred bone-roll normals.
    mat=bpy.data.materials.new('ReviewThumbGold'+version);mat.diffuse_color=(.9,.42,.045,1);mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=mat.diffuse_color
    m.data.materials.append(mat);index=len(m.data.materials)-1
    groups={g.index for g in m.vertex_groups if g.name.startswith('thumb_')}
    for face in m.data.polygons:
        if sum(sum(g.weight for g in m.data.vertices[i].groups if g.group in groups) for i in face.vertices)/len(face.vertices)>.45:face.material_index=index
    action=next(t.strips[0].action for t in r.animation_data.nla_tracks if t.name=='idle')
    r.animation_data.action=action;r.animation_data.action_slot=action.slots[0];s.frame_set(0);bpy.context.view_layer.update()
    focus=r.pose.bones['hand_L'].matrix.translation+Vector((0,0,-.11))
    cam.location=focus+Vector((3,-.1,.06));cam.rotation_euler=(focus-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=.65
    s.render.filepath=str(OUT/(version+'_thumb_side.png'));bpy.ops.render.render(write_still=True)
