extends SceneTree

# This script updates the RV's wheels to be 4-Wheel Drive (AWD/4WD).
# A 3500kg vehicle slipping its rear tires won't accelerate well; 
# it needs 4WD traction to effectively put that 20000 engine force into the ground.

func _init():
	print("Enabling 4-Wheel Drive...")
	
	var rv_path = "res://scenes/rv.tscn"
	var packed_scene = ResourceLoader.load(rv_path)
	if not packed_scene:
		print("Error: Could not load ", rv_path)
		quit(1)
		return
		
	var rv = packed_scene.instantiate()
	
	for child in rv.get_children():
		if child is VehicleWheel3D:
			child.use_as_traction = true
			print("Enabled traction on: ", child.name)
			
	var new_packed = PackedScene.new()
	new_packed.pack(rv)
	ResourceSaver.save(new_packed, rv_path)
	
	rv.queue_free()
	print("RV is now 4WD!")
	quit()
