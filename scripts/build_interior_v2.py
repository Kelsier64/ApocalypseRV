"""One-time authored graybox source. Refuses to replace delivered scenes."""
from pathlib import Path
import math

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'world/poi_kit/rooms/v2'
CAT = ROOT / 'world/instances/catalog'

def v(values):
    return 'Vector3(' + ', '.join(f'{n:.6f}' for n in values) + ')'

def build(id, width=9, depth=9, height=5.5, title='', arrangement=0):
    ext = ['[gd_scene format=3]',
        '[ext_resource type="Script" path="res://world/poi_kit/poi_room.gd" id="room"]',
        '[ext_resource type="Script" path="res://world/poi_kit/poi_door_socket.gd" id="socket"]',
        '[ext_resource type="Script" path="res://world/poi_kit/poi_loot_point.gd" id="loot"]',
        '[ext_resource type="PackedScene" path="res://props/scrap.tscn" id="scrap"]']
    for name in ['shelf', 'workbench', 'cabinet']:
        ext.append(f'[ext_resource type="PackedScene" path="res://world/poi_kit/furniture/{name}.tscn" id="{name}"]')
    res, nodes = [], []
    colors = {'wall': (0.23, .27, .28), 'floor': (.14, .17, .18), 'steel': (.12, .16, .18), 'accent': (.66, .39, .13)}
    for name, color in colors.items():
        res.append(f'[sub_resource type="StandardMaterial3D" id="{name}"]\nalbedo_color = Color({color[0]}, {color[1]}, {color[2]}, 1)\nroughness = 0.88')
    nodes.append(f'[node name="{id.title()}" type="Node3D"]\nscript = ExtResource("room")\nroom_id = &"v2_{id}"\nsize_cells = Vector2i({width//9}, {depth//9})\nclear_height = {height}\ncategory = &"{id}"')
    for layer in ['Visuals', 'Collision', 'DoorSockets', 'Furnishings', 'LootSpawns', 'EnemySpawns', 'Walkway']:
        nodes.append(f'[node name="{layer}" type="Node3D" parent="."]')
    serial = 0
    def box(label, size, pos, material='wall', rotation=None, collision=True):
        nonlocal serial
        serial += 1
        key = f'b{serial}'
        res.append(f'[sub_resource type="BoxMesh" id="{key}m"]\nsize = {v(size)}')
        transform = f'position = {v(pos)}' + (f'\nrotation = {v(rotation)}' if rotation else '')
        nodes.append(f'[node name="{label}{serial}" type="MeshInstance3D" parent="Visuals"]\n{transform}\nmesh = SubResource("{key}m")\nmaterial_override = SubResource("{material}")')
        if collision:
            res.append(f'[sub_resource type="BoxShape3D" id="{key}s"]\nsize = {v(size)}')
            nodes.append(f'[node name="{label}{serial}" type="StaticBody3D" parent="Collision"]\n{transform}')
            nodes.append(f'[node name="Shape" type="CollisionShape3D" parent="Collision/{label}{serial}"]\nshape = SubResource("{key}s")')
    box('Floor', (width, .25, depth), (0, -.125, 0), 'floor')
    box('Ceiling', (width, .25, depth), (0, height+.125, 0))
    sockets = [('north', (0, 0, -depth/2), 0), ('east', (width/2, 0, 0), -math.pi/2), ('south', (0, 0, depth/2), math.pi), ('west', (-width/2, 0, 0), math.pi/2)]
    if id == 'entry': sockets = [s for s in sockets if s[0] != 'south']
    if id == 'stairs': sockets = [('north', (0, 6, -depth/2), 0), ('south', (0, 0, depth/2), math.pi)]
    for side, size, center in [('north', width, (0,0,-depth/2)), ('south', width, (0,0,depth/2)), ('east', depth, (width/2,0,0)), ('west', depth, (-width/2,0,0))]:
        horizontal = side in ['north','south']
        socket = next((s for s in sockets if s[0] == side), None)
        if socket:
            y = socket[1][1]
            for sign in [-1, 1]:
                p = list(center); p[0 if horizontal else 2] = sign*(size+3)/4; p[1] = height/2
                box('Wall', ((size-3)/2,height,.24) if horizontal else (.24,height,(size-3)/2), p)
            top = height-y-3.5
            p = list(center); p[1] = y+3.5+top/2
            box('Lintel', (3,top,.24) if horizontal else (.24,top,3), p)
            if y:
                p = list(center); p[1]=y/2
                box('LowerWall', (3,y,.24) if horizontal else (.24,y,3), p)
        else:
            p = list(center); p[1] = height/2
            box('Wall', (size,height,.24) if horizontal else (.24,height,size), p)
    for side, pos, yaw in sockets:
        nodes.append(f'[node name="{side}" type="Marker3D" parent="DoorSockets"]\nposition = {v(pos)}\nrotation = Vector3(0, {yaw}, 0)\nscript = ExtResource("socket")\nsocket_id = &"{side}"')
    if id == 'stairs':
        box('Landing', (width,.25,3), (0,5.875,-7.5), 'floor')
        # Continuous collision wedge; visible treads do not force jumping.
        points = [(x,y,z) for x in [-1.7,1.7] for y,z in [(-.25,6),(-.25,-6),(6,-6),(0,6)]]
        res.append('[sub_resource type="ConvexPolygonShape3D" id="ramp"]\npoints = PackedVector3Array(' + ', '.join(str(n) for p in points for n in p) + ')')
        nodes.append('[node name="Ramp" type="StaticBody3D" parent="Collision"]')
        nodes.append('[node name="Shape" type="CollisionShape3D" parent="Collision/Ramp"]\nshape = SubResource("ramp")')
        for i in range(24):
            box('Tread', (3.4,.25,.5), (0,(i+.5)*.25,5.75-i*.5), 'steel', collision=False)
        for x in [-1.85,1.85]:
            box('Rail', (.12,1.0,math.sqrt(180)), (x,3.6,0), 'accent', (math.atan(.5),0,0))
        # Upper landing rail leaves central stair approach open.
        for x in [-3.2,3.2]: box('LandingRail',(2.4,1,.15),(x,6.6,-6),'accent')
        for idx, p in enumerate([(0,0,7.5),(0,0,6),(0,6,-6),(0,6,-7.5)]):
            nodes.append(f'[node name="Route{idx}" type="Marker3D" parent="Walkway"]\nposition = {v(p)}')
    else:
        corners = [(-width/2+1.6,0,-depth/2+1.3),(width/2-1.6,0,depth/2-1.3)]
        for i, pos in enumerate(corners):
            furniture = ['shelf','workbench','cabinet'][(arrangement+i)%3]
            nodes.append(f'[node name="Furniture{i}" parent="Furnishings" instance=ExtResource("{furniture}")]\nposition = {v(pos)}\nrotation = Vector3(0, {0 if i == 0 else math.pi}, 0)')
        if id in ['workshop','pump','atrium']:
            for sign in [-1,1]: box('Machine',(1.2,2.1,2.4),(sign*width/4,1.05,sign*(depth/2-1.6)),'steel')
        if id == 'atrium':
            # High perimeter gallery is decorative; usable route remains on floor.
            for x in [-7,7]: box('OverheadGantry',(2,.3,depth),(x,6,0),'steel')
        nodes.append('[node name="Supply" type="Marker3D" parent="LootSpawns"]\nposition = Vector3(-2, 0.4, 1.5)\nscript = ExtResource("loot")\npoint_id = &"floor_supply"\nspawn_chance = 1.0\ncandidates = Array[PackedScene]([ExtResource("scrap")])')
    nodes.append('[node name="Enemy" type="Marker3D" parent="EnemySpawns"]\nposition = Vector3(0, 0.1, -2)')
    nodes.append(f'[node name="Title" type="Label3D" parent="Visuals"]\nposition = Vector3(0, 3, {-depth/2+.2})\ntext = "{title}"\nfont_size = 52\npixel_size = 0.008\nmodulate = Color(0.8, 0.66, 0.34, 1)')
    nodes.append('[node name="Light" type="OmniLight3D" parent="Visuals"]\nposition = Vector3(0, 3.8, 0)\nlight_color = Color(0.76, 0.83, 0.82, 1)\nlight_energy = 1.6\nomni_range = 11.0')
    if id == 'stairs': nodes.append('[node name="UpperLight" type="OmniLight3D" parent="Visuals"]\nposition = Vector3(0, 9.5, -6)\nlight_color = Color(0.85, 0.65, 0.36, 1)\nlight_energy = 1.8\nomni_range = 12.0')
    return '\n\n'.join(ext+res+nodes)+'\n'

