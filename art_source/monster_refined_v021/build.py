"""Replace both hands at the wrist: connected quad cages, new skinning, 3 phalanges.

Run against v020. No source hand vertices or finger weights are retained.
"""
import bpy,bmesh,math,json
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform
from collections import Counter

OUT=Path(__file__).resolve().parent
source=bpy.data.objects['Refined020_Mesh'];oldrig=bpy.data.objects['Refined020_Rig']
oldscene=bpy.data.scenes['MONSTER_REFINED_V020']
scene=bpy.data.scenes.new('MONSTER_REFINED_V021');scene.world=oldscene.world.copy();scene.render.fps=60
bpy.context.window.scene=scene
rig=oldrig.copy();rig.data=oldrig.data.copy();rig.name='Refined021_Rig';scene.collection.objects.link(rig)
body=source.copy();body.data=source.data.copy();body.name='Refined021_Mesh';body.parent=rig;scene.collection.objects.link(body)
for mod in body.modifiers:
 if mod.type=='ARMATURE':mod.object=rig
for ob in oldscene.objects:
 if ob.name.startswith('Review020_'):
  copy=ob.copy();copy.data=ob.data.copy();copy.name=ob.name.replace('020','021');scene.collection.objects.link(copy)
  if copy.type=='CAMERA':scene.camera=copy
for t in rig.animation_data.nla_tracks:
 t.mute=True;a=t.strips[0].action.copy();a.name='raker_v021_'+t.name;t.strips[0].action=a;t.strips[0].action_slot=a.slots[0]
rig.animation_data.action=None;rig.data.pose_position='REST'
for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)

# Keep a UV lookup for the existing dirt skin, independent of old topology.
source.data.calc_loop_triangles()
uv=source.data.uv_layers.active.data
triangles=[p for p in source.data.loop_triangles if source.data.polygons[p.polygon_index].material_index==0]
source_points=[v.co.copy() for v in source.data.vertices]
uvtree=BVHTree.FromPolygons(source_points,[tuple(t.vertices) for t in triangles],all_triangles=True)
skin_image=bpy.data.images['Raker011_Albedo']
pixels=np.empty(len(skin_image.pixels),dtype=np.float32);skin_image.pixels.foreach_get(pixels);pixels=pixels.reshape(skin_image.size[1],skin_image.size[0],4)
texture_size=1024
atlas=np.zeros((texture_size,texture_size,4),dtype=np.float32)
hand_material=body.data.materials[0].copy();hand_material.name='Raker021_RebuiltHandSkin'
hand_image=bpy.data.images.new('Raker021_HandAlbedo',texture_size,texture_size,alpha=False)
for n in hand_material.node_tree.nodes:
 if n.type=='TEX_IMAGE':n.image=hand_image
body.data.materials.append(hand_material)
nail_material=bpy.data.materials.new('Raker021_WornNails');nail_material.use_nodes=True
nail_bsdf=nail_material.node_tree.nodes.get('Principled BSDF');nail_bsdf.inputs['Base Color'].default_value=(.18,.165,.125,1);nail_bsdf.inputs['Roughness'].default_value=.78
body.data.materials.append(nail_material)

def surface_color(point):
 co,normal,idx,dist=uvtree.find_nearest(point);tri=triangles[idx]
 a,b,c=[source_points[i] for i in tri.vertices];ua,ub,uc=[Vector((uv[l].uv.x,uv[l].uv.y,0)) for l in tri.loops]
 tex=barycentric_transform(co,a,b,c,ua,ub,uc)
 px=min(pixels.shape[1]-1,max(0,int(tex.x*pixels.shape[1])));py=min(pixels.shape[0]-1,max(0,int(tex.y*pixels.shape[0])))
 rgb=pixels[py,px,:3].copy()
 if pixels[py,px,3]<.5 or max(rgb)<.012:
  patch=pixels[max(0,py-4):py+5,max(0,px-4):px+5,:3];rgb=patch.reshape(-1,3).max(axis=0)
 return rgb

