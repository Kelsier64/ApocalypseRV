import bpy,bmesh,json
from collections import Counter
from mathutils import Vector
from mathutils.bvhtree import BVHTree
r=bpy.data.objects['Refined021_Rig'];m=bpy.data.objects['Refined021_Mesh'];s=bpy.data.scenes['MONSTER_REFINED_V021'];bpy.context.window.scene=s
for t in r.animation_data.nla_tracks:t.mute=True
groups={g.index:g.name for g in m.vertex_groups}
for clip in ['REST','idle','grab_stand_hold']:
 r.data.pose_position='REST' if clip=='REST' else 'POSE'
 if clip!='REST':
  a=next(t.strips[0].action for t in r.animation_data.nla_tracks if t.name==clip);r.animation_data.action=a;r.animation_data.action_slot=a.slots[0]
 s.frame_set(0);bpy.context.view_layer.update()
 ob=m.evaluated_get(bpy.context.evaluated_depsgraph_get());ev=ob.to_mesh();ev.calc_loop_triangles()
 vs=[v.co.copy() for v in ev.vertices];ts=[tuple(p.vertices) for p in ev.loop_triangles]
 tree=BVHTree.FromPolygons(vs,ts,all_triangles=True,epsilon=0)
 pairs=[];counts=Counter()
 def labels(ids):
  names=Counter(groups[g.group] for idx in ids for g in m.data.vertices[idx].groups if g.weight>.1 and not groups[g.group].startswith('Rebuilt'))
  return str(names.most_common(2))
 for a,b in tree.overlap(tree):
  if a>=b or set(ts[a]).intersection(ts[b]):continue
  if any(abs(m.data.vertices[v].co.x)<.075 and m.data.vertices[v].co.y<-.055 and 1.95<m.data.vertices[v].co.z<2.07 for v in ts[a]+ts[b]):continue
  counts[(labels(ts[a]),labels(ts[b]))]+=1
  if len(pairs)<10:pairs.append([ts[a],ts[b],list(sum((vs[v] for v in ts[a]),Vector())/3)])
 print(clip,'collisions',sum(counts.values()),'GROUPS',counts,'PAIRS',pairs,flush=True)
 ob.to_mesh_clear()
bm=bmesh.new();bm.from_mesh(m.data)
print('NONMANIFOLD',sum(not e.is_manifold for e in bm.edges),'LOOSE',sum(not v.link_edges for v in bm.verts))
bm.free()
bm=bmesh.new();bm.from_mesh(bpy.data.objects['Refined020_Mesh'].data);print('SOURCE_NONMANIFOLD',sum(not e.is_manifold for e in bm.edges));bm.free()
for img in [bpy.data.images['Raker011_Albedo'],bpy.data.images['Raker021_HandAlbedo']]:print('COLORSPACE',img.name,img.colorspace_settings.name)
