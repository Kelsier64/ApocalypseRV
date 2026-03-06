extends SceneTree

func _init():
	print("--- Generating House Reference ---")
	var root = Node3D.new()
	root.name = "House"
	
	# We'll use CSGBox3D for quick modeling
	
	# Main Building Block
	var main_body = CSGBox3D.new()
	main_body.name = "MainBody"
	main_body.use_collision = true
	main_body.size = Vector3(10, 5, 10)
	main_body.position = Vector3(0, 2.5, 0)
	root.add_child(main_body)
	main_body.owner = root
	
	# Hollow Inside
	var hollow = CSGBox3D.new()
	hollow.operation = CSGShape3D.OPERATION_SUBTRACTION
	hollow.size = Vector3(9, 4.5, 9)
	hollow.position = Vector3(0, -0.25, 0)
	main_body.add_child(hollow)
	# CSG children don't strictly need ownership for packing if we don't need to edit them, 
	# but it's safer for the editor tree view
	hollow.owner = root
	
	# Doorway Cutout
	var door = CSGBox3D.new()
	door.operation = CSGShape3D.OPERATION_SUBTRACTION
	door.size = Vector3(2, 3, 2)
	door.position = Vector3(0, -1.0, 4.5) # Cut through the front wall
	main_body.add_child(door)
	door.owner = root
	
	var packed = PackedScene.new()
	if packed.pack(root) == OK:
		ResourceSaver.save(packed, "res://scenes/house.tscn")
		print("-> Created: res://scenes/house.tscn")
	else:
		printerr("Failed to pack House scene")
	
	print("--- Generation Complete ---")
	quit()