def paint_triangle(points,positions,colors):
 pts=np.array(points)*texture_size
 lo=np.maximum(0,np.floor(pts.min(axis=0)).astype(int));hi=np.minimum(texture_size-1,np.ceil(pts.max(axis=0)).astype(int))
 if np.any(lo>hi):return
 yy,xx=np.mgrid[lo[1]:hi[1]+1,lo[0]:hi[0]+1];p=np.stack([xx+.5,yy+.5],axis=-1)
 aa,bb,cc=pts;v0=bb-aa;v1=cc-aa;den=v0[0]*v1[1]-v0[1]*v1[0]
 if abs(den)<1e-9:return
 vv=p-aa;u=(vv[:,:,0]*v1[1]-vv[:,:,1]*v1[0])/den;v=(v0[0]*vv[:,:,1]-v0[1]*vv[:,:,0])/den
 mask=(u>=-.001)&(v>=-.001)&(u+v<=1.001)
 rgb=colors[0]*(1-u-v)[:,:,None]+colors[1]*u[:,:,None]+colors[2]*v[:,:,None]
 xyz=positions[0]*(1-u-v)[:,:,None]+positions[1]*u[:,:,None]+positions[2]*v[:,:,None]
 def noise(freq):
  q=xyz*freq;cell=np.floor(q);f=q-cell;f=f*f*(3-2*f);value=np.zeros_like(u)
  for dx in [0,1]:
   for dy in [0,1]:
    for dz in [0,1]:
     c=cell+np.array([dx,dy,dz]);hash=np.sin(c[:,:,0]*127.1+c[:,:,1]*311.7+c[:,:,2]*74.7)*43758.5453;hash=hash-np.floor(hash)
     value+=hash*(f[:,:,0] if dx else 1-f[:,:,0])*(f[:,:,1] if dy else 1-f[:,:,1])*(f[:,:,2] if dz else 1-f[:,:,2])
  return value
 rgb*=((1+(noise(170)-.5)*.7+(noise(430)-.5)*.25))[:,:,None]
 tile=atlas[lo[1]:hi[1]+1,lo[0]:hi[0]+1];tile[:,:,:3][mask]=rgb[mask];tile[:,:,3][mask]=1

finger_names=['index','middle','ring','pinky']
frames={};joints={};parts={};removed_count=0
for side in ['L','R']:
 wrist=rig.data.bones['hand_'+side].head_local.copy()
 forward=(rig.data.bones['middle_01_'+side].head_local-wrist).normalized()
 x=rig.data.bones['thumb_01_'+side].head_local-rig.data.bones['middle_01_'+side].head_local
 x=(x-forward*x.dot(forward)).normalized();palm=forward.cross(x)*(1 if side=='L' else -1)
 frames[side]=(wrist,x,forward,palm)

# Remove the entire old palm/thumb/fingers, leaving only the forearm wrist ring.
old_groups={g.index for g in body.vertex_groups if any(g.name.startswith(n+'_') for n in ['hand','thumb']+finger_names)}
bm=bmesh.new();bm.from_mesh(body.data);dw=bm.verts.layers.deform.active
old_vertices=[v for v in bm.verts if sum(w for g,w in v[dw].items() if g in old_groups)>.5]
removed_count=len(old_vertices);bmesh.ops.delete(bm,geom=old_vertices,context='VERTS')
bm.to_mesh(body.data);bm.free()

