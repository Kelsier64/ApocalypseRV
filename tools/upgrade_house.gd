extends SceneTree

func _init():
	print("Upgrading House Scene...")
	var path = "res://scenes/house.tscn"
	var packed_scene = ResourceLoader.load(path)
	if not packed_scene:
		print("Error: Could not load ", path)
		quit(1)
		return
		
	var house = packed_scene.instantiate()
	
	# Add floor if it doesn't exist
	if not house.has_node("Floor"):
		var floor = CSGBox3D.new()
		floor.name = "Floor"
		floor.size = Vector3(9.8, 0.5, 9.8)
		floor.position = Vector3(0, 0.25, 0)
		floor.use_collision = true
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.25, 0.25) # Dark concrete
		floor.material_override = mat
		
		house.add_child(floor)
		floor.owner = house
		print("Added solid concrete Floor.")
		
	# Add LootSpawns
	if not house.has_node("LootSpawns"):
		var loot_node = Node3D.new()
		loot_node.name = "LootSpawns"
		house.add_child(loot_node)
		loot_node.owner = house
		
		# Create spawn points in the 4 corners of the house
		var positions = [
			Vector3(3.5, 0.6, 3.5),
			Vector3(-3.5, 0.6, 3.5),
			Vector3(3.5, 0.6, -3.5),
			Vector3(-3.5, 0.6, -3.5)
		]
		
		for i in range(4):
			var m = Marker3D.new()
			m.name = "Spawn" + str(i+1)
			m.position = positions[i]
			loot_node.add_child(m)
			m.owner = house
		print("Added 4 LootSpawn points.")
			
	var new_packed = PackedScene.new()
	new_packed.pack(house)
	ResourceSaver.save(new_packed, path)
	house.queue_free()
	
	print("House upgraded successfully.")
	quit()
