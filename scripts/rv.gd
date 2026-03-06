extends VehicleBody3D

@export var max_engine_force: float = 500.0
@export var max_braking_force: float = 5.0
@export var max_steering: float = 0.5 
@export var is_player_driving: bool = false # Toggle this via driver seat!

func set_driving_state(state: bool):
	is_player_driving = state

# Note: Wheels need to have 'use_as_traction' set for accelerating wheels
# and 'use_as_steering' set for the front steering wheels in the Godot Inspector.

func _physics_process(delta):
	var throttle = 0.0
	var braking = 0.0
	var steer_left = 0.0
	var steer_right = 0.0
	
	# 1. Driver Seat Control (WASD)
	if is_player_driving:
		if Input.is_physical_key_pressed(KEY_W): throttle = 1.0
		if Input.is_physical_key_pressed(KEY_S): braking = 1.0
		if Input.is_physical_key_pressed(KEY_A): steer_left = 1.0
		if Input.is_physical_key_pressed(KEY_D): steer_right = 1.0
		
	# 2. Remote Control / Testing (Arrow Keys) - Always active
	if Input.is_physical_key_pressed(KEY_UP): throttle = 1.0
	if Input.is_physical_key_pressed(KEY_DOWN): braking = 1.0
	if Input.is_physical_key_pressed(KEY_LEFT): steer_left = 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT): steer_right = 1.0
	
	var has_input = throttle > 0.0 or braking > 0.0 or steer_left > 0.0 or steer_right > 0.0

	# Apply parking brake if nobody is driving and nobody is remote controlling
	if not is_player_driving and not has_input:
		brake = max_braking_force
		engine_force = 0.0
		steering = 0.0
		return
		
	# Apply steering
	var target_steering = (steer_left - steer_right) * max_steering
	# Smoothly interpolate steering for natural feel
	steering = lerp(steering, target_steering, 5.0 * delta)
	
	# Apply acceleration and braking
	if throttle > 0.0:
		engine_force = throttle * max_engine_force
		brake = 0.0
	elif braking > 0.0:
		# If we press down/brake, and we are moving forward, we brake
		# For simplicity here, we'll assign brake or reverse engine force.
		if linear_velocity.dot(transform.basis.z) > -1.0: # Moving forward or stopped
			engine_force = 0.0
			brake = braking * max_braking_force
		else:
			# Reverse
			brake = 0.0
			engine_force = -braking * max_engine_force
	else:
		# Let it roll
		engine_force = 0.0
		brake = 0.0
