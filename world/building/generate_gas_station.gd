extends SceneTree


func _init() -> void:
	var root := Node3D.new()
	root.name = "GasStation"

	_build_ground_slab(root)
	_build_store_walls(root)
	_build_store_roof(root)
	_build_canopy_pillars(root)
	_build_canopy_roof(root)
	_build_fuel_pumps(root)
	_build_pump_island(root)
	_build_shelves(root)
	_build_counter(root)

	DirAccess.make_dir_recursive_absolute("res://world/building/scenes")

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, "res://world/building/scenes/gas_station.tscn")
	if err != OK:
		push_error("Failed to save gas_station.tscn: " + str(err))
	else:
		print("Saved gas_station.tscn successfully")

	quit()


# --- Ground slab ---

func _build_ground_slab(root: Node3D) -> void:
	var mat := _make_material(Color(0.50, 0.48, 0.45), 0.95)
	var node := _create_box_node("GroundSlab", Vector3(18.0, 0.15, 14.0), mat)
	node.position = Vector3(0.0, -0.075, 0.75)
	root.add_child(node)
	node.owner = root
	_add_static_collision(node, Vector3(18.0, 0.15, 14.0), root)


# --- Store walls ---

func _build_store_walls(root: Node3D) -> void:
	var mat := _make_material(Color(0.55, 0.52, 0.48), 0.85)

	# North (back) wall
	var north := _create_box_node("WallNorth", Vector3(8.5, 3.0, 0.25), mat)
	north.position = Vector3(0.0, 1.5, -6.125)
	root.add_child(north)
	north.owner = root
	_add_static_collision(north, Vector3(8.5, 3.0, 0.25), root)

	# East wall
	var east := _create_box_node("WallEast", Vector3(0.25, 3.0, 6.25), mat)
	east.position = Vector3(4.125, 1.5, -3.0)
	root.add_child(east)
	east.owner = root
	_add_static_collision(east, Vector3(0.25, 3.0, 6.25), root)

	# West wall
	var west := _create_box_node("WallWest", Vector3(0.25, 3.0, 6.25), mat)
	west.position = Vector3(-4.125, 1.5, -3.0)
	root.add_child(west)
	west.owner = root
	_add_static_collision(west, Vector3(0.25, 3.0, 6.25), root)

	# South wall - left of door
	var south_left := _create_box_node("WallSouthLeft", Vector3(2.875, 3.0, 0.25), mat)
	south_left.position = Vector3(-2.5625, 1.5, 0.125)
	root.add_child(south_left)
	south_left.owner = root
	_add_static_collision(south_left, Vector3(2.875, 3.0, 0.25), root)

	# South wall - right of door
	var south_right := _create_box_node("WallSouthRight", Vector3(2.875, 3.0, 0.25), mat)
	south_right.position = Vector3(2.5625, 1.5, 0.125)
	root.add_child(south_right)
	south_right.owner = root
	_add_static_collision(south_right, Vector3(2.875, 3.0, 0.25), root)


# --- Store roof ---

func _build_store_roof(root: Node3D) -> void:
	var mat := _make_material(Color(0.42, 0.40, 0.38), 0.9)
	var roof := _create_box_node("StoreRoof", Vector3(8.5, 0.15, 6.5), mat)
	roof.position = Vector3(0.0, 3.075, -2.875)
	root.add_child(roof)
	roof.owner = root
	_add_static_collision(roof, Vector3(8.5, 0.15, 6.5), root)


# --- Canopy pillars (instanced from pillar.tscn) ---

func _build_canopy_pillars(root: Node3D) -> void:
	var positions := [
		Vector3(-4.5, 1.5, 1.0),
		Vector3(4.5, 1.5, 1.0),
		Vector3(-4.5, 1.5, 7.0),
		Vector3(4.5, 1.5, 7.0),
	]
	for i in positions.size():
		_instance_tile("res://world/building/tiles/pillar.tscn",
			positions[i], 0.0, "CanopyPillar" + str(i + 1), root)


# --- Canopy roof + fascia ---

