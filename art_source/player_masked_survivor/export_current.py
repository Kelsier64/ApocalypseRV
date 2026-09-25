"""Stage the current full character and nine independent limb GLBs in work/export."""
import bpy,json
from mathutils import Matrix
OUT='C:/Users/evan4/Projects/ApocalypseRV/art_source/player_masked_survivor/work/export/'
main=bpy.data.scenes['PLAYER_MASKED_SURVIVOR'];bpy.context.window.scene=main
source=bpy.data.objects['Survivor_Rig'];source.animation_data.action=None
for t in source.animation_data.nla_tracks:t.mute=True
for p in source.pose.bones:p.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
for o in main.objects:o.select_set((o.type=='MESH' and o.name.startswith(('body_','cap_','mask_default')) and not o.get('exclude_from_export',False)) or o==source)
bpy.context.view_layer.objects.active=source
bpy.ops.export_scene.gltf(filepath=OUT+'player_masked_survivor.glb',use_selection=True,use_active_scene=True,export_animation_mode='NLA_TRACKS',export_yup=True,export_animations=True,export_skins=True,export_extras=True,export_rest_position_armature=True,export_force_sampling=True,export_anim_slide_to_zero=True)
cutmap=json.loads(source['cut_map']);manifest=[]
for cut in cutmap:
    label=cut['cut'];primary=cut['bone'];descendants={primary}|{b.name for b in source.data.bones[primary].children_recursive};allowed=descendants|{'root'}
    limb=cut['limb'];names={limb}
    if limb.startswith('body_upper_arm'):names.add(limb.replace('upper_arm','forearm'))
    if limb.startswith('body_thigh'):names.add(limb.replace('thigh','shin'))
    if limb=='body_head':names.add('mask_default')
    closures=set()
    for row in cutmap:
        if row['body'] in names:closures.add(row['caps'][0])
        if row['limb'] in names:closures.add(row['caps'][1])
    names|=closures
    scene=bpy.data.scenes.new('DETACHED_CURRENT | '+label);bpy.context.window.scene=scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    collection=bpy.data.collections.new('DetachedCurrent '+label+' | independent bones and weights');scene.collection.children.link(collection)
    rig=source.copy();rig.data=source.data.copy();rig.animation_data_clear();collection.objects.link(rig);rig.name='DetachedCurrentRig_'+label
    bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
    # Only prune the newly made copy; the source and existing detached scenes are preserved.
    for bone in list(rig.data.edit_bones):
        if bone.name not in allowed:rig.data.edit_bones.remove(bone)
    rig.data.edit_bones[primary].parent=rig.data.edit_bones['root']
    bpy.ops.object.mode_set(mode='OBJECT')
    renames=[]
    try:
        for name in sorted(names):
            original=bpy.data.objects[name];original.name=name+'_REV7_SOURCE'
            obj=original.copy();obj.data=original.data.copy();obj.name=name;collection.objects.link(obj);obj.parent=rig
            renames.append((original,name,obj))
            # Detached copies must not depend on the full-body editing normal reference.
            for modifier in list(obj.modifiers):
                if modifier.type=='ARMATURE':modifier.object=rig
                elif modifier.type=='DATA_TRANSFER':obj.modifiers.remove(modifier)
            by_index={g.index:g.name for g in obj.vertex_groups};newweights=[]
            for v in obj.data.vertices:
                w={}
                for g in v.groups:
                    n=by_index[g.group]
                    if n not in source.data.bones:continue
                    n=n if n in allowed else primary;w[n]=w.get(n,0)+g.weight
                newweights.append(w)
            obj.vertex_groups.clear()
            for vi,weights in enumerate(newweights):
                total=sum(weights.values())
                for n,w in weights.items():
                    if w>.00001:
                        vg=obj.vertex_groups.get(n) or obj.vertex_groups.new(name=n);vg.add([vi],w/total,'REPLACE')
        for o in scene.objects:o.select_set(True)
        bpy.context.view_layer.objects.active=rig
        filename='detached_'+label.replace('.','_')+'.glb'
        bpy.ops.export_scene.gltf(filepath=OUT+'detached/'+filename,use_selection=True,use_active_scene=True,export_animations=False,export_skins=True,export_yup=True,export_extras=True,export_rest_position_armature=True)
    finally:
        for original,name,obj in renames:obj.name='DETACH_CURRENT_'+label+'_'+name;original.name=name
    manifest.append({'cut':label,'file':'detached/'+filename,'bones':sorted(allowed),'meshes':sorted(names),'removed_ancestor_weights':'reassigned to '+primary,'origin':'unchanged, full-character ground origin'})
bpy.context.window.scene=main
main['detached_manifest']=json.dumps(manifest)
main['active_asset_revision']='waterproof workwear and cautious walk, 1.60m'
print('DETACHED_MANIFEST='+json.dumps(manifest))
print('EXPORT_COMPLETE')

