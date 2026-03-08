extends SceneTree

func _init():
	print("--- Generating Crafting Station ---")
	
	var root = RigidBody3D.new()
	root.name = "CraftingStation"
	
	var script = load("res://equipment/crafting_station.gd")
	if script:
		root.set_script(script)
		root.set("equipment_name", "Crafting Station")
	
	# It's equipment, so it needs to be throwable but heavy
	root.mass = 25.0
	
	# 1. Main Table Mesh (A wide, flat box)
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(1.2, 0.8, 0.8)
	mesh_inst.mesh = box
	mesh_inst.position.y = 0.4 # rest on the floor
	
	# Grey metallic color
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.4, 0.45)
	mat.metallic = 0.8
	box.material = mat
	root.add_child(mesh_inst)
	mesh_inst.owner = root
	
	# 2. Main Collision
	var col = CollisionShape3D.new()
	var col_shape = BoxShape3D.new()
	col_shape.size = Vector3(1.2, 0.8, 0.8)
	col.shape = col_shape
	col.position.y = 0.4
	root.add_child(col)
	col.owner = root
	
	# 3. Spawn Marker (Where items appear)
	var marker = Marker3D.new()
	marker.name = "SpawnMarker"
	# Positioned right in the middle, sitting on top of the table (y=0.8 is the top surface, plus a tiny gap)
	marker.position = Vector3(0, 0.9, 0)
	root.add_child(marker)
	marker.owner = root
	
	# Save Scene
	var packed = PackedScene.new()
	if packed.pack(root) == OK:
		ResourceSaver.save(packed, "res://equipment/crafting_station.tscn")
		print("-> Created: res://equipment/crafting_station.tscn")
	else:
		printerr("Failed to pack scene")
		
	quit()
