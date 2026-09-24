"""Author the initial bunker kit. Existing scenes are never overwritten.
Future rooms are edited as .tscn/.tres resources; the runtime has no size table.
"""
from pathlib import Path
import math
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'world/poi_kit/rooms/bunker'
CAT = ROOT / 'world/instances/catalog/bunker'

def vec(p): return 'Vector3(' + ', '.join(f'{x:.6f}' for x in p) + ')'

def build(identifier, w, d, h, group, variant=0, role='ordinary'):
    ext = ['[gd_scene format=3]', '[ext_resource type="Script" path="res://world/poi_kit/poi_room.gd" id="room"]', '[ext_resource type="Script" path="res://world/poi_kit/poi_door_socket.gd" id="socket"]']
    for name in ['concrete', 'floor', 'olive', 'steel', 'stripe', 'lamp']:
        ext.append(f'[ext_resource type="Material" path="res://world/poi_kit/materials/bunker/{name}.tres" id="{name}"]')
    res, nodes = [], [f'[node name="{identifier.title()}" type="Node3D"]\nscript = ExtResource("room")\nroom_id = &"{identifier}"\nfootprint = Vector2({w}, {d})\nclear_height = {h}\ncategory = &"{group}"']
    for layer in ['Visuals','Collision','DoorSockets','Furnishings','Walkway']:
        nodes.append(f'[node name="{layer}" type="Node3D" parent="."]')
    serial = 0
    sockets = []
    def box(label, size, pos, material='concrete', collision=True, rotation=None, layer='Visuals'):
        nonlocal serial
        # Reserve full doorway width plus a 2 m approach on both sides.
        if collision and label in ('Locker','Pier','Column'):
            for sid,side,offset,y in sockets:
                if y != 0: continue
                lateral = abs(pos[0]-offset) if side in ('north','south') else abs(pos[2]-offset)
                half = size[0]/2 if side in ('north','south') else size[2]/2
                inward = {'north':pos[2]+d/2,'south':d/2-pos[2],'east':w/2-pos[0],'west':pos[0]+w/2}[side]
                deep = size[2]/2 if side in ('north','south') else size[0]/2
                if lateral < 1.35+half and inward < 2.0+deep: return
        serial += 1
        key = f'b{serial}'
        transform = 'position = ' + vec(pos) + (('\nrotation = '+vec(rotation)) if rotation else '')
        res.append(f'[sub_resource type="BoxMesh" id="{key}m"]\nsize = {vec(size)}')
        nodes.append(f'[node name="{label}{serial}" type="MeshInstance3D" parent="{layer}"]\n{transform}\nmesh = SubResource("{key}m")\nmaterial_override = ExtResource("{material}")')
        if collision:
            res.append(f'[sub_resource type="BoxShape3D" id="{key}s"]\nsize = {vec(size)}')
            nodes.append(f'[node name="{label}{serial}" type="StaticBody3D" parent="Collision"]\n{transform}')
            nodes.append(f'[node name="Shape" type="CollisionShape3D" parent="Collision/{label}{serial}"]\nshape = SubResource("{key}s")')
    box('Floor',(w,.25,d),(0,-.125,0),'floor')
    box('Ceiling',(w,.25,d),(0,h+.125,0))
    # Each wall lives wholly INSIDE its occupancy. Adjacent rooms never share visible faces.
    sockets = []
    if role == 'stairs': sockets = [('upper','north',0,4.5),('lower','south',0,0)]
    elif role == 'entry': sockets = [('north','north',0,0),('east','east',0,0),('west','west',0,0)]
    elif group in ('passage','corridor'):
        sockets = [('north','north',0,0),('south','south',0,0)] if variant==0 else [('north','north',0,0),('east','east',d/2-1.8,0)]
        if group=='corridor' and variant==1: sockets.append(('west','west',-d/2+1.8,0))
    elif variant == 0:
        sockets = [(side,side,0,0) for side in ['north','south','east','west']]
    elif variant == 1:
        sockets = [('north','north',-w/2+1.8,0),('south','south',w/2-1.8,0),('east','east',0,0)]
    else:
        sockets = [('north','north',0,0),('west','west',-d/2+1.5,0),('west_back','west',d/2-1.5,0)]
    frames = {}
    for side in ['north','south','east','west']:
        horizontal = side in ['north','south']
        length = w if horizontal else d
        boundary = (-d/2 if side=='north' else d/2) if horizontal else (-w/2 if side=='west' else w/2)
        sign = -1 if side in ['north','west'] else 1
        openings = sorted([s for s in sockets if s[1]==side],key=lambda s:s[2])
        def wall_segment(start,end,bottom,top,label='Wall',material='concrete',thickness=.24,inset=.12,collision=True):
            if end-start<.001 or top-bottom<.001: return
            size=(end-start,top-bottom,thickness) if horizontal else (thickness,top-bottom,end-start)
            pos=((start+end)/2,(bottom+top)/2,boundary-sign*inset) if horizontal else (boundary-sign*inset,(bottom+top)/2,(start+end)/2)
            box(label,size,pos,material,collision)
        cursor = -length/2
        for sid,_,offset,y in openings:
            wall_segment(cursor,offset-1.2,0,h)
            wall_segment(cursor+.02,offset-1.22,.15,1.25,'Paint','olive',.012,.247,False)
            wall_segment(offset-1.2,offset+1.2,y+2.8,h,'Lintel')
            wall_segment(offset-1.2,offset+1.2,0,y,'LowerWall')
            # Frame only surrounds the opening, never narrows it.
            frames[sid] = [f'Jamb{serial+1}',f'Jamb{serial+2}',f'Header{serial+3}']
            for edge in [offset-1.25,offset+1.25]: wall_segment(edge-.04,edge+.04,y,y+2.85,'Jamb','steel',.08,.27,False)
            wall_segment(offset-1.29,offset+1.29,y+2.8,y+2.88,'Header','steel',.08,.27,False)
            cursor=offset+1.2
        wall_segment(cursor,length/2,0,h)
        wall_segment(cursor+.02,length/2-.02,.15,1.25,'Paint','olive',.012,.247,False)
    for sid,side,offset,y in sockets:
        pos = {'north':(offset,y,-d/2),'south':(offset,y,d/2),'east':(w/2,y,offset),'west':(-w/2,y,offset)}[side]
        yaw = {'north':0,'south':math.pi,'east':-math.pi/2,'west':math.pi/2}[side]
        nodes.append(f'[node name="{sid}" type="Marker3D" parent="DoorSockets"]\nposition = {vec(pos)}\nrotation = Vector3(0, {yaw}, 0)\nscript = ExtResource("socket")\nsocket_id = &"{sid}"\ninterface_type = &"bunker_240"\nopening = Vector2(2.4, 2.8)')
        nodes[-1] += '\nframe_nodes = Array[NodePath]([' + ', '.join(f'NodePath("../../Visuals/{name}")' for name in frames[sid]) + '])'
    if role=='stairs':
        # 4.5 m rise / 9 m run. Continuous collision ramp, shallow visible tread nosings.
        box('UpperLanding',(w,.25,1.5),(0,4.375,-5.25),'floor')
        points = [(x,y,z) for x in [-1.25,1.25] for y,z in [(-.25,4.5),(-.25,-4.5),(4.5,-4.5),(0,4.5)]]
        res.append('[sub_resource type="ConvexPolygonShape3D" id="ramp"]\npoints = PackedVector3Array('+', '.join(str(n) for p in points for n in p)+')')
        nodes.append('[node name="Ramp" type="StaticBody3D" parent="Collision"]')
        nodes.append('[node name="Shape" type="CollisionShape3D" parent="Collision/Ramp"]\nshape = SubResource("ramp")')
        for i in range(30): box('Tread',(2.5,.15,.30),(0,(i+.5)*.15,4.35-i*.3),'steel',False)
        for x in [-1.42,1.42]:
            box('Rail',(.08,.08,math.sqrt(101.25)),(x,3.3,0),'stripe',True,(math.atan(.5),0,0))
            for z in [-4.5,-1.5,1.5,4.5]: box('Post',(.07,1,.07),(x,(4.5-z)*.5+.5,z),'steel')
        for x in [-2.13,2.13]: box('LandingRail',(1.5,1,.10),(x,5,-4.5),'steel')
        for i,p in enumerate([(0,0,5.4),(0,0,4.5),(0,4.5,-4.5),(0,4.5,-5.4)]):
            nodes.append(f'[node name="Route{i}" type="Marker3D" parent="Walkway"]\nposition = {vec(p)}')
    else:
        # Every central axis and every authored door approach remains clear.
        if w>=6:
            for i,x in enumerate([-w/2+.65,w/2-.65]):
                z = -d/2+.65 if i==0 else d/2-.65
                box('Locker',(.65,1.85,.65),(x,.925,z),'olive',True,layer='Furnishings')
                if nodes[-1].startswith('[node name="Shape"') and 'Locker' in nodes[-1]: box('LockerHandle',(.05,.25,.035),(x,1.05,z+.345),'steel',False,layer='Furnishings')
        if w>=9:
            for x in [-w/2+.45,w/2-.45]:
                for z in [-d/4,d/4]: box('Pier',(.42,h,.48),(x,h/2,z))
            for z in [-d/4,d/4]: box('Beam',(w,.24,.4),(0,h-.12,z),'concrete',False)
        if variant==2 and w>=12:
            # Interior columns are outside the central cross and offset door corridors.
            for x in [-3,3]:
                for z in [-4,4]: box('Column',(.5,h,.5),(x,h/2,z))
        nodes.append('[node name="Center" type="Marker3D" parent="Walkway"]')
    # Services stay overhead. Sparse, steady lighting; no flickering animation.
    for x in [-w/2+.4,-w/2+.58]: box('Pipe',(.08,.08,d-.6),(x,h-.4,0),'steel',False)
    lamp_z = [0] if d<10 else [-d/3,d/3]
    for i,z in enumerate(lamp_z):
        ly = (6.8 if z<0 else 2.8) if role=='stairs' else h-.25
        box('LampHousing',(1.2,.10,.28),(0,ly,z),'steel',False)
        box('LampTube',(1.05,.05,.17),(0,ly-.065,z),'lamp',False)
        nodes.append(f'[node name="Light{i}" type="OmniLight3D" parent="Visuals"]\nposition = {vec((0,ly-.25,z))}\nlight_color = Color(0.82, 0.86, 0.72, 1)\nlight_energy = 1.5\nomni_range = {max(w,d)/2+2}\nomni_attenuation = 1.3')
    # Labels use a side wall, clear of doors, and never float across an opening.
    nodes.append(f'[node name="Stencil" type="Label3D" parent="Visuals"]\nposition = {vec((0,2.1,d/2-.255))}\nrotation = Vector3(0, {math.pi}, 0)\ntext = "{identifier.upper().replace("_"," / ")}"\nfont_size = 32\npixel_size = 0.005\nmodulate = Color(0.75,0.74,0.57,1)') if role=='entry' else None
    if role=='entry':
        nodes.append('[node name="Spawn" type="Marker3D" parent="Walkway"]\nposition = Vector3(0, 0.05, 1.5)')
        nodes.append('[node name="Exit" type="Marker3D" parent="Walkway"]\nposition = Vector3(0, 0, 2.72)\nrotation = Vector3(0, 3.14159265359, 0)')
        box('ExitLeaf',(2.35,2.8,.08),(0,1.4,2.73),'steel',False)
    return '\n\n'.join(ext+res+nodes)+'\n'

