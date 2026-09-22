import bpy
import json
from mathutils.bvhtree import BVHTree
scene=bpy.data.scenes['MONSTER_REFINED_V015']
bpy.context.window.scene=scene
rig=bpy.data.objects['Refined015_Rig']
mesh=bpy.data.objects['Refined015_Mesh']
for track in rig.animation_data.nla_tracks: track.mute=True
audit=[]
for track in rig.animation_data.nla_tracks:
    action=track.strips[0].action
    rig.animation_data.action=action
    rig.animation_data.action_slot=action.slots[0]
    bad=[]
    min_z=100
    max_height=0
    for frame in range(int(action.frame_range[0]),int(action.frame_range[1])+1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        obj=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
        ev=obj.to_mesh()
        ev.calc_loop_triangles()
        vs=[v.co.copy() for v in ev.vertices]
        ts=[tuple(t.vertices) for t in ev.loop_triangles]
        tree=BVHTree.FromPolygons(vs,ts,all_triangles=True,epsilon=0)
        pairs=[(a,b) for a,b in tree.overlap(tree) if a<b and not set(ts[a]).intersection(ts[b])]
        if pairs: bad.append((frame,len(pairs)))
        min_z=min(min_z,min(v.z for v in vs))
        max_height=max(max_height,max(v.z for v in vs)-min(v.z for v in vs))
        obj.to_mesh_clear()
    audit.append({'clip':action.name,'bad_frames':bad,'min_z':min_z,'max_height':max_height})
scene['animation_audit']=json.dumps(audit)
rig.animation_data.action=next(t.strips[0].action for t in rig.animation_data.nla_tracks if t.name=='idle')
rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_set(0)
print(json.dumps(audit))

