extends SceneTree

func _init():
	print("Creating Test Generator Equipment...")
	var pack_path = "res://scenes/generator.tscn"
	
	var root = RigidBody3D.new()
	root.name = "Generator"
	root.mass = 50.0
	
	var script = load("res://scripts/equipment.gd")
	root.set_script(script)
	root.set("equipment_name", "Portable Generator")
	
	# Mesh
	var mesh_node = MeshInstance3D.new()
	mesh_node.name = "Mesh"
	
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.8, 0.6, 1.2)
	mesh_node.mesh = box_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.2) # Red generator
	mesh_node.material_override = mat
	
	root.add_child(mesh_node)
	mesh_node.owner = root
	
	# Collision
	var col_node = CollisionShape3D.new()
	col_node.name = "Collision"
	var col_shape = BoxShape3D.new()
	col_shape.size = box_mesh.size
	col_node.shape = col_shape
	
	root.add_child(col_node)
	col_node.owner = root
	
	var pack = PackedScene.new()
	pack.pack(root)
	ResourceSaver.save(pack, pack_path)
	root.queue_free()
	
	print("Test Generator saved to 'res://scenes/generator.tscn'")
	quit()
