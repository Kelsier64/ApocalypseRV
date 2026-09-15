extends SceneTree
## One-shot authoring scaffold. Never overwrites scenes edited by an artist.
## The saved PackedScenes are the deliverables; this is not a runtime generator.

const BASE := "res://world/poi_kit/"
const ROOM = preload("res://world/poi_kit/poi_room.gd")
const SOCKET = preload("res://world/poi_kit/poi_door_socket.gd")
const FURNITURE = preload("res://world/poi_kit/poi_furniture.gd")
const LOOT = preload("res://world/poi_kit/poi_loot_point.gd")
const ENTRANCE = preload("res://world/poi_kit/poi_entrance.gd")
var concrete: StandardMaterial3D
var paint: StandardMaterial3D
var steel: StandardMaterial3D
var orange: StandardMaterial3D
var floor_mat: StandardMaterial3D
var wood: StandardMaterial3D
var glow: StandardMaterial3D
var failures: int = 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	for folder in ["rooms", "furniture", "exteriors", "materials"]:
		DirAccess.make_dir_recursive_absolute(BASE + folder)
	concrete = _material(Color(0.82, 0.84, 0.78))
	concrete.albedo_texture = load("res://assets/materials/poi_kit/concrete_albedo.png")
	concrete.uv1_triplanar = true
	concrete.uv1_scale = Vector3.ONE * 0.5
	paint = _material(Color("355954"))
	steel = _material(Color("323d3f"), 0.65)
	orange = _material(Color("dc8b42"))
	floor_mat = _material(Color("626b68"))
	wood = _material(Color("897156"))
	glow = _material(Color("dbedd9"))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for entry in [["concrete", concrete], ["paint", paint], ["steel", steel], ["orange", orange], ["floor", floor_mat], ["wood", wood], ["light", glow]]:
		var path: String = BASE + "materials/" + entry[0] + ".tres"
		if ResourceLoader.exists(path):
			push_error("Refusing to overwrite material: " + path)
			quit(1)
			return
		ResourceSaver.save(entry[1], path)
		entry[1].take_over_path(path)
	_save(_shelf(), "furniture/shelf.tscn")
	_save(_table(), "furniture/workbench.tscn")
	_save(_cabinet(), "furniture/cabinet.tscn")
	_save(_room("utility_small", Vector2i(1, 1), 4.5, ["north", "south"], "01 / STORES"), "rooms/utility_small.tscn")
	_save(_room("service_corridor", Vector2i(1, 1), 4.5, ["north", "south"], "02 / TRANSIT"), "rooms/service_corridor.tscn")
	_save(_room("maintenance_hall", Vector2i(2, 2), 6.0, ["south", "east"], "03 / WORKSHOP"), "rooms/maintenance_hall.tscn")
	_save(_exterior(), "exteriors/service_entrance.tscn")
	if failures == 0:
		print("PASS: created editable POI kit scenes; generator will refuse overwriting them")
	quit(failures)

func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mat.metallic = metallic
	return mat

func _node(parent: Node, label: String) -> Node3D:
	var result := Node3D.new()
	result.name = label
	parent.add_child(result)
	return result

func _layers(asset: Node3D, furniture: bool = false) -> void:
	_node(asset, "Visuals")
	var collision := StaticBody3D.new()
	collision.name = "Collision"
	asset.add_child(collision)
	_node(asset, "LootSpawns")
	if not furniture:
		for layer in ["DoorSockets", "Furnishings", "EnemySpawns", "Walkway"]:
			_node(asset, layer)

func _box(parent: Node3D, label: String, size: Vector3, pos: Vector3, mat: Material, solid: bool = true) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	parent.get_node("Visuals").add_child(mesh)
	if solid:
		var shape := CollisionShape3D.new()
		shape.name = label
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		shape.position = pos
		parent.get_node("Collision").add_child(shape)

func _loot(parent: Node, label: String, pos: Vector3, chance: float = 0.7) -> void:
	var point := LOOT.new()
	point.name = label
	point.point_id = StringName(label.to_snake_case())
	point.position = pos
	point.spawn_chance = chance
	point.candidates.append(preload("res://props/scrap.tscn"))
	parent.get_node("LootSpawns").add_child(point)

func _label(parent: Node3D, caption: String, pos: Vector3, text_size: int, tint: Color = Color("e7e3d5")) -> Label3D:
	var sign := Label3D.new()
	sign.name = "Sign" + str(parent.get_child_count())
	sign.text = caption
	sign.position = pos
	sign.font_size = text_size
	sign.pixel_size = 0.008
	sign.modulate = tint
	sign.outline_size = 0
	parent.add_child(sign)
	return sign

