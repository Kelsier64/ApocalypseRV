@tool
extends EditorScript

func _run():
	print("--- Updating RV Collision Boxes ---")
	var rv_scene = load("res://scenes/rv.tscn")
	if not rv_scene:
		printerr("Could not load rv.tscn")
		return
		
	var rv = rv_scene.instantiate()
	var modified = false
	
	for child in rv.get_children():
		if child is CollisionShape3D and child.name.ends_with("Col"):
			var base_name = child.name.replace("Col", "")
			var mesh_node = rv.get_node_or_null(base_name + "Mesh") as MeshInstance3D
			
			if mesh_node and mesh_node.mesh is BoxMesh and child.shape is BoxShape3D:
				# Copy size
				var new_size = mesh_node.mesh.size
				child.shape.size = new_size
				# Add size to shape to force it to be unique to this instance in case they are shared
				var new_shape = BoxShape3D.new()
				new_shape.size = new_size
				child.shape = new_shape
				
				# Copy transform
				child.transform = mesh_node.transform
				
				print("Updated %s to match %s (Size: %s)" % [child.name, mesh_node.name, new_size])
				modified = true

	if modified:
		var packed = PackedScene.new()
		if packed.pack(rv) == OK:
			ResourceSaver.save(packed, "res://scenes/rv.tscn")
			print("-> Saved updated rv.tscn!")
		else:
			printerr("Failed to repack rv.tscn")
	else:
		print("No colliders needed updating.")
		
	rv.queue_free()
	print("--- Done ---")
