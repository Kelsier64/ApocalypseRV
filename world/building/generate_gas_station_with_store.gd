extends SceneTree

func _init() -> void:
	var root := Node3D.new()
	root.name = "GasStationWithStore"

	# 1. Load existing gas station
	var base_scene := load("res://world/building/scenes/gas_station.tscn") as PackedScene
	if base_scene:
		var base_inst = base_scene.instantiate()
		root.add_child(base_inst)
		base_inst.owner = root

	# 1.5 Build the new store extension
	_build_store(root)

	# 2. Save the combined scene
	DirAccess.make_dir_recursive_absolute("res://world/building/scenes")
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, "res://world/building/scenes/gas_station_with_store.tscn")
	if err != OK:
		push_error("Failed to save gas_station_with_store.tscn: " + str(err))
	else:
		print("Saved gas_station_with_store.tscn successfully")

	quit()

func _build_store(root: Node3D) -> void:
	var wall_mat := _make_material(Color(0.6, 0.58, 0.55), 0.85)
	var roof_mat := _make_material(Color(0.35, 0.33, 0.3), 0.9)
	var glass_mat := _make_material(Color(0.5, 0.8, 0.9), 0.2, 0.8, 0.4)
	var sign_mat := _make_material(Color(0.8, 0.2, 0.2), 0.5) # Red awning/sign
	
	# Offset the store to the left of the gas station (-X direction)
	var store_offset = Vector3(-12.0, 0, 0)
	
	# Ground Slab
	var slab := _create_box_node("StoreSlab", Vector3(10.0, 0.15, 10.0), wall_mat)
	slab.position = store_offset + Vector3(0, -0.075, 0)
	root.add_child(slab)
	slab.owner = root
	_add_static_collision(slab, Vector3(10.0, 0.15, 10.0), root)
	
	# Roof
	var roof := _create_box_node("StoreRoof", Vector3(10.5, 0.2, 10.5), roof_mat)
	roof.position = store_offset + Vector3(0, 3.5, 0)
	root.add_child(roof)
	roof.owner = root
	_add_static_collision(roof, Vector3(10.5, 0.2, 10.5), root)
	
	# Walls
	var back_wall := _create_box_node("StoreBackWall", Vector3(10.0, 3.5, 0.25), wall_mat)
	back_wall.position = store_offset + Vector3(0, 1.75, -4.875)
	root.add_child(back_wall)
	back_wall.owner = root
	_add_static_collision(back_wall, Vector3(10.0, 3.5, 0.25), root)
	
	var left_wall := _create_box_node("StoreLeftWall", Vector3(0.25, 3.5, 9.5), wall_mat)
	left_wall.position = store_offset + Vector3(-4.875, 1.75, 0)
	root.add_child(left_wall)
	left_wall.owner = root
	_add_static_collision(left_wall, Vector3(0.25, 3.5, 9.5), root)
	
	var right_wall := _create_box_node("StoreRightWall", Vector3(0.25, 3.5, 9.5), wall_mat)
	right_wall.position = store_offset + Vector3(4.875, 1.75, 0)
	root.add_child(right_wall)
	right_wall.owner = root
	_add_static_collision(right_wall, Vector3(0.25, 3.5, 9.5), root)
	
	# Front Wall (with door and window cutouts)
	var front_left := _create_box_node("StoreFrontLeft", Vector3(2.5, 3.5, 0.25), wall_mat)
	front_left.position = store_offset + Vector3(-3.75, 1.75, 4.875)
	root.add_child(front_left)
	front_left.owner = root
	_add_static_collision(front_left, Vector3(2.5, 3.5, 0.25), root)
	
	var front_right := _create_box_node("StoreFrontRight", Vector3(4.5, 3.5, 0.25), wall_mat)
	front_right.position = store_offset + Vector3(2.75, 1.75, 4.875)
	root.add_child(front_right)
	front_right.owner = root
	_add_static_collision(front_right, Vector3(4.5, 3.5, 0.25), root)
	
	var front_top := _create_box_node("StoreFrontTop", Vector3(3.0, 1.0, 0.25), wall_mat)
	front_top.position = store_offset + Vector3(-1.0, 3.0, 4.875)
	root.add_child(front_top)
	front_top.owner = root
	_add_static_collision(front_top, Vector3(3.0, 1.0, 0.25), root)
	
	# Window (Glass)
	var window := _create_box_node("StoreWindow", Vector3(4.0, 2.0, 0.1), glass_mat)
	window.position = store_offset + Vector3(2.5, 1.5, 4.875)
	root.add_child(window)
	window.owner = root
	_add_static_collision(window, Vector3(4.0, 2.0, 0.1), root)
	
	# Store Sign / Awning
	var sign_board := _create_box_node("StoreSign", Vector3(6.0, 0.8, 0.3), sign_mat)
	sign_board.position = store_offset + Vector3(0, 3.2, 5.0)
	root.add_child(sign_board)
	sign_board.owner = root

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
		metallic: float = 0.0, transparency: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mat.albedo_color.a = transparency
	if transparency < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = roughness
	mat.metallic = metallic
	return mat