func _shelf() -> Node3D:
	var asset := FURNITURE.new()
	asset.name = "Shelf"
	asset.furniture_id = &"shelf_industrial"
	asset.footprint = Vector3(2.4, 2.3, 0.8)
	_layers(asset, true)
	for x in [-1.13, 1.13]:
		for z in [-0.33, 0.33]:
			_box(asset, "Upright" + str(asset.get_node("Visuals").get_child_count()), Vector3(0.09, 2.3, 0.09), Vector3(x, 1.15, z), steel)
	for i in range(3):
		var y := 0.24 + i * 0.78
		_box(asset, "Shelf" + str(i), Vector3(2.3, 0.07, 0.78), Vector3(0, y, 0), wood)
		_box(asset, "Lip" + str(i), Vector3(2.4, 0.1, 0.035), Vector3(0, y, 0.4), orange, false)
		for j in range(2):
			_loot(asset, "Level%dSlot%d" % [i, j], Vector3(-0.55 + j * 1.1, y + 0.22, 0))
	return asset

func _table() -> Node3D:
	var asset := FURNITURE.new()
	asset.name = "Workbench"
	asset.furniture_id = &"workbench"
	asset.footprint = Vector3(2.4, 1.0, 1.0)
	_layers(asset, true)
	_box(asset, "Top", Vector3(2.4, 0.12, 1), Vector3(0, 0.94, 0), wood)
	for x in [-1.05, 1.05]:
		for z in [-0.36, 0.36]:
			_box(asset, "Leg" + str(asset.get_node("Visuals").get_child_count()), Vector3(0.1, 0.9, 0.1), Vector3(x, 0.45, z), steel)
	_box(asset, "Stretcher", Vector3(2.2, 0.1, 0.1), Vector3(0, 0.25, -0.36), steel)
	_loot(asset, "WorktopLeft", Vector3(-0.65, 1.18, 0), 1.0)
	_loot(asset, "WorktopRight", Vector3(0.65, 1.18, 0))
	return asset

func _cabinet() -> Node3D:
	var asset := FURNITURE.new()
	asset.name = "Cabinet"
	asset.furniture_id = &"open_cabinet"
	asset.footprint = Vector3(1.6, 2.0, 0.7)
	_layers(asset, true)
	for x in [-0.76, 0.76]:
		_box(asset, "Side" + str(asset.get_node("Visuals").get_child_count()), Vector3(0.08, 2.0, 0.7), Vector3(x, 1, 0), paint)
	_box(asset, "Back", Vector3(1.6, 2.0, 0.07), Vector3(0, 1, -0.315), paint)
	for i in range(4):
		var y := 0.12 + i * 0.61
		_box(asset, "Tray" + str(i), Vector3(1.6, 0.07, 0.7), Vector3(0, y, 0), steel)
		if i < 3:
			_loot(asset, "TrayLoot" + str(i), Vector3(0, y + 0.22, 0.05))
	return asset

func _wall_piece(asset: Node3D, size: Vector3, pos: Vector3) -> void:
	var index := str(asset.get_node("Visuals").get_child_count())
	_box(asset, "Wall" + index, size, pos, concrete)
	if pos.y - size.y * 0.5 < 0.01:
		_box(asset, "Paint" + index, Vector3(size.x + 0.008, 1.35, size.z + 0.008), Vector3(pos.x, 0.675, pos.z), paint, false)
		_box(asset, "Stripe" + index, Vector3(size.x + 0.012, 0.07, size.z + 0.012), Vector3(pos.x, 1.4, pos.z), orange, false)

