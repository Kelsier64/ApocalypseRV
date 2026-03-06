extends SceneTree

func _init():
	print("--- Updating RV Collision Boxes via CLI ---")
	var rv_scene = load("res://scenes/rv.tscn")
	if not rv_scene:
		printerr("Could not load rv.tscn")
		quit(1)
		return
		
	var rv = rv_scene.instantiate()
	var modified = false
	
	for child in rv.get_children():
		if child is CollisionShape3D and child.name.ends_with("Col"):
			var base_name = child.name.replace("Col", "")
			var mesh_node = rv.get_node_or_null(base_name + "Mesh") as MeshInstance3D
			
			if mesh_node and mesh_node.mesh is BoxMesh and child.shape is BoxShape3D:
				var new_size = mesh_node.mesh.size
				
				var new_shape = BoxShape3D.new()
				new_shape.size = new_size
				child.shape = new_shape
				
				child.transform = mesh_node.transform
				
				print("Updated %s to match %s (Size: %s)" % [child.name, mesh_node.name, new_size])
				modified = true

	if modified:
		var packed = PackedScene.new()
		# MUST properly assign owner to save scene children correctly
		for c in rv.get_children():
			c.owner = rv
			for grandc in c.get_children():
				grandc.owner = rv
				
		if packed.pack(rv) == OK:
			ResourceSaver.save(packed, "res://scenes/rv.tscn")
			print("-> Saved updated rv.tscn!")
		else:
			printerr("Failed to repack rv.tscn")
	else:
		print("No colliders needed updating.")
		
	rv.free()
	print("--- Done ---")
	quit()
