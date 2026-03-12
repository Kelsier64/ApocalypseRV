extends Equipment

const MOUSE_SENSITIVITY: float = 0.002

@onready var seat_camera: Camera3D = $Camera3D

var current_driver: Node3D = null

func _ready() -> void:
	super._ready()
	# Defer setup so the RV parent's _ready() (which calls add_to_group("rv"))
	# has already run before we walk up the tree looking for it.
	call_deferred("_setup_if_on_rv")

func _setup_if_on_rv() -> void:
	var rv := get_connected_rv()
	if not rv:
		return
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1
	collision_mask = 0
	var ancestor := get_parent()
	while ancestor != null and ancestor is Node3D:
		if ancestor is CollisionObject3D:
			add_collision_exception_with(ancestor)
		ancestor = ancestor.get_parent()

func interact_hold(player: Node3D) -> void:
	if is_being_placed or current_driver:
		return

	var rv := get_connected_rv()
	if not rv:
		print("Driver Seat: not mounted on an RV — cannot drive.")
		return

	current_driver = player
	player.set_physics_process(false)
	player.get_node("CollisionShape3D").disabled = true
	player.visible = false
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

	if event is InputEventKey and event.physical_keycode == KEY_E and event.pressed and not event.echo:
		exit_seat()
		get_viewport().set_input_as_handled()

func exit_seat() -> void:
	if not current_driver:
		return

	var player := current_driver
	current_driver = null

	player.set_physics_process(true)
	player.get_node("CollisionShape3D").disabled = false
	player.visible = true
	player.global_position = global_position + global_transform.basis.x * 1.5
	player.get_node("Camera3D").current = true

	var rv := get_connected_rv()
	if rv and rv.has_method("set_driving_state"):
		rv.set_driving_state(false)

	seat_camera.rotation = Vector3.ZERO
