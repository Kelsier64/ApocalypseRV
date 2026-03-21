extends SceneTree

func _init():
	var store = Node3D.new()
	store.name = "ConvenienceStore"

	# Settings
	var store_width = 16.0
	var store_depth = 12.0
	var wall_height = 4.0
	var wall_thickness = 0.4

	# 1. Floor
	var floor_mesh = _create_box_wall("Floor", Vector3(store_width, 0.2, store_depth), Color(0.4, 0.4, 0.45))
	floor_mesh.position = Vector3(0, -0.1, 0)
	_add_to_scene(store, floor_mesh)

	# 2. Walls
	# Back Wall
	var back_wall = _create_box_wall("BackWall", Vector3(store_width, wall_height, wall_thickness), Color(0.6, 0.6, 0.6))
	back_wall.position = Vector3(0, wall_height / 2.0, -store_depth / 2.0 + wall_thickness / 2.0)
	_add_to_scene(store, back_wall)

	# Left Wall
	var left_wall = _create_box_wall("LeftWall", Vector3(wall_thickness, wall_height, store_depth), Color(0.6, 0.6, 0.6))
	left_wall.position = Vector3(-store_width / 2.0 + wall_thickness / 2.0, wall_height / 2.0, 0)
	_add_to_scene(store, left_wall)

	# Right Wall
	var right_wall = _create_box_wall("RightWall", Vector3(wall_thickness, wall_height, store_depth), Color(0.6, 0.6, 0.6))
	right_wall.position = Vector3(store_width / 2.0 - wall_thickness / 2.0, wall_height / 2.0, 0)
	_add_to_scene(store, right_wall)

	# Front Wall (with a gap for the door)
	var front_wall_left = _create_box_wall("FrontWallLeft", Vector3((store_width - 4.0) / 2.0, wall_height, wall_thickness), Color(0.6, 0.6, 0.6))
	front_wall_left.position = Vector3(-store_width / 4.0 - 1.0, wall_height / 2.0, store_depth / 2.0 - wall_thickness / 2.0)
	_add_to_scene(store, front_wall_left)

	var front_wall_right = _create_box_wall("FrontWallRight", Vector3((store_width - 4.0) / 2.0, wall_height, wall_thickness), Color(0.6, 0.6, 0.6))
	front_wall_right.position = Vector3(store_width / 4.0 + 1.0, wall_height / 2.0, store_depth / 2.0 - wall_thickness / 2.0)
	_add_to_scene(store, front_wall_right)

	var front_wall_top = _create_box_wall("FrontWallTop", Vector3(4.0, 1.0, wall_thickness), Color(0.6, 0.6, 0.6))
	front_wall_top.position = Vector3(0, wall_height - 0.5, store_depth / 2.0 - wall_thickness / 2.0)
	_add_to_scene(store, front_wall_top)

	# 3. Roof
	var roof_mesh = _create_box_wall("Roof", Vector3(store_width + 1.0, 0.4, store_depth + 1.0), Color(0.3, 0.3, 0.3))
	roof_mesh.position = Vector3(0, wall_height + 0.2, 0)
	_add_to_scene(store, roof_mesh)

	# 4. Tiles / Shelves
	var shelf_scene = load("res://world/building/tiles/shelf.tscn")
	var shelf_positions = [
		Vector3(-4, 0, -2), Vector3(-4, 0, 1),
		Vector3(0, 0, -2),  Vector3(0, 0, 1),
		Vector3(4, 0, -2),  Vector3(4, 0, 1)
	]

	for i in range(shelf_positions.size()):
		var shelf = shelf_scene.instantiate()
		shelf.name = "Shelf_" + str(i)
		shelf.position = shelf_positions[i]
		_add_to_scene(store, shelf)

	# 5. Props
	var gas_can_scene = load("res://props/gas_can.tscn")
	var scrap_scene = load("res://props/scrap.tscn")
	var prop_scenes = [gas_can_scene, scrap_scene, gas_can_scene, scrap_scene, scrap_scene, scrap_scene]

	for i in range(prop_scenes.size()):
		if prop_scenes[i]:
			var prop = prop_scenes[i].instantiate()
			prop.name = "Prop_" + str(i)
			# Put on top of shelves roughly
			prop.position = shelf_positions[i] + Vector3(0, 1.5, 0)
			_add_to_scene(store, prop)

	var counter_mesh = _create_box_wall("Counter", Vector3(3.0, 1.0, 1.0), Color(0.5, 0.3, 0.1))
	counter_mesh.position = Vector3(-4, 0.5, 4)
	_add_to_scene(store, counter_mesh)

	var packed_scene = PackedScene.new()
	var err = packed_scene.pack(store)
	if err == OK:
		err = ResourceSaver.save(packed_scene, "res://world/building/scenes/convenience_store.tscn")
		if err == OK:
			print("Successfully saved convenience_store.tscn!")
		else:
			print("Error saving resource: ", err)
	else:
		print("Error packing scene: ", err)

	quit()

func _create_box_wall(node_name: String, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = node_name
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	box_mesh.material = mat
	mesh_inst.mesh = box_mesh
	
	var static_body = StaticBody3D.new()
	static_body.name = "StaticBody3D"
	mesh_inst.add_child(static_body)
	
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var box_shape = BoxShape3D.new()
	box_shape.size = size
	collision_shape.shape = box_shape
	static_body.add_child(collision_shape)
	
	return mesh_inst

func _add_to_scene(root: Node, node: Node):
	root.add_child(node)
	node.owner = root
	# Sub-nodes of the generated instances (like StaticBody3D/CollisionShape3D created dynamically)
	# need to be owned by the root of the PackedScene.
	for child in node.get_children():
		child.owner = root
		for grandchild in child.get_children():
			grandchild.owner = root