def make_hand(side):
 wrist,x,forward,palm=frames[side]
 def world(p):return wrist+x*p[0]+forward*p[1]+palm*p[2]
 verts=[];faces=[];weights=[];face_mats=[]
 def vert(p,w):
  verts.append(world(p));weights.append(w);return len(verts)-1
 def face(*ids,mat=0):faces.append(ids);face_mats.append(mat)
 def bridge(a,b,nail=False):
  for i in range(len(a)):face(a[i],a[(i+1)%len(a)],b[(i+1)%len(b)],b[i],mat=1 if nail and i in [4,5] else 0)
 # Four finger openings with real webs; palm front/back quad grids.
 # Positive X is radial (thumb). Widths are intentionally asymmetric.
 xs=[-.078,-.066,-.054,-.045,-.033,-.021,-.012,0,.012,.021,.033,.045]
 ys=[.020,.039,.062,.087,.110,.128,.146]
 widths=[.35,.60,.87,1.04,1.02,1.0,1.0]
 front={};back={};edge={}
 for row,y in enumerate(ys):
  for col,xx in enumerate(xs):
   u=col/11;xx=(xx+.014)*widths[row]-.006*min(1,row/3)
   # Thenar/hypothenar pads on the palm; tendons and knuckles on the dorsum.
   arch=math.sin(math.pi*u)
   thick=.014+.008*math.sin(math.pi*row/6)
   thenar=.010*math.exp(-((u-.88)/.24)**2-((y-.077)/.038)**2)
   hypothenar=.005*math.exp(-((u-.1)/.2)**2-((y-.082)/.05)**2)
   hollow=.005*math.exp(-((u-.5)/.24)**2-((y-.096)/.035)**2)
   yshift=-(.014*((u-.55)/.55)**2)*(row/6)**3
   fade=min(1,y/.06);fade=fade*fade*(3-2*fade);hand_weight=.45+.55*fade
   skin={('forearm_'+side):1-hand_weight,('hand_'+side):hand_weight}
   front[row,col]=vert((xx,y+yshift,thick+thenar+hypothenar-hollow),skin)
   dorsal=-thick*.8-.003*arch
   if row>=4:dorsal-=.002*math.cos(u*math.pi*8)**2
   back[row,col]=vert((xx,y+yshift,dorsal),skin)
  for end in [0,11]:
   a=verts[front[row,end]];b=verts[back[row,end]]
   local=(a+b)*.5-wrist
   edge[row,end]=vert((local.dot(x),local.dot(forward),local.dot(palm)),skin)
 for row in range(6):
  for col in range(11):
   face(front[row,col],front[row,col+1],front[row+1,col+1],front[row+1,col])
   face(back[row+1,col],back[row+1,col+1],back[row,col+1],back[row,col])
  for end in [0,11]:
   if end==11 and row in [1,2]:continue # open thumb saddle, not intersecting tubes
   face(front[row,end],front[row+1,end],edge[row+1,end],edge[row,end])
   face(edge[row,end],edge[row+1,end],back[row+1,end],back[row,end])
 # Mid-depth vertices at all distal palm boundaries form finger loops/webs.
 mids={0:edge[6,0],11:edge[6,11]}
 for col in range(1,11):
  a=(verts[front[6,col]]+verts[back[6,col]])*.5-wrist
  mids[col]=vert((a.dot(x),a.dot(forward),a.dot(palm)),{'hand_'+side:1})
 for col in [2,5,8]:
  face(front[6,col],front[6,col+1],mids[col+1],mids[col])
  face(mids[col],mids[col+1],back[6,col+1],back[6,col])

 def tube(base,centers,radii,bone_names,fractions,thumb=False):
  """Eight-sided quad tube with support rings either side of each hinge."""
  total=sum((b-a).length for a,b in zip(centers,centers[1:]))
  cumulative=[0]
  for a,b in zip(centers,centers[1:]):cumulative.append(cumulative[-1]+(b-a).length)
  cumulative=[c/total for c in cumulative]
  def evaluate(t):
   i=next((i for i in range(len(cumulative)-1) if t<=cumulative[i+1]),len(centers)-2)
   f=(t-cumulative[i])/(cumulative[i+1]-cumulative[i]);return centers[i].lerp(centers[i+1],f),(centers[i+1]-centers[i]).normalized()
  rings=[base]
  for t in fractions:
   center,direction=evaluate(t)
   normal=Vector((0,0,1));normal=(normal-direction*direction.dot(normal)).normalized()
   lateral=direction.cross(normal).normalized()
   if thumb:lateral=-lateral
   # Section parameters follow the base loop from palmar-left to palmar-right.
   section=[(-.707,.707),(0,1),(.707,.707),(1,0),(.707,-.707),(0,-1),(-.707,-.707),(-1,0)]
   # Joint bulges and shallow crease rings rather than sharp triangular elbows.
   bulge=1+.13*sum(math.exp(-((t-j)/.055)**2) for j in cumulative[1:-1])
   taper=1-.38*t
   if t>.93:taper*=max(.1,math.sqrt(max(0,1-((t-.93)/.071)**2)))
   width,depth=radii
   skin={}
   # Smoothly distribute weights through three rings around each joint.
   bone_index=min(len(bone_names)-1,next((i for i in range(len(cumulative)-1) if t<=cumulative[i+1]),len(bone_names)-1))
   skin[bone_names[bone_index]]=1
   for j in range(1,len(bone_names)):
    if abs(t-cumulative[j])<.065:
     f=max(0,min(1,(t-cumulative[j]+.065)/.13));f=f*f*(3-2*f)
     skin={bone_names[j-1]:1-f,bone_names[j]:f}
   if t<.12:
    f=max(0,min(1,t/.12));skin={bone_names[0]:f,'hand_'+side:1-f}
   ring=[]
   for section_index,(sx,sz) in enumerate(section):
    local=center+lateral*(sx*width*taper*bulge)+normal*(sz*depth*taper*bulge)
    # Dorsal nail bed is sculpted in the mesh, palmar pad remains rounded.
    if sz<-.6 and .82<t<.98:local-=normal*.0015
    if sz>.6:
     local-=normal*(.0015*sum(math.exp(-((t-j)/.025)**2) for j in cumulative[1:-1]))
    if thumb and t<.3:
     # Leave the side opening along its normal before turning into the
     # thumb's oblique axis. Rotating a full ring at the saddle intersects it.
     seed=verts[base[section_index]]-wrist
     seed=Vector((seed.dot(x),seed.dot(forward),seed.dot(palm)))
     blend=min(1,t/.3);blend=blend*blend*(3-2*blend)
     local=(seed+center-centers[0]).lerp(local,blend)
    ring.append(vert(local,skin))
   bridge(rings[-1],ring,nail=.85<=t<=.994);rings.append(ring)
  # Rounded distal cap, with a closed triangle fan.
  tip,direction=evaluate(1);cap=vert(tip+direction*.0005,{bone_names[-1]:1})
  for i in range(8):face(rings[-1][i],rings[-1][(i+1)%8],cap)
  return rings

 lengths={'index':.186,'middle':.205,'ring':.194,'pinky':.158}
 radii={'index':(.014,.0125),'middle':(.0145,.013),'ring':(.0135,.012),'pinky':(.0115,.0105)}
 spread={'index':.025,'middle':0,'ring':-.02,'pinky':-.09}
 for name,col in [('pinky',0),('ring',3),('middle',6),('index',9)]:
  base=[front[6,col],front[6,col+1],front[6,col+2],mids[col+2],back[6,col+2],back[6,col+1],back[6,col],mids[col]]
  point=sum((verts[v] for v in base),Vector())/8-wrist
  p=Vector((point.dot(x),point.dot(forward),point.dot(palm)))
  direction=Vector((spread[name],1,0)).normalized();length=lengths[name]
  centers=[p,p+direction*length*.45,p+direction*length*.77,p+direction*length]
  names=[name+'_%02d_'%i+side for i in [1,2,3]]
  joints.update({n:(world(centers[i]),world(centers[i+1]),palm) for i,n in enumerate(names)})
  tube(base,centers,radii[name],names,[.035,.10,.25,.38,.42,.45,.49,.55,.66,.72,.77,.81,.87,.93,.97,.994])
 # Thumb emerges from the radial side of the PALM, including a broad thenar saddle.
 base=[front[1,11],front[2,11],front[3,11],edge[3,11],back[3,11],back[2,11],back[1,11],edge[1,11]]
 p=sum((verts[v] for v in base),Vector())/8-wrist
 p=Vector((p.dot(x),p.dot(forward),p.dot(palm)))
 centers=[p,Vector((.100,.101,.009)),Vector((.132,.153,.014))]
 names=['thumb_01_'+side,'thumb_02_'+side]
 joints.update({n:(world(centers[i]),world(centers[i+1]),palm) for i,n in enumerate(names)})
 # Radial extrusion has opposite loop orientation to the distal finger holes.
 tube(base,centers,(.023,.016),names,[.055,.16,.30,.43,.49,.55,.64,.75,.85,.93,.97,.994],True)
 data=bpy.data.meshes.new('AnatomicalHandCage_'+side);data.from_pydata(verts,[],faces);data.update()
 data.materials.append(hand_material);data.materials.append(nail_material)
 for poly,mat in zip(data.polygons,face_mats):poly.material_index=mat
 ob=bpy.data.objects.new('NewHand_'+side,data);scene.collection.objects.link(ob)
 for g in rig.data.bones:ob.vertex_groups.new(name=g.name)
 for name in joints:
  if name not in ob.vertex_groups:ob.vertex_groups.new(name=name)
 for i,skin in enumerate(weights):
  for name,value in skin.items():
   if value>0:ob.vertex_groups[name].add([i],value,'REPLACE')
 marker=ob.vertex_groups.new(name='RebuiltHand_'+side);marker.add(list(range(len(verts))),1,'REPLACE')
 bm=bmesh.new();bm.from_mesh(data)
 bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_edges],context='VERTS')
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
 for o in scene.objects:o.select_set(False)
 ob.select_set(True);bpy.context.view_layer.objects.active=ob
 sub=ob.modifiers.new('Anatomical quad smoothing','SUBSURF');sub.levels=1
 bpy.ops.object.modifier_apply(modifier=sub.name)
 for p in ob.data.polygons:p.use_smooth=True
 # New UV islands and a new atlas. Sample old dirt colors spatially, not old UV
 # triangles (which would interpolate across unrelated islands and leave bands).
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
 bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.018)
 bpy.ops.object.mode_set(mode='OBJECT')
 layer=ob.data.uv_layers.active
 for loop in layer.data:
  loop.uv.x=loop.uv.x*.48+(.01 if side=='L' else .51);loop.uv.y=loop.uv.y*.88+.11
 colors=np.array([surface_color(v.co) for v in ob.data.vertices])
 ob.data.calc_loop_triangles()
 for tri in ob.data.loop_triangles:
  paint_triangle([layer.data[i].uv[:] for i in tri.loops],np.array([ob.data.vertices[i].co[:] for i in tri.vertices]),colors[list(tri.vertices)])
 parts[side]=ob
 return ob

