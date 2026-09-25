"""Blender-only connected normal reference; never included in game exports."""
import bpy
from mathutils import Matrix
s=bpy.data.scenes['PLAYER_MASKED_SURVIVOR'];bpy.context.window.scene=s;r=bpy.data.objects['Survivor_Rig'];r.animation_data.action=None
for tr in r.animation_data.nla_tracks:tr.mute=True
for b in r.pose.bones:b.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
objects=[bpy.data.objects[n] for n in ['body_torso','body_upper_arm.L','body_upper_arm.R','body_forearm.L','body_forearm.R']]
verts=[];faces=[];weights=[];smooth=[];cache={}
for ob in objects:
    gn={g.index:g.name for g in ob.vertex_groups};indices={}
    for v in ob.data.vertices:
        key=tuple(round(c,5) for c in v.co)
        if key not in cache:
            cache[key]=len(verts);verts.append(v.co.copy());weights.append({gn[g.group]:g.weight for g in v.groups if gn[g.group] in r.data.bones})
        indices[v.index]=cache[key]
    for p in ob.data.polygons:
        faces.append([indices[i] for i in p.vertices]);smooth.append(not (ob.name=='body_torso' and all(512<=i<688 for i in p.vertices)))
me=bpy.data.meshes.new('EDIT_joint_continuous_reference');me.from_pydata(verts,[],faces);me.update()
for p,flag in zip(me.polygons,smooth):p.use_smooth=flag
proxy=bpy.data.objects.get('EDIT_joint_shading_reference')
if proxy is None:
    proxy=bpy.data.objects.new('EDIT_joint_shading_reference',me)
    collection=bpy.data.collections.get('REVIEW | cameras and lights, excluded from GLB')
    collection.objects.link(proxy)
else:proxy.data=me
proxy.vertex_groups.clear();groups={}
for i,values in enumerate(weights):
    for name,w in values.items():
        if name not in groups:groups[name]=proxy.vertex_groups.new(name=name)
        groups[name].add([i],w,'REPLACE')
arm=next((m for m in proxy.modifiers if m.type=='ARMATURE'),None) or proxy.modifiers.new('Edit reference skin','ARMATURE');arm.object=r
proxy.hide_render=True;proxy.hide_set(True);proxy['exclude_from_export']=True
proxy['purpose']='Blender deformation normal reference only. Export body/cap/mask meshes; no additional physical bones.'
for ob in objects:
    vg=ob.vertex_groups.get('EDIT_joint_normal_mask') or ob.vertex_groups.new(name='EDIT_joint_normal_mask')
    vg.remove(list(range(len(ob.data.vertices))))
    ids=[]
    for v in ob.data.vertices:
        active=v.index<128 if ob.name!='body_torso' else ((v.index<384 and abs(v.co.x)>.10 and v.co.z>1.1) or 416<=v.index<448 or v.index>=688)
        if active:ids.append(v.index)
    vg.add(ids,1,'REPLACE')
    m=ob.modifiers.get('Continuous joint shading') or ob.modifiers.new('Continuous joint shading','DATA_TRANSFER')
    m.object=proxy;m.use_loop_data=True;m.data_types_loops={'CUSTOM_NORMAL'};m.loop_mapping='POLYINTERP_NEAREST'
    m.mix_factor=1
    m.vertex_group=vg.name
print('Connected edit-time normals enabled; hidden proxy excluded from GLB')
