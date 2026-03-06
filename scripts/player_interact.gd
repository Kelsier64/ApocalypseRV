extends RayCast3D

@onready var player = get_parent().get_parent() # RayCast -> Camera3D -> Player

func _physics_process(_delta):
	# Make sure ray length is long enough for testing
	target_position = Vector3(0, 0, -3.0) 
	
	if Input.is_physical_key_pressed(KEY_E):
		if not is_colliding():
			return
			
		var obj = get_collider()
		print("Hit collider: ", obj.name if obj else "None")
		if obj and obj.has_method("interact"):
			print("Found interact method! Interacting...")
			obj.interact(player)
			
			# The original code had a debounce mechanism, which is good practice for interactions.
			# Re-adding it here as the provided snippet seemed to omit it, but it's useful.
			set_physics_process(false)
			await get_tree().create_timer(0.5).timeout
			set_physics_process(true)
