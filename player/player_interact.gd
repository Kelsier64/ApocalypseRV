extends RayCast3D

@onready var player = get_parent().get_parent() # RayCast -> Camera3D -> Player

func _physics_process(_delta):
	# Make sure ray length is long enough for testing
	target_position = Vector3(0, 0, -3.0) 
	
	var obj = get_collider() if is_colliding() else null
	
	var is_holding = false
	
	# 1. Normal Interaction (E) for Props/Items + Hold for special objects
	if Input.is_physical_key_pressed(KEY_E):
		if obj:
			# If the object requires a hold interaction
			if obj.has_method("interact_hold") and "hold_timer" in obj:
				obj.hold_timer += _delta
				is_holding = true
				if obj.hold_timer >= 1.0:
					obj.interact_hold(player)
					obj.hold_timer = 0.0
						
			# Otherwise just normal instant interact
			elif obj.has_method("interact"):
				obj.interact(player)
				set_physics_process(false)
				await get_tree().create_timer(0.5).timeout
				set_physics_process(true)
				return
					
	# 2. Hold F Interaction for Placeable Equipment
	elif Input.is_physical_key_pressed(KEY_F):
		if obj and obj is Equipment:
			if not player.is_placing_equipment():
				obj.hold_timer += _delta
				is_holding = true
				if obj.hold_timer >= 2.0:
					obj.start_placement(player)
					obj.hold_timer = 0.0
					
	# 3. Handle resetting if neither relevant key is held or looking away
	if not is_holding:
		_reset_all_equipment_timers()

func _reset_all_equipment_timers():
	# Simplistic way to reset. For better performance, we'd track the specific focused object.
	# But checking the collider is usually enough.
	var obj = get_collider()
	if obj and obj is Equipment:
		if "hold_timer" in obj:
			obj.hold_timer = 0.0
