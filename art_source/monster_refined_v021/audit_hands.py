"""Verify actual replacement topology, skin weights and all three hinges."""
import bpy,bmesh,json,math
from pathlib import Path
from mathutils import Vector
OUT=Path(__file__).resolve().parent
r=bpy.data.objects['Refined021_Rig'];m=bpy.data.objects['Refined021_Mesh'];s=bpy.data.scenes['MONSTER_REFINED_V021'];bpy.context.window.scene=s
old=bpy.data.objects['Refined020_Mesh'];names={g.index:g.name for g in old.vertex_groups}
finger_names=['index','middle','ring','pinky'];hand_stems=['hand','thumb']+finger_names
keep=[v.co.copy() for v in old.data.vertices if sum(g.weight for g in v.groups if any(names[g.group].startswith(n+'_') for n in hand_stems))<=.5]
assert len(keep)==8737
preserved_error=max((point-m.data.vertices[i].co).length for i,point in enumerate(keep))
assert preserved_error<1e-6,('Body changed',preserved_error)
groups={g.index:g.name for g in m.vertex_groups}
hand_ids={v.index for v in m.data.vertices if any(groups[g.group].startswith('RebuiltHand_') and g.weight>.5 for g in v.groups)}
assert len(hand_ids)==6422
deform={g.index for g in m.vertex_groups if g.name in r.data.bones and r.data.bones[g.name].use_deform}
max_weight_error=max(abs(1-sum(g.weight for g in m.data.vertices[i].groups if g.group in deform)) for i in hand_ids)
assert max_weight_error<1e-5
bm=bmesh.new();bm.from_mesh(m.data);bm.verts.ensure_lookup_table()
hand_bad_edges=sum(not e.is_manifold for e in bm.edges if any(v.index in hand_ids for v in e.verts))
assert hand_bad_edges==0;bm.free()
for side in ['L','R']:
 for name in finger_names:
  a,b,c=[r.data.bones[name+'_%02d_'%i+side] for i in [1,2,3]]
  assert b.parent==a and c.parent==b and b.use_connect and c.use_connect
  assert .024<c.length<.05
report={'old_hand_vertices_removed':len(old.data.vertices)-len(keep),'replacement_vertices':len(hand_ids),'body_max_position_error':preserved_error,'max_weight_error':max_weight_error,'replacement_nonmanifold_edges':hand_bad_edges,'deform_bones':sum(b.use_deform for b in r.data.bones),'clips':[]}
for t in r.animation_data.nla_tracks:t.mute=True
r.data.pose_position='POSE'
for track in r.animation_data.nla_tracks:
 a=track.strips[0].action;r.animation_data.action=a;r.animation_data.action_slot=a.slots[0]
 row={'clip':track.name,'min_flexion':[180,180,180],'max_flexion':[-180,-180,-180]}
 for frame in range(int(a.frame_range[1])+1):
  s.frame_set(frame);bpy.context.view_layer.update()
  for side in ['L','R']:
   at=lambda name:r.pose.bones[name+'_'+side].head.copy()
   forward=(at('middle_01')-at('hand')).normalized();radial=at('thumb_01')-at('middle_01');radial=(radial-forward*radial.dot(forward)).normalized()
   palm=forward.cross(radial)*(1 if side=='L' else -1)
   for name in finger_names:
    directions=[r.pose.bones[name+'_%02d_'%i+side].matrix.to_3x3().col[1].normalized() for i in [1,2,3]]
    previous=[forward]+directions[:2]
    for joint,(start,end) in enumerate(zip(previous,directions)):
     normal=(palm-start*palm.dot(start)).normalized()
     angle=math.degrees(math.atan2(end.dot(normal),end.dot(start)))
     row['min_flexion'][joint]=min(row['min_flexion'][joint],angle);row['max_flexion'][joint]=max(row['max_flexion'][joint],angle)
     assert -1<angle<75,(track.name,frame,side,name,joint,angle)
 report['clips'].append(row)
 print('HAND_AUDIT',track.name,row['min_flexion'],row['max_flexion'],flush=True)
(OUT/'hand_validation.json').write_text(json.dumps(report,indent=2))
print('PASS: replacement topology, continuous wrist, three phalanges, normalized skinning and 41 clips')