def main():
    if OUT.exists() and any(OUT.iterdir()): raise SystemExit('Bunker kit exists; edit scenes/resources directly.')
    OUT.mkdir(parents=True,exist_ok=True); CAT.mkdir(parents=True,exist_ok=True)
    mats=ROOT/'world/poi_kit/materials/bunker'; mats.mkdir(parents=True,exist_ok=True)
    colors={'concrete':(.55,.56,.50),'floor':(.32,.34,.30),'olive':(.22,.28,.20),'steel':(.12,.15,.14),'stripe':(.56,.47,.26),'lamp':(.8,.87,.66)}
    for name,c in colors.items():
        extra='\nemission_enabled = true\nemission = Color(0.65, 0.72, 0.5, 1)\nemission_energy_multiplier = 1.4' if name=='lamp' else ''
        texture = ''
        if name in ('concrete','floor'):
            texture = '[ext_resource type="Texture2D" path="res://assets/materials/poi_kit/concrete_albedo.png" id="1"]\n\n'
            extra += '\nalbedo_texture = ExtResource("1")\nuv1_scale = Vector3(0.5, 0.5, 0.5)\nuv1_triplanar = true'
        (mats/(name+'.tres')).write_text(f'[gd_resource type="StandardMaterial3D" format=3]\n\n{texture}[resource]\nalbedo_color = Color({c[0]}, {c[1]}, {c[2]}, 1)\nroughness = 0.9{extra}\n',encoding='utf-8')
    definitions=[]
    for group,w,d,h,n in [('passage',3,6,3,2),('corridor',3,12,3,2),('small',6,6,3.6,3),('medium',6,9,3.6,2),('large',9,12,3.6,2),('hall',12,18,4,3)]:
        for i in range(n): definitions.append((f'{group}_{i+1:02}',w,d,h,group,i,'ordinary'))
    definitions += [('entry',6,6,3.6,'entry',0,'entry'),('stairs',6,12,7.5,'stairs',0,'stairs')]
    for args in definitions:
        identifier,w,d,h,group,variant,role=args
        path=OUT/(identifier+'.tscn')
        if path.exists(): raise SystemExit(f'Refusing to overwrite authored scene {path}')
        path.write_text(build(*args),encoding='utf-8')
        (CAT/(identifier+'.tres')).write_text(f'[gd_resource type="Resource" script_class="InteriorRoomDefinition" format=3]\n\n[ext_resource type="Script" path="res://world/instances/room_definition.gd" id="1"]\n[ext_resource type="PackedScene" path="res://world/poi_kit/rooms/bunker/{identifier}.tscn" id="2"]\n\n[resource]\nscript = ExtResource("1")\nid = &"{identifier}"\nscene = ExtResource("2")\nrole = &"{role}"\nselection_group = &"{group}"\n',encoding='utf-8')
    ext=['[gd_resource type="Resource" script_class="InteriorProfile" format=3]','[ext_resource type="Script" path="res://world/instances/interior_profile.gd" id="1"]','[ext_resource type="Script" path="res://world/instances/room_definition.gd" id="room_script"]']
    for args in definitions: ext.append(f'[ext_resource type="Resource" path="res://world/instances/catalog/bunker/{args[0]}.tres" id="{args[0]}"]')
    ext.append('[resource]\nscript = ExtResource("1")\nrooms = Array[ExtResource("room_script")](['+', '.join(f'ExtResource("{d[0]}")' for d in definitions)+'])')
    (CAT.parent/'bunker.tres').write_text('\n\n'.join(ext)+'\n',encoding='utf-8')
if __name__=='__main__': main()