func _wall(asset: Node3D, width: float, height: float, depth: float, side: String, door: bool) -> void:
	var across_x := side == "north" or side == "south"
	var length := width if across_x else depth
	var edge := (depth if across_x else width) * 0.5
	var sign_axis := -1.0 if side == "north" or side == "west" else 1.0
	var center := Vector3(0, height * 0.5, sign_axis * edge) if across_x else Vector3(sign_axis * edge, height * 0.5, 0)
	if not door:
		_wall_piece(asset, Vector3(length, height, 0.24) if across_x else Vector3(0.24, height, length), center)
		return
	var wing := (length - 3.0) * 0.5
	for direction in [-1.0, 1.0]:
		var offset: float = direction * (1.5 + wing * 0.5)
		var wing_center := center + (Vector3(offset, 0, 0) if across_x else Vector3(0, 0, offset))
		_wall_piece(asset, Vector3(wing, height, 0.24) if across_x else Vector3(0.24, height, wing), wing_center)
		var jamb := center + (Vector3(direction * 1.57, 0, 0) if across_x else Vector3(0, 0, direction * 1.57))
		jamb.y = 1.75
		_box(asset, "Jamb" + str(asset.get_node("Visuals").get_child_count()), Vector3(0.12, 3.5, 0.34) if across_x else Vector3(0.34, 3.5, 0.12), jamb, steel, false)
	center.y = (height + 3.5) * 0.5
	_wall_piece(asset, Vector3(3, height - 3.5, 0.24) if across_x else Vector3(0.24, height - 3.5, 3), center)
	center.y = 3.56
	_box(asset, "Lintel" + side, Vector3(3.25, 0.12, 0.34) if across_x else Vector3(0.34, 0.12, 3.25), center, orange, false)
	var socket := SOCKET.new()
	socket.name = side.capitalize()
	socket.socket_id = StringName(side)
	socket.position = Vector3(center.x, 0, center.z)
	socket.rotation.y = {"north": 0.0, "south": PI, "east": -PI / 2.0, "west": PI / 2.0}[side]
	asset.get_node("DoorSockets").add_child(socket)

func _lamp(asset: Node3D, pos: Vector3) -> void:
	var count := str(asset.get_node("Visuals").get_child_count())
	_box(asset, "LampHousing" + count, Vector3(2.2, 0.14, 0.42), pos, steel, false)
	_box(asset, "LampTube" + count, Vector3(1.9, 0.04, 0.22), pos + Vector3(0, -0.09, 0), glow, false)
	var light := OmniLight3D.new()
	light.name = "LampLight" + count
	light.position = pos + Vector3(0, -0.5, 0)
	light.light_color = Color("dce9da")
	light.light_energy = 2.0
	light.omni_range = 9.0
	asset.get_node("Visuals").add_child(light)

func _furnish(asset: Node3D, scene: String, label: String, pos: Vector3, yaw: float = 0.0) -> void:
	var item: Node3D = load(BASE + "furniture/" + scene + ".tscn").instantiate()
	item.name = label
	item.position = pos
	item.rotation.y = yaw
	asset.get_node("Furnishings").add_child(item)

func _room(id: String, cells: Vector2i, height: float, doors: Array, title: String) -> Node3D:
	var asset := ROOM.new()
	asset.name = id.to_pascal_case()
	asset.room_id = StringName(id)
	asset.size_cells = cells
	asset.clear_height = height
	asset.category = &"corridor" if id.contains("corridor") else &"utility"
	_layers(asset)
	var w := float(cells.x) * 9.0
	var d := float(cells.y) * 9.0
	_box(asset, "Floor", Vector3(w, 0.25, d), Vector3(0, -0.125, 0), floor_mat)
	_box(asset, "Ceiling", Vector3(w + 0.24, 0.24, d + 0.24), Vector3(0, height + 0.12, 0), concrete)
	for side in ["north", "south", "east", "west"]:
		_wall(asset, w, height, d, side, doors.has(side))
	for x in [-1.15, 1.15]:
		_box(asset, "Lane" + str(x), Vector3(0.055, 0.008, d), Vector3(x, 0.008, 0), orange, false)
	for z in [-d / 3.0, 0.0, d / 3.0]:
		_box(asset, "Beam" + str(z), Vector3(w, 0.22, 0.18), Vector3(0, height - 0.11, z), steel, false)
		_lamp(asset, Vector3(0, height - 0.4, z))
	_label(asset.get_node("Visuals"), title, Vector3(-w * 0.32, 2.4, -d * 0.5 + 0.16), 48)
	for i in range(3):
		var point := Marker3D.new()
		point.name = ["South", "Center", "North"][i]
		point.position = Vector3(0, 0, d * 0.5 - 0.6 - i * (d - 1.2) / 2.0)
		asset.get_node("Walkway").add_child(point)
	if id == "utility_small":
		_furnish(asset, "shelf", "ShelfWest", Vector3(-3.4, 0, -2.7), PI / 2.0)
		_furnish(asset, "workbench", "BenchEast", Vector3(3.2, 0, 0.5), -PI / 2.0)
		_furnish(asset, "cabinet", "CabinetNorth", Vector3(2.8, 0, -3.95))
	elif id == "maintenance_hall":
		for x in [-6.8, 6.8]:
			for z in [-5.5, -1.5, 3.5]:
				var rack_z: float = -3.0 if x > 0 and z == -1.5 else z
				_furnish(asset, "shelf", "Rack" + str(asset.get_node("Furnishings").get_child_count()), Vector3(x, 0, rack_z), PI / 2 if x < 0 else -PI / 2)
		_furnish(asset, "workbench", "Workbench", Vector3(-3.3, 0, -6.7))
		_furnish(asset, "cabinet", "Cabinet", Vector3(4.5, 0, -8.3))
		var spawn := Marker3D.new()
		spawn.name = "EnemyCandidate01"
		spawn.position = Vector3(-4, 0.05, 2)
		asset.get_node("EnemySpawns").add_child(spawn)
	else:
		# 9m footprint, but partitions make the actual corridor 3m wide.
		for x in [-3.05, 3.05]:
			_box(asset, "ServiceCore" + str(x), Vector3(2.9, height, d), Vector3(x, height / 2, 0), paint)
		_label(asset.get_node("Visuals"), "WORKSHOP  >", Vector3(0, 3.85, -d / 2 + 0.2), 40, Color("dc8b42"))
	return asset

