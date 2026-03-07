extends SceneTree

func _init():
	print("--- Updating Test World with Endless Generator ---")
	
	var world_scene = load("res://scenes/test_world.tscn")
	if not world_scene:
		printerr("Could not load test_world.tscn")
		quit()
		return
		
	var root = world_scene.instantiate()
	
	# Check if WorldGenerator already exists
	if not root.has_node("WorldGenerator"):
		var generator = Node3D.new()
		generator.name = "WorldGenerator"
		var script = load("res://scripts/world_generator.gd")
		if script:
			generator.set_script(script)
			
			# We need to assign the player reference to the RV (so terrain generates around the car, not the character)
			var rv = root.get_node_or_null("RV")
			if rv:
				generator.set("player", rv)
				print("Assigned RV to WorldGenerator.")
			else:
				printerr("Could not find RV in test_world.tscn!")
			
			root.add_child(generator)
			generator.owner = root
			
			var packed = PackedScene.new()
			if packed.pack(root) == OK:
				ResourceSaver.save(packed, "res://scenes/test_world.tscn")
				print("Successfully saved test_world.tscn with Endless Generator!")
			else:
				printerr("Failed to pack scene.")
		else:
			printerr("Could not load world_generator.gd script.")
	else:
		print("WorldGenerator already exists in test_world.")

	quit()
