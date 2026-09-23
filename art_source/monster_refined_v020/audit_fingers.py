import bpy,math,json
from mathutils import Vector
from pathlib import Path
OUT=Path(__file__).resolve().parent
s=bpy.data.scenes['MONSTER_REFINED_V020'];bpy.context.window.scene=s
r=bpy.data.objects['Refined020_Rig'];src=bpy.data.objects['Refined019_Rig'];ss=bpy.data.scenes['MONSTER_REFINED_V019']
for rig in [r,src]:
 for t in rig.animation_data.nla_tracks:t.mute=True
report=[]
for clip in ['REST']+[t.name for t in r.animation_data.nla_tracks]:
 row={'clip':clip,'minimum_mcp':180,'minimum_pip':180,'maximum_pip':-180,'maximum_preserved_bone_error':0,'failures':[]}
 r.data.pose_position='REST' if clip=='REST' else 'POSE';src.data.pose_position=r.data.pose_position
 if clip!='REST':
  a=next(t.strips[0].action for t in r.animation_data.nla_tracks if t.name==clip);r.animation_data.action=a;r.animation_data.action_slot=a.slots[0]
  old=next(t.strips[0].action for t in src.animation_data.nla_tracks if t.name==clip);src.animation_data.action=old;src.animation_data.action_slot=old.slots[0]
  count=int(a.frame_range[1])+1
 else:count=1
 for frame in range(count):
  bpy.context.window.scene=ss;ss.frame_set(frame);bpy.context.view_layer.update()
  old_pose={b.name:b.matrix.copy() for b in src.pose.bones}
  bpy.context.window.scene=s;s.frame_set(frame);bpy.context.view_layer.update()
  for side,sign in [('L',1),('R',-1)]:
   def point(name):return r.data.bones[name+'_'+side].head_local.copy() if clip=='REST' else r.pose.bones[name+'_'+side].head.copy()
   forward=(point('middle_01')-point('hand')).normalized()
   lateral=point('thumb_01')-point('middle_01');lateral=(lateral-forward*lateral.dot(forward)).normalized();palm=forward.cross(lateral)*sign
   for finger in ['index','middle','ring','pinky']:
    first=point(finger+'_01');joint=point(finger+'_02')
    tip=r.data.bones[finger+'_02_'+side].tail_local if clip=='REST' else r.pose.bones[finger+'_02_'+side].tail
    proximal=(joint-first).normalized();distal=(tip-joint).normalized()
    normal=(palm-proximal*palm.dot(proximal)).normalized()
    mcp=math.degrees(math.atan2(proximal.dot(palm),proximal.dot(forward)))
    pip=math.degrees(math.atan2(distal.dot(normal),distal.dot(proximal)))
    row['minimum_mcp']=min(row['minimum_mcp'],mcp);row['minimum_pip']=min(row['minimum_pip'],pip);row['maximum_pip']=max(row['maximum_pip'],pip)
    if mcp<2.8 or pip<11.8 or pip>70.2:row['failures'].append([frame,finger,side,mcp,pip])
   for name in ['hand','thumb_01','thumb_02']:
    bone=name+'_'+side
    current=r.data.bones[bone].matrix_local if clip=='REST' else r.pose.bones[bone].matrix
    before=src.data.bones[bone].matrix_local if clip=='REST' else old_pose[bone]
    err=max(abs(current[i][j]-before[i][j]) for i in range(4) for j in range(4))
    row['maximum_preserved_bone_error']=max(row['maximum_preserved_bone_error'],err)
    if err>1e-5:row['failures'].append([frame,bone,'preservation',err])
 report.append(row)
 print('FINGER_AUDIT',clip,'MCP',round(row['minimum_mcp'],2),'PIP',round(row['minimum_pip'],2),round(row['maximum_pip'],2),'failures',len(row['failures']),flush=True)
(OUT/'finger_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
assert not any(row['failures'] for row in report),'Anatomical finger or preserved thumb failure'