func _exterior() -> Node3D:
	var asset := Node3D.new()
	asset.name = "ServiceEntrance"
	_layers(asset)
	_box(asset, "Slab", Vector3(10, 0.25, 10), Vector3(0, -0.125, 0), floor_mat)
	for side in ["north", "east", "west", "south"]:
		_wall(asset, 9, 5.2, 9, side, side == "south")
	_box(asset, "Roof", Vector3(9.5, 0.3, 9.5), Vector3(0, 5.3, 0), steel)
	_box(asset, "Canopy", Vector3(10.6, 0.18, 3.4), Vector3(0, 4.15, 5.7), paint)
	_box(asset, "Fascia", Vector3(10.6, 0.25, 0.08), Vector3(0, 4.15, 7.42), orange, false)
	_box(asset, "SignBoard", Vector3(7.9, 0.7, 0.1), Vector3(0, 4.75, 4.7), steel, false)
	_label(asset.get_node("Visuals"), "NORTHLINE  /  SERVICE 07", Vector3(0, 4.75, 4.77), 60)
	_label(asset.get_node("Visuals"), "MAINTENANCE ACCESS\n[E] ENTER", Vector3(0, 2.3, 4.62), 36, Color("dc8b42"))
	for x in [-3.6, 3.6]:
		_box(asset, "Post" + str(x), Vector3(0.16, 4, 0.16), Vector3(x, 2, 7.0), steel)
		_box(asset, "PostGuard" + str(x), Vector3(0.22, 0.9, 0.22), Vector3(x, 0.45, 7), orange, false)
	_box(asset, "VentUnit", Vector3(2, 0.8, 1.7), Vector3(-2.2, 5.85, -1), paint)
	for i in range(6):
		_box(asset, "VentSlat" + str(i), Vector3(1.8, 0.055, 0.07), Vector3(-2.2, 5.55 + i * 0.11, -0.13), steel, false)
	var portal := ENTRANCE.new()
	portal.name = "Entrance"
	portal.position = Vector3(0, 0, 4.5)
	asset.add_child(portal)
	var shape := CollisionShape3D.new()
	shape.name = "DoorCollision"
	var door_box := BoxShape3D.new()
	door_box.size = Vector3(3, 3.5, 0.15)
	shape.shape = door_box
	shape.position.y = 1.75
	portal.add_child(shape)
	_box(asset, "DoorVisual", Vector3(3, 3.5, 0.14), Vector3(0, 1.75, 4.5), steel, false)
	for x in [-0.65, 0.65]:
		_box(asset, "Handle" + str(x), Vector3(0.07, 0.45, 0.12), Vector3(x, 1.2, 4.62), orange, false)
	var arrival := Marker3D.new()
	arrival.name = "ReturnPoint"
	arrival.position = Vector3(0, 0.05, 6.3)
	asset.add_child(arrival)
	return asset

func _own(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		if child.scene_file_path.is_empty():
			_own(child, scene_root)

func _save(asset: Node3D, relative_path: String) -> void:
	var path := BASE + relative_path
	if ResourceLoader.exists(path):
		push_error("Refusing to overwrite edited scene: " + path)
		failures += 1
		asset.free()
		return
	_own(asset, asset)
	var packed := PackedScene.new()
	var error := packed.pack(asset)
	if error == OK:
		error = ResourceSaver.save(packed, path)
	if error != OK:
		push_error("Could not save " + path)
		failures += 1
	asset.free()