for side in ['L','R']:make_hand(side)
# Replace finger rig, preserving wrists and all upstream animation contracts.
for o in scene.objects:o.select_set(False)
rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
for name,(head,tail,palm) in joints.items():
 b=rig.data.edit_bones.get(name) or rig.data.edit_bones.new(name)
 b.head=head;b.tail=tail;b.align_roll(palm);b.use_deform=True
 number=int(name.split('_')[-2]);stem=name.rsplit('_',2)[0];side=name[-1]
 b.parent=rig.data.edit_bones['hand_'+side if number==1 else stem+'_%02d_'%(number-1)+side]
 b.use_connect=number>1
bpy.ops.object.mode_set(mode='OBJECT')

# Join new hands, then stitch each open collar to the untouched eight-point wrist.
for o in scene.objects:o.select_set(False)
body.select_set(True)
for ob in parts.values():ob.select_set(True)
bpy.context.view_layer.objects.active=body;bpy.ops.object.join()
bm=bmesh.new();bm.from_mesh(body.data);dw=bm.verts.layers.deform.active
uvlayer=bm.loops.layers.uv.active
for side in ['L','R']:
 wrist,x,forward,palm=frames[side];marker=body.vertex_groups['RebuiltHand_'+side].index
 boundary=[v for v in bm.verts if v.is_boundary and (v.co-wrist).length<.09]
 old=[v for v in boundary if v[dw].get(marker,0)<.5];new=[v for v in boundary if v[dw].get(marker,0)>.5]
 assert len(old)==8 and len(new)>8,(side,len(old),len(new))
 def angle(v):p=v.co-wrist;return math.atan2(p.dot(palm),p.dot(x))%(2*math.pi)
 old.sort(key=angle);new.sort(key=angle)
 # Zipper two ordered cycles by their angular coordinates. Preserves all forearm vertices.
 i=j=0
 while i<len(old) or j<len(new):
  ni=angle(old[(i+1)%len(old)])+(2*math.pi if i+1>=len(old) else 0) if i<len(old) else 1e9
  nj=angle(new[(j+1)%len(new)])+(2*math.pi if j+1>=len(new) else 0) if j<len(new) else 1e9
  if ni<nj:vs=[old[i%len(old)],old[(i+1)%len(old)],new[j%len(new)]];i+=1
  else:vs=[old[i%len(old)],new[(j+1)%len(new)],new[j%len(new)]];j+=1
  face=bm.faces.new(vs);face.smooth=True;face.material_index=4
  angles=[angle(v) for v in vs]
  if max(angles)-min(angles)>math.pi:angles=[a+2*math.pi if a<math.pi else a for a in angles]
  coords=[(a/(2*math.pi)*.48+(.01 if side=='L' else .51),.015+min(.03,max(0,(v.co-wrist).dot(forward)))/.03*.075) for a,v in zip(angles,vs)]
  for loop,tex in zip(face.loops,coords):loop[uvlayer].uv=tex
  paint_triangle(coords,np.array([v.co[:] for v in vs]),np.array([surface_color(v.co) for v in vs]))
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(body.data);bm.free();body.data.update()
# Eight-pixel gutters on the new atlas, including the rebuilt wrist collar.
for iteration in range(8):
 mask=atlas[:,:,3]>.5;total=np.zeros_like(atlas[:,:,:3]);count=np.zeros_like(atlas[:,:,3])
 for dy,dx in [(1,0),(-1,0),(0,1),(0,-1)]:
  valid=np.roll(mask,(dy,dx),(0,1));total+=np.roll(atlas[:,:,:3],(dy,dx),(0,1))*valid[:,:,None];count+=valid
 fill=(~mask)&(count>0);atlas[:,:,:3][fill]=total[fill]/count[fill,None];atlas[:,:,3][fill]=1
