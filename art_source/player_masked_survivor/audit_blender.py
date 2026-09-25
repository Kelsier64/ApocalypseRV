import bpy,json,math
from mathutils import Matrix,Vector
main=bpy.data.scenes['PLAYER_MASKED_SURVIVOR'];bpy.context.window.scene=main
rig=bpy.data.objects['Survivor_Rig'];rig.animation_data.action=None
for t in rig.animation_data.nla_tracks:t.mute=True
for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
meshes=[o for o in main.objects if o.type=='MESH' and not o.get('exclude_from_export',False)];fail=[]
statistics={}
for ob in meshes:
    bad=0;maxweights=0
    for v in ob.data.vertices:
        gs=[g.weight for g in v.groups if g.weight>1e-6 and ob.vertex_groups[g.group].name in rig.data.bones];maxweights=max(maxweights,len(gs))
        if not gs or abs(sum(gs)-1)>1e-4:bad+=1
    if bad or maxweights>4:fail.append('weights '+ob.name)
    statistics[ob.name]={'vertices':len(ob.data.vertices),'triangles':sum(len(p.vertices)-2 for p in ob.data.polygons),'max_influences':maxweights,'bad_weights':bad}
seams=[]
for cut in json.loads(rig['cut_map']):
    n=16 if cut['cut'].startswith(('shoulder','elbow')) else 32
    pair=[]
    for capname,bodyname in zip(cut['caps'],[cut['body'],cut['limb']]):
        cap=bpy.data.objects[capname];body=bpy.data.objects[bodyname]
        match=[]
        for v in list(cap.data.vertices)[:n]:
            nearest=body.data.vertices[min(((p.co-v.co).length_squared,p.index) for p in body.data.vertices)[1]]
            match.append((v.index,nearest.index))
        pair.append((cap,body,match))
    seams.append((cut['cut'],pair))
clips=json.loads(main['actions_manifest']);results=[];maxseam=0
for info in clips:
    action=bpy.data.actions[info['name']];rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
    contacts={'L':[],'R':[]};worst=0;finite=True;max_edge_ratio=0
    for frame in range(info['frames'][0],info['frames'][1]+1):
        main.frame_set(frame);bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
        evaluated={o.name:o.evaluated_get(deps).to_mesh() for o in meshes}
        for ob in meshes:
            ev=evaluated[ob.name]
            for v in ev.vertices:finite=finite and all(math.isfinite(c) for c in v.co)
            for edge in ob.data.edges:
                a,b=edge.vertices;rest=(ob.data.vertices[a].co-ob.data.vertices[b].co).length
                if rest>.004:max_edge_ratio=max(max_edge_ratio,(ev.vertices[a].co-ev.vertices[b].co).length/rest)
        for label,pairs in seams:
            for cap,body,matches in pairs:
                cv=evaluated[cap.name].vertices;bv=evaluated[body.name].vertices
                worst=max(worst,max((cv[a].co-bv[b].co).length for a,b in matches))
        for side in ['L','R']:
            ob=bpy.data.objects['body_shin.'+side];ev=evaluated[ob.name]
            ids=[v.index for v in ob.data.vertices if v.co.z<.041]
            ground=min(ev.vertices[i].co.z for i in ids)
            if abs(ground)<.006:contacts[side].append(frame)
        for ob in meshes:ob.evaluated_get(deps).to_mesh_clear()
    def intervals(frames):
        result=[]
        for f in frames:
            if result and f==result[-1][1]+1:result[-1][1]=f
            else:result.append([f,f])
        return result
    record=dict(info);record.update({'all_vertices_finite':finite,'max_edge_length_ratio':max_edge_ratio,'max_cut_rim_gap_m':worst,'feet_ground_contact_frames':{s:intervals(c) for s,c in contacts.items()}});results.append(record)
    if not finite:fail.append('nonfinite '+info['name'])
    if worst>.0001:fail.append('seam mismatch '+info['name'])
    maxseam=max(maxseam,worst)
hand_checks={}
for name in ['idle','sit_driver','hold_small','QA_fists']:
    a=bpy.data.actions[name];rig.animation_data.action=a;rig.animation_data.action_slot=a.slots[0];main.frame_set(1);bpy.context.view_layer.update()
    check={}
    for side in ['L','R']:
        thumb=rig.pose.bones['thumb_01.'+side].head;little=rig.pose.bones['pinky_01.'+side].head
        check[side]={'thumb_minus_pinky_world':list(thumb-little)}
    hand_checks[name]=check
rig.animation_data.action=None
for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
report={'meshes':statistics,'actions':results,'max_cut_rim_gap_m':maxseam,'hand_anatomy':hand_checks,'failures':fail,'scope':'All source action frames: finite positions, edge stretch and paired cut rim agreement. Not an exhaustive self-intersection or motion-blend proof.'}
print('AUDIT_JSON='+json.dumps(report))
