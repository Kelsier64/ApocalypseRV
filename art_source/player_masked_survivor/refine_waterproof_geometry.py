"""Prepend waterproof_fields.py; current skeleton and cut rings are fixed."""
import bpy,json
from mathutils import Matrix,Vector
s=bpy.data.scenes['PLAYER_MASKED_SURVIVOR'];bpy.context.window.scene=s;r=bpy.data.objects['Survivor_Rig'];r.animation_data.action=None
for t in r.animation_data.nla_tracks:t.mute=True
for p in r.pose.bones:p.matrix_basis=Matrix.Identity(4)
changed={}
for o in s.objects:
    if o.type!='MESH' or not o.name.startswith('body_') or o.name=='body_head':continue
    backup=bpy.data.objects.get('REV9_BASE_'+o.name)
    if backup is None:
        backup=o.copy();backup.data=o.data.copy();backup.name='REV9_BASE_'+o.name;backup.use_fake_user=True
    ids=set()
    for p in o.data.polygons:
        if o.data.materials[p.material_index].name in ['suit_dye','reflective_orange']:ids.update(p.vertices)
    if o.name=='body_torso':ids={i for i in ids if i<384}
    if 'forearm' in o.name:ids={i for i in ids if i<128}
    # Exact boundary rings are unchanged, including their tangent neighbourhood.
    if 'upper_arm' in o.name or 'forearm' in o.name:ids-=(set(range(16))|set(range(112,128)))
    if 'thigh' in o.name:ids-=(set(range(32))|set(range(224,256)))
    if 'shin' in o.name:ids={i for i in ids if 32<=i<160}
    for v,b in zip(o.data.vertices,backup.data.vertices):v.co=b.co
    n=0
    for i in ids:
        p=backup.data.vertices[i].co;d=waterproof_offset(p,o.name);o.data.vertices[i].co=p+d;n+=d.length>1e-7
    o.data.update();changed[o.name]=n
    # Recompute only loops next to changed cloth vertices; retain joint normals.
    sums={}
    for p in o.data.polygons:
        if o.data.materials[p.material_index].name!='suit_dye':continue
        for vi in p.vertices:sums[vi]=sums.get(vi,Vector())+p.normal*p.area
    normals=[]
    for loop,old in zip(o.data.loops,backup.data.corner_normals):
        vi=loop.vertex_index;normals.append(sums[vi].normalized() if vi in ids and vi in sums else old.vector)
    o.data.normals_split_custom_set(normals)
bpy.context.view_layer.update();s['waterproof_revision']=10
print('WATERPROOF_GEOMETRY='+json.dumps(changed))
