"""Audit fixed roots, jaw timing, closed-mouth tooth occlusion and body collisions."""
import bpy,json,math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from pathlib import Path
OUT=Path('C:/Users/evan4/Projects/ApocalypseRV/art_source/monster_refined_v021')
s=bpy.data.scenes['MONSTER_REFINED_V021'];bpy.context.window.scene=s
r=bpy.data.objects['Refined021_Rig'];m=bpy.data.objects['Refined021_Mesh']
r.data.pose_position='POSE'
for t in r.animation_data.nla_tracks:t.mute=True
rest=[v.co.copy() for v in m.data.vertices]
# New hands append vertices after teeth: locate the 18 original tooth components.
tooth_vertices=set(v for p in m.data.polygons if p.material_index==3 for v in p.vertices)
tooth_tips=[]
while tooth_vertices:
 component={min(tooth_vertices)};pending=list(component)
 while pending:
  v=pending.pop()
  for edge in m.data.edges:
   if v not in edge.vertices:continue
   for other in edge.vertices:
    if other in tooth_vertices and other not in component:component.add(other);pending.append(other)
 tooth_vertices-=component
 assert len(component)==24
 tooth_tips.append(sorted(component)[16:24])
assert len(tooth_tips)==18
# The zero-gap mouth seam, cavity/skin contacts and tooth roots intentionally meet.
# Audit limb/torso self-intersections separately from those contacts.
mouth=[abs(v.x)<.075 and v.y<-.055 and 1.95<v.z<2.07 for v in rest]
report={'clips':[],'tooth_visibility':[],'mouth_contact_region_excluded_from_body_collision_audit':True}
for t in r.animation_data.nla_tracks:
 a=t.strips[0].action;r.animation_data.action=a;r.animation_data.action_slot=a.slots[0]
 row={'clip':t.name,'body_collision_frames':[],'tooth_collision_frames':[],'max_root_translation':0,'max_jaw_degrees':0}
 for frame in range(int(a.frame_range[0]),int(a.frame_range[1])+1):
  s.frame_set(frame);bpy.context.view_layer.update()
  row['max_root_translation']=max(row['max_root_translation'],r.pose.bones['root'].location.length)
  angle=math.degrees(r.pose.bones['jaw'].rotation_quaternion.angle);row['max_jaw_degrees']=max(row['max_jaw_degrees'],angle)
  ob=m.evaluated_get(bpy.context.evaluated_depsgraph_get());ev=ob.to_mesh();ev.calc_loop_triangles()
  vs=[v.co.copy() for v in ev.vertices];ts=[tuple(p.vertices) for p in ev.loop_triangles];mats=[ev.polygons[p.polygon_index].material_index for p in ev.loop_triangles]
  tree=BVHTree.FromPolygons(vs,ts,all_triangles=True,epsilon=0)
  body=0;teeth=0
  for x,y in tree.overlap(tree):
   if x>=y or set(ts[x]).intersection(ts[y]):continue
   if mats[x]==3 and mats[y]==3:teeth+=1
   if mats[x]!=3 and mats[y]!=3 and not any(mouth[v] for v in ts[x]+ts[y]):body+=1
  if body:row['body_collision_frames'].append([frame,body])
  if teeth:row['tooth_collision_frames'].append([frame,teeth])
  if t.name=='grab_stand_bite' and frame in [0,14,23,39]:
   direction=r.pose.bones['head'].matrix.to_3x3()@r.data.bones['head'].matrix_local.to_3x3().inverted()
   for az,el in [(0,0),(-30,0),(30,0),(0,15),(0,-15)]:
    azr,elr=map(math.radians,[az,el]);front=direction@Vector((math.sin(azr)*math.cos(elr),-math.cos(azr)*math.cos(elr),math.sin(elr)))
    visible=0
    for ids in tooth_tips:
     tip=sum((vs[j] for j in ids),Vector())/8
     hit=tree.ray_cast(tip+front, -front,1.1)
     if hit[2] is not None and mats[hit[2]]==3:visible+=1
    report['tooth_visibility'].append({'frame':frame,'view':[az,el],'visible_teeth':visible})
  ob.to_mesh_clear()
 report['clips'].append(row)
 print('AUDIT',t.name,row['max_jaw_degrees'],len(row['body_collision_frames']),len(row['tooth_collision_frames']),flush=True)
r.data.pose_position='REST';bpy.context.view_layer.update();ob=m.evaluated_get(bpy.context.evaluated_depsgraph_get());ev=ob.to_mesh();report['neutral_height']=max(v.co.z for v in ev.vertices)-min(v.co.z for v in ev.vertices);ob.to_mesh_clear()
report['source_vertices']=len(m.data.vertices);m.data.calc_loop_triangles();report['triangles']=len(m.data.loop_triangles);report['materials']=len(m.data.materials)
(OUT/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('VISIBILITY',report['tooth_visibility']);print('METRICS',report['source_vertices'],report['triangles'],report['neutral_height'])


