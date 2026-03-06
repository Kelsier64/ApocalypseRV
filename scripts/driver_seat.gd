extends Area3D

# Reference to the RV vehicle body (assigned by the RV scene or script)
@onready var vehicle: VehicleBody3D = get_parent()
@onready var seat_camera: Camera3D = $Camera3D

var current_driver: Node3D = null

func interact(player: Node3D):
	if current_driver:
		# Someone is already driving
		return
		
	# Board the vehicle
	current_driver = player
	
	# Disable player physics and hide them (or play sit animation in the future)
	player.set_physics_process(false)
	# Disable collision so player doesn't accidentally bounce inside the RV
	player.get_node("CollisionShape3D").disabled = true
	# Hide the player visual if any (currently capsule)
	player.visible = false
	
	# Switch to seat camera
	seat_camera.current = true
	
	# Enable RV driving control
	if vehicle.has_method("set_driving_state"):
		vehicle.set_driving_state(true)
	elif "is_player_driving" in vehicle:
		vehicle.is_player_driving = true

const MOUSE_SENSITIVITY = 0.002

func _ready():
	# Make sure Area3D process is running so we can check inputs
	set_process(true)
	set_process_unhandled_input(true)

func _unhandled_input(event):
	if current_driver and event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate horizontal (only the camera, not the chair)
		seat_camera.rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		# Rotate vertical (camera)
		seat_camera.rotation.x -= event.relative.y * MOUSE_SENSITIVITY
		
		# Clamp vertical rotation so we don't look too far up/down
		seat_camera.rotation.x = clamp(seat_camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))
		
		# Optional: Clamp horizontal rotation so the driver can't spin their head 360 degrees like an owl
		seat_camera.rotation.y = clamp(seat_camera.rotation.y, deg_to_rad(-120), deg_to_rad(120))
		
	# Check for exit input F
	if current_driver and event is InputEventKey:
		if event.physical_keycode == KEY_E and event.pressed and not event.echo:
			exit_seat()
			# Consume event
			get_viewport().set_input_as_handled()

func exit_seat():
	# Re-enable player physics and collision
	current_driver.set_physics_process(true)
	current_driver.get_node("CollisionShape3D").disabled = false
	current_driver.visible = true
	
	# Move player to a safe exit point (e.g. next to the seat)
	current_driver.global_position = global_position + global_transform.basis.x * 1.5
	
	# Switch back to player camera
	current_driver.get_node("Camera3D").current = true
	
	# Disable RV driving control
	if vehicle.has_method("set_driving_state"):
		vehicle.set_driving_state(false)
	elif "is_player_driving" in vehicle:
		vehicle.is_player_driving = false
		
	# Reset seat rotation to face forward again
	seat_camera.rotation = Vector3.ZERO
	
	current_driver = null
