"""Run in Blender MCP after optimize_model.py, before animate_export.py.

Replaces the first-pass feet, keeps upper-leg geometry and the existing rig.
The source v1 is retained in versions/feet_v1; repeat runs replace this pass.
"""
import bpy
import bmesh
import math
from mathutils import Vector

ROOT = 'C:/Users/evan4/Projects/ApocalypseRV/'
scene = bpy.data.scenes['BARREL_MAN_AUTHORING']
bpy.context.window.scene = scene
rig = bpy.data.objects['BarrelManRig']
rig.data.pose_position = 'REST'
skin = bpy.data.materials['BarrelMan_DirtySkin']
nodes = skin.node_tree.nodes
links = skin.node_tree.links
bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
nail_mat = bpy.data.materials['BarrelMan_DirtyNails']
nail_bsdf = next(n for n in nail_mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
nail_bsdf.inputs['Base Color'].default_value = (.235, .162, .102, 1)
nail_bsdf.inputs['Roughness'].default_value = .53
edge_mat = bpy.data.materials.get('BarrelMan_NailFreeEdge') or bpy.data.materials.new('BarrelMan_NailFreeEdge')
edge_mat.use_nodes = True
edge_bsdf = next(n for n in edge_mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
edge_bsdf.inputs['Base Color'].default_value = (.29, .225, .143, 1)
edge_bsdf.inputs['Roughness'].default_value = .64

def activate(ob):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob

def create_mesh(name, verts, faces):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    ob = bpy.data.objects.new(name, data)
    scene.collection.objects.link(ob)
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    return ob

def loft_faces(count, segments):
    faces = []
    for j in range(count-1):
        for k in range(segments):
            a = j*segments+k
            b = j*segments+(k+1)%segments
            faces.append((a, b, b+segments, a+segments))
    faces.append(tuple(reversed(range(segments))))
    faces.append(tuple((count-1)*segments+k for k in range(segments)))
    return faces

def smoothstep(v):
    v = max(0, min(1, v))
    return v*v*(3-2*v)

def gauss(v, center, width):
    return math.exp(-((v-center)/width)**2)

legs = []
for side, suffix in [(-1, 'R'), (1, 'L')]:
    x = side*.145
    leg = bpy.data.objects['Leg_'+suffix]
    # Preserve the first-pass upper leg exactly across repeatable revisions.
    original_name = 'BarrelMan_UpperLegBaseline_'+suffix
    original = bpy.data.meshes.get(original_name)
    if original is None:
        original = leg.data.copy()
        original.name = original_name
        original.use_fake_user = True
    leg.data = original.copy()
    for mod in list(leg.modifiers): leg.modifiers.remove(mod)
    leg.vertex_groups.clear()
    # Cut a joining ring in the narrow lower calf. No overlap or detached foot.
    bm = bmesh.new()
    bm.from_mesh(leg.data)
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
        plane_co=(0,0,.255), plane_no=(0,0,1), clear_inner=True, clear_outer=False)
    bm.to_mesh(leg.data)
    bm.free()
    activate(leg)
    # Reserve more of the fixed game budget for the ankle and five toes.
    dec = leg.modifiers.new('Upper_leg_budget', 'DECIMATE')
    dec.ratio = min(1, 9000/max(1, sum(len(p.vertices)-2 for p in leg.data.polygons)))
    bpy.ops.object.modifier_apply(modifier=dec.name)

    # Ankle rings: medial malleolus sits higher; lateral malleolus farther back.
    verts = []
    segments = 48
    ankle_profiles = [(.065,.036,.036,.025),(.09,.032,.036,.017),
        (.115,.029,.032,.009),(.14,.029,.031,.011),(.165,.030,.032,.014),
        (.19,.034,.036,.021),(.215,.042,.041,.028),(.24,.050,.047,.033),
        (.265,.056,.052,.037),(.285,.061,.056,.04)]
    for z, rx, ry, cy in ankle_profiles:
        for k in range(segments):
            a = math.tau*k/segments
            ca, sa = math.cos(a), math.sin(a)
            medial = gauss(z,.144,.020) * max(0,-ca)**10 * .010
            lateral = gauss(z,.125,.021) * max(0,ca)**10 * .009
            u = (rx+medial+lateral)*ca
            # Narrow Achilles cord and hollows on either side, smoothly continuous.
            achilles = .010*max(0,sa)**18 * gauss(z,.165,.075)
            yy = cy+ry*sa+achilles
            yy -= .006*max(0,sa)**2*abs(ca)**2*gauss(z,.13,.065)
            # Tibialis anterior passes diagonally over the front of the ankle.
            yy -= .0035*gauss(ca,-.25,.17)*max(0,-sa)*gauss(z,.18,.07)
            verts.append((x+side*u, yy, z))
    ankle = create_mesh('RefinedAnkle_'+suffix, verts, loft_faces(len(ankle_profiles),segments))
    parts = [ankle]

    # Longitudinal foot sections: padded heel, narrow waist, raised medial arch,
    # metatarsal heads, tapering outer border. Values are anatomical metres.
    foot_profiles = [
        (.091,.004,.040,.055,.024),(.084,.022,.042,.076,.011),
        (.067,.035,.043,.092,.002),(.042,.037,.045,.102,.000),
        (.018,.035,.046,.112,.001),(-.010,.035,.045,.107,.004),
        (-.037,.038,.042,.095,.006),(-.065,.045,.037,.077,.003),
        (-.091,.054,.032,.063,.001),(-.116,.061,.029,.054,.000),
        (-.136,.060,.027,.049,.000),(-.152,.050,.025,.043,.002),
        (-.164,.033,.023,.035,.006),(-.169,.003,.021,.024,.017)]
    verts = []
    for yy, width, cz, top, bottom in foot_profiles:
        for k in range(segments):
            a = math.tau*k/segments
            ca, sa = math.cos(a), math.sin(a)
            # Slightly fuller lateral border and natural inward heel taper.
            center_u = .006*smoothstep((-yy-.02)/.1)
            u = center_u+width*ca
            zz = cz+(top-cz)*max(0,sa)+(cz-bottom)*min(0,sa)
            arch = .024*gauss(yy,-.035,.046)*max(0,-ca)**1.5*max(0,-sa)**.5
            zz += arch
            # Five extensor tendons taper into the forefoot; low relief, not cords.
            if sa > 0:
                for tu in [-.032,-.004,.021,.043,.06]:
                    route = tu*smoothstep((-yy+.015)/.145)
                    zz += .0018*gauss(u,route,.005)*gauss(yy,-.08,.055)*sa**5
            verts.append((x+side*u, yy, zz))
    foot = create_mesh('RefinedFoot_'+suffix,verts,loft_faces(len(foot_profiles),segments))
    parts.append(foot)

    # Unequal phalanges, ball-to-toe webbing, dorsal joint creases, rounded pads.
    toe_specs = [(-.037,-.129,.105,.0205,.0215),(-.004,-.132,.099,.014,.017),
        (.022,-.128,.092,.0125,.016),(.044,-.120,.082,.011,.0145),
        (.061,-.110,.071,.010,.013)]
    samples = [0,.06,.13,.22,.30,.34,.38,.42,.49,.57,.63,.67,.71,.77,.83,.89,.94,.975,1]
    nail_specs = []
    for idx,(u,base,length,radius,rz) in enumerate(toe_specs):
        verts = []
        for t in samples:
            yy = base-length*t
            taper = 1-.18*t
            taper += .075*gauss(t,.42,.08)+.075*gauss(t,.75,.11)
            if t > .87: taper *= math.sqrt(max(.015,1-((t-.87)/.135)**2))
            center = .025 if idx == 0 else .0205
            center += .010*(1-t)**2 + .002*math.sin(math.pi*t)
            for k in range(32):
                a = math.tau*k/32
                ca, sa = math.cos(a), math.sin(a)
                # Lesser toes are gently curled; joint valleys affect dorsal skin.
                fold = (.0011*gauss(t,.34,.030)+.0008*gauss(t,.63,.026))*max(0,sa)**3
                zz = center + rz*taper*sa-fold
                verts.append((x+side*(u+radius*taper*ca),yy,max(.002,zz)))
        toe = create_mesh('RefinedToe_%d_%s'%(idx+1,suffix),verts,loft_faces(len(samples),32))
        parts.append(toe)
        nail_specs.append((idx,u,base-length*.785,radius*.64,length*.125))

    # Curved profile interpolation removes the faceted, stepped first-pass ankle.
    for part in parts:
        activate(part)
        sub = part.modifiers.new('Anatomical_profile_interpolation','SUBSURF')
        sub.levels = 2 if part in [ankle,foot] else 1
        bpy.ops.object.modifier_apply(modifier=sub.name)
    activate(ankle)
    for part in parts: part.select_set(True)
    bpy.ops.object.join()
    remesh = ankle.modifiers.new('Continuous_foot_skin','REMESH')
    remesh.mode = 'VOXEL'
    remesh.voxel_size = .00165
    remesh.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=remesh.name)
    smooth = ankle.modifiers.new('Skin_relax','SMOOTH')
    smooth.factor = .35
    smooth.iterations = 2
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    bm = bmesh.new()
    bm.from_mesh(ankle.data)
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
        plane_co=(0,0,.235),plane_no=(0,0,1),clear_outer=True,clear_inner=False)
    bm.to_mesh(ankle.data)
    bm.free()
    dec = ankle.modifiers.new('Foot_curvature_budget','DECIMATE')
    dec.ratio = min(1,11200/max(1,sum(len(p.vertices)-2 for p in ankle.data.polygons)))
    bpy.ops.object.modifier_apply(modifier=dec.name)

    # Connect differently sampled boundary loops by angular progression.
    verts = [tuple(v.co) for v in leg.data.vertices]
    faces = [tuple(p.vertices) for p in leg.data.polygons]
    upper_count = len(verts)
    verts.extend(tuple(v.co) for v in ankle.data.vertices)
    faces.extend(tuple(i+upper_count for i in p.vertices) for p in ankle.data.polygons)
    upper = sorted([(math.atan2(v.co.y-.035,v.co.x-x),v.index) for v in leg.data.vertices if abs(v.co.z-.255)<.00001])
    lower = sorted([(math.atan2(v.co.y-.033,v.co.x-x),v.index+upper_count) for v in ankle.data.vertices if abs(v.co.z-.235)<.00001])
    i,j = 0,0
    while i<len(upper) or j<len(lower):
        ui,lj = upper[i%len(upper)][1],lower[j%len(lower)][1]
        ua = upper[(i+1)%len(upper)][0]+(math.tau if i+1>=len(upper) else 0)
        la = lower[(j+1)%len(lower)][0]+(math.tau if j+1>=len(lower) else 0)
        if i<len(upper) and (j>=len(lower) or ua<la):
            faces.append((ui,upper[(i+1)%len(upper)][1],lj))
            i += 1
        else:
            faces.append((ui,lower[(j+1)%len(lower)][1],lj))
            j += 1
    merged = create_mesh('RefinedLeg_'+suffix,verts,faces)
    leg.data = merged.data
    bpy.data.objects.remove(merged,do_unlink=True)
    bpy.data.objects.remove(ankle,do_unlink=True)
    # Relax the narrow joining strip without changing the original upper calf.
    bm = bmesh.new()
    bm.from_mesh(leg.data)
    join_verts = [v for v in bm.verts if .219<v.co.z<.278]
    for iteration in range(12):
        bmesh.ops.smooth_vert(bm,verts=join_verts,factor=.45,use_axis_x=True,use_axis_y=True,use_axis_z=True)
    boundaries = [e for e in bm.edges if e.is_boundary]
    if boundaries: bmesh.ops.holes_fill(bm,edges=boundaries,sides=6)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(leg.data)
    bm.free()
    for p in leg.data.polygons: p.use_smooth = True
    for v in leg.data.vertices:
        if v.co.z<.006: v.co.z = max(0,v.co.z-.0015)*.8
        if v.normal.z>.4 and v.co.z<.070:
            # Shallow skin folds across each toe joint, confined to the dorsal
            # surface. The plantar pads remain smooth and do not pinch shut.
            u=(v.co.x-x)*side
            for index,(tu,base,length,radius,rz) in enumerate(toe_specs):
                t=(base-v.co.y)/length
                if .18<t<.72 and abs(u-tu)<radius*.85:
                    across=max(0,1-((u-tu)/(radius*.85))**2)
                    crease=.0012*gauss(t,.35,.022)+.0007*gauss(t,.64,.024)
                    v.co.z-=crease*across
    leg.data.materials.clear()
    leg.data.materials.append(skin)
    activate(leg)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.01)
    bpy.ops.object.mode_set(mode='OBJECT')

    # Sample the actual remeshed toe surface for a thin curved nail plate.
    # Edges embed in the skin; there is no floating elliptical disc.
    for old in list(scene.objects):
        if old.name.startswith('Nail_') and old.name.endswith('_'+suffix):
            bpy.data.objects.remove(old,do_unlink=True)
    bpy.context.view_layer.update()
    for idx,u,cy,rx,ry in nail_specs:
        verts = []
        faces = []
        rings = [0,.28,.56,.79,.92,1]
        nseg = 24
        for r in rings:
            for k in range(nseg):
                a = math.tau*k/nseg
                ca,sa = math.cos(a),math.sin(a)
                # Soft square corners, width decreases towards the cuticle.
                dx = math.copysign(abs(ca)**.66,ca)*rx*r
                dy = math.copysign(abs(sa)**.66,sa)*ry*r
                dx *= 1-.10*max(0,dy/ry)
                xx,yy = x+side*(u+dx),cy+dy
                hit,pos,normal,face = leg.ray_cast(Vector((xx,yy,.11)),Vector((0,0,-1)))
                zz = pos.z if hit else .042
                # A convex plate with flush perimeter and a thin free edge.
                zz += .00015+.0010*(1-r*r)
                verts.append((xx,yy,zz))
        for ri in range(len(rings)-1):
            for k in range(nseg):
                a=ri*nseg+k
                b=ri*nseg+(k+1)%nseg
                faces.append((a,b,b+nseg,a+nseg))
        nail = create_mesh('Nail_%d_%s'%(idx+1,suffix),verts,faces)
        nail.data.materials.append(nail_mat)
        nail.data.materials.append(edge_mat)
        for p in nail.data.polygons:
            p.use_smooth=True
            # Follow one complete outer ring instead of thresholding a UV row,
            # which made a conspicuous stair-step across the free edge.
            if p.index>=4*nseg and p.center.y<cy: p.material_index=1
        # Merge the centre ring to one vertex; apply before skinning.
        bm=bmesh.new()
        bm.from_mesh(nail.data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(nail.data)
        bm.free()
        vg=nail.vertex_groups.new(name='toes_'+suffix)
        vg.add(list(range(len(nail.data.vertices))),1,'REPLACE')
        mod=nail.modifiers.new('Skin','ARMATURE')
        mod.object=rig
        nail.parent=rig

    groups={name:leg.vertex_groups.new(name=name+'_'+suffix) for name in ['thigh','shin','foot','toes']}
    for v in leg.data.vertices:
        z,y=v.co.z,v.co.y
        if z>.60: weights={'thigh':1}
        elif z>.44:
            t=max(0,min(1,(z-.44)/.16))
            weights={'thigh':t,'shin':1-t}
        elif z>.20: weights={'shin':1}
        elif z>.09:
            # Forefoot stays rigid as the ankle bends; the blend is spatially
            # restricted to the lower shin/Achilles instead of the whole instep.
            t=smoothstep((z-.09)/.11)*smoothstep((y+.065)/.065)
            weights={'shin':t,'foot':1-t}
        elif y<-.11:
            t=smoothstep((-y-.11)/.06)
            weights={'foot':1-t,'toes':t}
        else: weights={'foot':1}
        for name,w in weights.items():
            if w>0: groups[name].add([v.index],w,'REPLACE')
    mod=leg.modifiers.new('Skin','ARMATURE')
    mod.object=rig
    leg.parent=rig
    legs.append(leg)
    print('Refined',suffix,'triangles',sum(len(p.vertices)-2 for p in leg.data.polygons),'bridge',len(upper),len(lower))

# Fresh UV halves. Keep original skin palette and bake portable foot details.
for index,leg in enumerate(legs):
    for uv in leg.data.uv_layers.active.data: uv.uv.x=uv.uv.x*.48+.01+index*.5
coord=next(n for n in nodes if n.type=='TEX_COORD')
ramp=next(n for n in nodes if n.type=='VALTORGB')
links.new(ramp.outputs[0],bsdf.inputs['Base Color'])
image=nodes.get('FootRefinementColor')
if image is None:
    image=nodes.new('ShaderNodeTexImage')
    image.name='FootRefinementColor'
    image.image=bpy.data.images.new('BarrelMan_Skin_Refined',width=2048,height=2048,alpha=False)
nodes.active=image
# Sub-pixel sliver UVs must fall back to skin, never black between toe webs.
image.image.pixels.foreach_set([.27,.135,.073,1]*(2048*2048))
scene.render.engine='CYCLES'
scene.cycles.samples=1
scene.render.bake.use_pass_direct=False
scene.render.bake.use_pass_indirect=False
scene.render.bake.use_pass_color=True
scene.render.bake.margin=16
for index,leg in enumerate(legs):
    activate(leg)
    scene.render.bake.use_clear=False
    bpy.ops.object.bake(type='DIFFUSE')
image.image.filepath_raw=ROOT+'art_source/barrel_man/skin_basecolor.png'
image.image.file_format='PNG'
image.image.save()
# Blender can retain the previous packed PNG after rebaking an existing image.
# Refresh that payload too: glTF exports packed bytes, not the viewport buffer.
if image.image.packed_file: image.image.unpack(method='REMOVE')
image.image.reload()
image.image.pack()
links.new(image.outputs['Color'],bsdf.inputs['Base Color'])
rig['feet_revision']=2
rig.data.pose_position='POSE'
rig.animation_data.action=bpy.data.actions['idle']
scene.frame_set(1)
scene.render.engine='BLENDER_EEVEE'
activate(rig)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'art_source/barrel_man/barrel_man.blend',copy=True)
print('FEET V2 COMPLETE')