func _build_canopy_roof(root: Node3D) -> void:
	var roof_mat := _make_material(Color(0.65, 0.60, 0.55), 0.7, 0.3)
	var roof := _create_box_node("CanopyRoof", Vector3(10.0, 0.15, 7.0), roof_mat)
	roof.position = Vector3(0.0, 3.075, 4.0)
	root.add_child(roof)
	roof.owner = root
	_add_static_collision(roof, Vector3(10.0, 0.15, 7.0), root)

	# Fascia strips (decorative, no collision)
	var fascia_mat := _make_material(Color(0.50, 0.45, 0.40), 0.6, 0.4)

	var fascia_data := [
		["FasciaNorth", Vector3(10.0, 0.3, 0.1), Vector3(0.0, 2.85, 0.5)],
		["FasciaSouth", Vector3(10.0, 0.3, 0.1), Vector3(0.0, 2.85, 7.5)],
		["FasciaEast", Vector3(0.1, 0.3, 7.0), Vector3(5.0, 2.85, 4.0)],
		["FasciaWest", Vector3(0.1, 0.3, 7.0), Vector3(-5.0, 2.85, 4.0)],
	]
	for data in fascia_data:
		var strip := _create_box_node(data[0], data[1], fascia_mat)
		strip.position = data[2]
		root.add_child(strip)
		strip.owner = root


# --- Fuel pumps (instanced from fuel_pump.tscn) ---

func _build_fuel_pumps(root: Node3D) -> void:
	var positions := [
		Vector3(-2.5, 1.5, 4.0),
		Vector3(0.0, 1.5, 4.0),
		Vector3(2.5, 1.5, 4.0),
	]
	for i in positions.size():
		_instance_tile("res://world/building/tiles/fuel_pump.tscn",
			positions[i], 0.0, "FuelPump" + str(i + 1), root)


# --- Pump island curb ---

func _build_pump_island(root: Node3D) -> void:
	var mat := _make_material(Color(0.58, 0.56, 0.52), 0.9)
	var curb := _create_box_node("PumpIsland", Vector3(8.0, 0.15, 1.2), mat)
	curb.position = Vector3(0.0, 0.075, 4.0)
	root.add_child(curb)
	curb.owner = root
	_add_static_collision(curb, Vector3(8.0, 0.15, 1.2), root)


# --- Shelves (instanced from shelf.tscn) ---

func _build_shelves(root: Node3D) -> void:
	# West wall shelf (default orientation, back at -X)
	_instance_tile("res://world/building/tiles/shelf.tscn",
		Vector3(-2.5, 1.5, -3.5), 0.0, "ShelfWest", root)

	# East wall shelf (rotated 180°, back at +X)
	_instance_tile("res://world/building/tiles/shelf.tscn",
		Vector3(2.5, 1.5, -3.5), PI, "ShelfEast", root)


# --- Counter ---

func _build_counter(root: Node3D) -> void:
	var mat := _make_material(Color(0.45, 0.35, 0.25), 0.8)
	var counter := _create_box_node("Counter", Vector3(2.0, 1.0, 0.6), mat)
	counter.position = Vector3(2.5, 0.5, -1.0)
	root.add_child(counter)
	counter.owner = root
	_add_static_collision(counter, Vector3(2.0, 1.0, 0.6), root)


# =============================================================================
# Helpers
# =============================================================================

func _create_box_node(node_name: String, size: Vector3,
		mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat

	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	return mi


func _add_static_collision(mesh_node: MeshInstance3D, box_size: Vector3,
		root: Node3D) -> void:
	var shape := BoxShape3D.new()
	shape.size = box_size

	var col := CollisionShape3D.new()
	col.shape = shape

	var body := StaticBody3D.new()
	body.add_child(col)

	mesh_node.add_child(body)
	body.owner = root
	col.owner = root


func _make_material(color: Color, roughness: float,
		metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _instance_tile(scene_path: String, pos: Vector3, rot_y: float,
		node_name: String, root: Node3D) -> void:
	var scene := load(scene_path) as PackedScene
	if not scene:
		push_error("Failed to load tile: " + scene_path)
		return
	var inst := scene.instantiate()
	inst.name = node_name
	inst.position = pos
	if rot_y != 0.0:
		inst.rotation.y = rot_y
	root.add_child(inst)
	inst.owner = root