atlas[:,:,3]=1
hand_image.pixels.foreach_set(atlas.ravel());hand_image.filepath_raw=str(OUT/'hand_albedo.png');hand_image.file_format='PNG';hand_image.save();hand_image.pack()

# Author new hand posing on the new three-joint anatomy, all 41 private actions.
rig.data.pose_position='POSE'
for track in rig.animation_data.nla_tracks:
 clip=track.name;a=track.strips[0].action;rig.animation_data.action=a;rig.animation_data.action_slot=a.slots[0]
 end=int(a.frame_range[1])
 for frame in range(end+1):
  scene.frame_set(frame)
  u=frame/max(1,end)
  for side in ['L','R']:
   wave=math.sin(u*2*math.pi+(0 if side=='L' else math.pi))
   flex=[8,20,10];thumb=[0,8]
   if clip in ['walk','crouch_walk']:flex=[9+wave*2,22+wave*3,12+wave*2]
   if clip in ['chase','sprint']:flex=[12+wave*3,28+wave*4,16+wave*3]
   if clip in ['climb_loop','hang_idle','attack_door','mantle','roof_settle','slip_loop']:flex=[12,36,22];thumb=[5,18]
   if clip.startswith('attack') or clip=='crouch_attack':flex=[13,32,20]
   if clip.startswith('grab_'):
    phase=clip.rsplit('_',1)[1]
    blend=u*u*(3-2*u) if phase=='reach' else (1-u*u*(3-2*u) if phase in ['release','escape','miss'] else 1)
    flex=[8+10*blend,20+25*blend,10+20*blend];thumb=[8*blend,8+16*blend]
   for k,name in enumerate(finger_names):
    stagger=[-1,0,2,4][k]
    for n in [1,2,3]:
     b=rig.pose.bones[name+'_%02d_'%n+side];b.rotation_mode='QUATERNION'
     b.rotation_quaternion=Quaternion((1,0,0),math.radians(flex[n-1]+stagger*.4))
     b.location=Vector();b.scale=Vector((1,1,1))
     for path in ['rotation_quaternion','location','scale']:b.keyframe_insert(data_path=path,frame=frame)
   for n in [1,2]:
    b=rig.pose.bones['thumb_%02d_'%n+side];b.rotation_mode='QUATERNION'
    b.rotation_quaternion=Quaternion((1,0,0),math.radians(thumb[n-1]));b.location=Vector();b.scale=Vector((1,1,1))
    for path in ['rotation_quaternion','location','scale']:b.keyframe_insert(data_path=path,frame=frame)
 print('AUTHORED',clip,flush=True)
rig.animation_data.action=next(t.strips[0].action for t in rig.animation_data.nla_tracks if t.name=='idle')
rig.animation_data.action_slot=rig.animation_data.action.slots[0];scene.frame_set(0)
scene['revision']='v021 complete hand replacement: quad palm/webs/thenar, 3 phalanges, new weights and actions'
body['hand_rebuild']='All old palm/thumb/finger vertices removed at wrist; RebuiltHand_L/R tag replacement vertices'
body['removed_old_hand_vertices']=removed_count
body.data.calc_loop_triangles()
report={'removed_old_hand_vertices':removed_count,'new_hand_vertices':{},'deform_bones':sum(b.use_deform for b in rig.data.bones),'source_vertices':len(body.data.vertices),'triangles':len(body.data.loop_triangles)}
for side in ['L','R']:
 group=body.vertex_groups['RebuiltHand_'+side].index
 report['new_hand_vertices'][side]=sum(any(g.group==group and g.weight>.5 for g in v.groups) for v in body.data.vertices)
(OUT/'rebuild.json').write_text(json.dumps(report,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'monster_refined_v021.blend'))
print('REBUILT',report,flush=True)
