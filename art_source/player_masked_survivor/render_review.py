import bpy,json,math
from mathutils import Vector,Matrix
OUT='C:/Users/evan4/Projects/ApocalypseRV/art_source/player_masked_survivor/review/'
JOBS = []
main=bpy.data.scenes['PLAYER_MASKED_SURVIVOR']
verified=main
if verified.camera is None:
    for ob in main.objects:
        if ob.type in ['CAMERA','LIGHT']:
            copy=ob.copy();copy.data=ob.data.copy();verified.collection.objects.link(copy)
            if copy.type=='CAMERA':verified.camera=copy
    verified.world=main.world
for job in JOBS:
    name=job['name'];qa=job.get('action','').startswith('QA_');scene=main if qa or job.get('cut') or name=='physical_bones' else verified
    bpy.context.window.scene=scene;rig=next(o for o in scene.objects if o.type=='ARMATURE');rig.animation_data.action=None
    for t in rig.animation_data.nla_tracks:t.mute=True
    for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
    if job.get('action'):
        action=bpy.data.actions[job['action']+('' if scene==main else '.001')];rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
    scene.frame_set(job.get('frame',1));bpy.context.view_layer.update()
    saved=[(o,o.hide_render,o.location.copy()) for o in scene.objects]
    for o in scene.objects:o.hide_render=bool(o.get('exclude_from_export',False))
    if job.get('cut'):
        rows=json.loads(bpy.data.objects['Survivor_Rig']['cut_map']);cut=next(c for c in rows if c['cut']==job['cut']);names={cut['limb']}
        if 'upper_arm' in cut['limb']:names.add(cut['limb'].replace('upper_arm','forearm'))
        if 'thigh' in cut['limb']:names.add(cut['limb'].replace('thigh','shin'))
        if cut['limb']=='body_head':names.add('mask_default')
        for row in rows:
            if row['body'] in names:names.add(row['caps'][0])
            if row['limb'] in names:names.add(row['caps'][1])
        for n in names:
            ob=bpy.data.objects[n]
            if job.get('missing'):ob.hide_render=True
            else:ob.location+=Vector((.43 if '.L' in job['cut'] else -.43,0,0)) if job['cut']!='neck' else Vector((0,0,.27))
    material=next(m for o in scene.objects if o.type=='MESH' for m in o.data.materials if m and m.name.startswith('suit_dye'))
    mix=next(n for n in material.node_tree.nodes if n.type=='MIX');tint=tuple(mix.inputs[7].default_value)
    if job.get('tint'):mix.inputs[7].default_value=job['tint']
    cam=scene.camera;target=Vector(job.get('target',(0,0,.90)));cam.location=Vector(job.get('camera',(2.6,-5,2.2)))
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=job.get('scale',2.1)
    scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
    temporary=[]
    if name=='physical_bones':
        for o in scene.objects:
            if o.type=='MESH':o.hide_render=True
        mat=bpy.data.materials.new('REVIEW_bone_orange');mat.use_nodes=True;p=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(.8,.22,.04,1)
        for bn in json.loads(rig['physical_bones']):
            b=rig.data.bones[bn];h=b.head_local;t=b.tail_local;d=(t-h).normalized();u=d.cross(Vector((0,1,0))).normalized();v=d.cross(u);c=h.lerp(t,.2);r=.022
            pts=[h,c+u*r,c+v*r,c-u*r,c-v*r,t];faces=[(0,1,2),(0,2,3),(0,3,4),(0,4,1),(5,2,1),(5,3,2),(5,4,3),(5,1,4)]
            me=bpy.data.meshes.new('REVIEW_'+bn);me.from_pydata(pts,[],faces);ob=bpy.data.objects.new('REVIEW_'+bn,me);scene.collection.objects.link(ob);me.materials.append(mat);temporary.append(ob)
    scene.render.filepath=OUT+name+'.png';bpy.ops.render.render(write_still=True)
    for ob in temporary:bpy.data.objects.remove(ob,do_unlink=True)
    for ob,hidden,location in saved:ob.hide_render=hidden;ob.location=location
    mix.inputs[7].default_value=tint
    print('PREVIEW',name,'source',scene.name)
bpy.context.window.scene=main
