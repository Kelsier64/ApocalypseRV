extends Equipment

const MOUSE_SENSITIVITY: float = 0.002

@onready var seat_camera: Camera3D = $Camera3D

var current_driver: Node3D = null

func _ready() -> void:
	super._ready()
	var dashboard := CanvasLayer.new()
	dashboard.set_script(load("res://rv/vehicle_dashboard.gd"))
	add_child(dashboard)
	# Defer setup so the RV parent's _ready() (which calls add_to_group("rv"))
	# has already run before we walk up the tree looking for it.
	call_deferred("_setup_if_on_rv")

func _setup_if_on_rv() -> void:
	var rv := get_connected_rv()
	if not rv or rv.chassis_destroyed:
		return
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1
	collision_mask = 0
	_add_collision_exceptions_with_ancestors(get_parent())

func interact_hold(player: Node3D) -> void:
	if not can_operate() or current_driver:
		return

	var rv := get_connected_rv()
	if not rv or rv.chassis_destroyed:
		print("Driver Seat: not mounted on an RV — cannot drive.")
		return

	# The player owns its mode state; refuse when it can't sit down right now.
	if not player.enter_seat_mode(self):
		return
	current_driver = player
	seat_camera.current = true

	if rv.has_method("set_driving_state"):
		rv.set_driving_state(true)

func _unhandled_input(event: InputEvent) -> void:
	if not current_driver:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		seat_camera.rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		seat_camera.rotation.x -= event.relative.y * MOUSE_SENSITIVITY
		seat_camera.rotation.x = clamp(seat_camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))
		seat_camera.rotation.y = clamp(seat_camera.rotation.y, deg_to_rad(-120), deg_to_rad(120))

	if event is InputEventKey and event.pressed and not event.echo:
		var rv := get_connected_rv()
		if rv:
			match event.physical_keycode:
				KEY_B: rv.set_engine_running(not rv.energy.engine_running)
				KEY_SPACE: rv.handbrake = not rv.handbrake
				KEY_Z: rv.set_gear(-1)
				KEY_X: rv.set_gear(0)
				KEY_C: rv.set_gear(1)
				KEY_R: rv.set_gear(rv.gear + 1)
				KEY_T: rv.set_gear(maxi(1, rv.gear - 1))
	if event.is_action_pressed("interact"):
		exit_seat()
		get_viewport().set_input_as_handled()

func exit_seat() -> void:
	if not current_driver:
		return

	var player := current_driver
	current_driver = null

	player.exit_seat_mode(_find_clear_exit_position())

	var rv := get_connected_rv()
	if rv and rv.has_method("set_driving_state"):
		rv.set_driving_state(false)
		rv.handbrake = true

	seat_camera.rotation = Vector3.ZERO

# Prefer the seat's right side, then left/back/front; if every side is inside
# geometry (seat parked against a wall), stand the player on top of the seat.
func _find_clear_exit_position() -> Vector3:
	var candidates: Array[Vector3] = [
		global_position + global_transform.basis.x * 1.5,
		global_position - global_transform.basis.x * 1.5,
		global_position + global_transform.basis.z * 1.5,
		global_position - global_transform.basis.z * 1.5,
	]
	for candidate in candidates:
		if _is_exit_position_clear(candidate):
			return candidate
	return global_position + Vector3.UP * 1.2

func _is_exit_position_clear(candidate: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	# Probe at roughly the player's torso height above the exit spot.
	query.transform = Transform3D(Basis.IDENTITY, candidate + Vector3.UP * 0.9)
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [self.get_rid()]
	if is_instance_valid(current_driver): query.exclude.append(current_driver.get_rid())
	return get_world_3d().direct_space_state.intersect_shape(query, 4).is_empty()

func _on_before_destroy() -> void:
	if current_driver:
		exit_seat()

func _on_service_stopped() -> void:
	if is_instance_valid(current_driver):
		if current_driver.is_inside_tree() and is_inside_tree():
			exit_seat()
		else:
			current_driver = null

func _physics_process(_delta: float) -> void:
	if is_instance_valid(current_driver):
		var rv := get_connected_rv()
		if not rv or rv.chassis_destroyed or current_driver.is_player_dead:
			exit_seat()

func get_interaction_prompt(_player: Node3D) -> String:
	if not can_operate(): return "駕駛座｜尚未接入或已損壞"
	return "駕駛座｜長按 E 1 秒：入座\n入座後 B：發動／熄火（無電也可手動發動，需燃油）"