def main():
    definitions = [('entry',9,9,5.5,'RECEPTION / HIGHWAY',0),('junction',9,9,5.5,'SERVICE CROSSING',1),('utility',9,9,5.5,'ELECTRICAL SERVICE',2),('store',9,9,5.5,'CONSUMABLES',0),('workshop',18,9,5.5,'REPAIR BAY',1),('gallery',9,18,5.5,'SERVICE GALLERY',2),('pump',18,18,5.5,'PUMP MACHINERY',1),('control',9,9,5.5,'CONTROL ROOM',2),('atrium',18,18,11.5,'TURBINE HALL',0),('stairs',9,18,11.5,'STAIRS / LEVEL 1 - 2',0),('depot',9,9,5.5,'RESTRICTED / PARTS DEPOT',0)]
    OUT.mkdir(parents=True,exist_ok=True); CAT.mkdir(parents=True,exist_ok=True)
    for definition in definitions:
        path=OUT/(definition[0]+'.tscn')
        if path.exists(): raise SystemExit(f'Refusing to overwrite {path}')
        path.write_text(build(*definition),encoding='utf-8')
        id=definition[0]
        weight=0 if id in ['entry','stairs','depot'] else (0.3 if id=='atrium' else 1.0)
        (CAT/(id+'.tres')).write_text(f'[gd_resource type="Resource" script_class="InteriorRoomDefinition" format=3]\n\n[ext_resource type="Script" path="res://world/instances/room_definition.gd" id="1"]\n[ext_resource type="PackedScene" path="res://world/poi_kit/rooms/v2/{id}.tscn" id="2"]\n\n[resource]\nscript = ExtResource("1")\nid = &"{id}"\nscene = ExtResource("2")\nweight = {weight}\npurpose = &"{id}"\n',encoding='utf-8')
    ext=['[gd_resource type="Resource" script_class="InteriorProfile" format=3]','[ext_resource type="Script" path="res://world/instances/interior_profile.gd" id="1"]','[ext_resource type="Script" path="res://world/instances/room_definition.gd" id="room_script"]']
    for definition in definitions:
        id=definition[0]; ext.append(f'[ext_resource type="Resource" path="res://world/instances/catalog/{id}.tres" id="{id}"]')
    ext.append('[resource]\nscript = ExtResource("1")\nrooms = Array[ExtResource("room_script")](['+', '.join(f'ExtResource("{d[0]}")' for d in definitions)+'])')
    (CAT/'maintenance_v2.tres').write_text('\n\n'.join(ext)+'\n',encoding='utf-8')

if __name__=='__main__': main()
