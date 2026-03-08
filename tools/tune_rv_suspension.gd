extends SceneTree

# This script tunes the physical properties of the RV's VehicleBody3D and VehicleWheel3D nodes
# to make it feel like a heavy, stable truck rather than a bouncy sports car.

func _init():
	print("Tuning RV Suspension and Physics...")
	
	var rv_path = "res://scenes/rv.tscn"
	var packed_scene = ResourceLoader.load(rv_path)
	if not packed_scene:
		print("Error: Could not load ", rv_path)
		return
		
	var rv = packed_scene.instantiate()
	
	# 1. Update VehicleBody3D Mass (make it a heavy truck)
	rv.mass = 3500.0 # 3.5 tons for an RV
	
	# 2. Update Wheels
	var wheel_count = 0
	for child in rv.get_children():
		if child is VehicleWheel3D:
			wheel_count += 1
			
			# Suspension Settings
			child.suspension_travel = 0.5 # Allow wheels to drop into FBM noise holes
			child.suspension_stiffness = 40.0 # Stiff enough to hold 3500kg
			child.suspension_max_force = 15000.0 # Prevent bottoming out
			
			# Damping (Prevent bouncing)
			child.damping_compression = 0.88 # Resist compressing quickly
			child.damping_relaxation = 0.95 # Relax slightly slower to prevent springy bounce
			
			# Grip
			child.wheel_friction_slip = 3.5 # Allow heavy sliding, not F1 cornering grip
			
	print("Tuned ", wheel_count, " wheels.")
	
	# Save the scene back
	var new_packed = PackedScene.new()
	new_packed.pack(rv)
	ResourceSaver.save(new_packed, rv_path)
	
	rv.queue_free()
	print("RV Physics successfully tuned and saved to '", rv_path, "'!")
	quit()
