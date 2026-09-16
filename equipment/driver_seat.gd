extends Equipment

const MOUSE_SENSITIVITY: float = 0.002
const REST_CAMERA_ROTATION := Vector3(-0.18, 0.0, 0.0)

@onready var seat_camera: Camera3D = $Camera3D

var current_driver: Node3D = null
var exit_message: String = ""

func _ready() -> void:
	super._ready()
	seat_camera.rotation = REST_CAMERA_ROTATION
	var dashboard := CanvasLayer.new()
	dashboard.set_script(load("res://rv/vehicle_dashboard.gd"))
	add_child(dashboard)
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
	_add_collision_exceptions_with_ancestors(get_parent())

func interact_hold(player: Node3D) -> void:
	if not can_operate() or current_driver:
		return

	var rv := get_connected_rv()
	if not rv:
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
				KEY_L: rv.headlights_requested = not rv.headlights_requested
				KEY_SPACE: rv.handbrake = not rv.handbrake
				KEY_Z: rv.set_gear(-1)
				KEY_X: rv.set_gear(0)
				KEY_C: rv.set_gear(1)
				KEY_R: rv.set_gear(rv.gear + 1)
				KEY_T: rv.set_gear(maxi(1, rv.gear - 1))
	if event.is_action_pressed("interact"):
		exit_seat()
		get_viewport().set_input_as_handled()

func exit_seat(forced: bool = false) -> void:
	if not current_driver:
		return

	var player := current_driver
	var exit_position := _find_clear_exit_position(forced)
	if not exit_position.is_finite():
		exit_message = "離座位置被擋住，請先清出走道"
		return
	exit_message = ""
	current_driver = null

	player.exit_seat_mode(exit_position)

	var rv := get_connected_rv()
	if rv and rv.has_method("set_driving_state"):
		rv.set_driving_state(false)
		rv.handbrake = true

	seat_camera.rotation = REST_CAMERA_ROTATION

# Use the real standing collider and supported floor points, never teleport into geometry.
func _find_clear_exit_position(forced: bool = false) -> Vector3:
	var candidates: Array[Vector3] = []
	for offset in [Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5), Vector3(0, 0, -1.5)]:
		candidates.append(to_global(offset))
	var rv := get_connected_rv()
	if rv:
		for z in [-3.0, -1.5, 0.0, 1.5, 3.0, 4.6]: candidates.append(rv.to_global(Vector3(0, 0.55, z)))
	if forced:
		for radius in [2.5, 4.0, 6.0]:
			for i in range(12): candidates.append(global_position + Vector3(cos(i * TAU / 12.0) * radius, 0, sin(i * TAU / 12.0) * radius))
	for candidate in candidates:
		var query := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 0.4, candidate - Vector3.UP * (5.0 if forced else 0.8), 1, [get_rid(), current_driver.get_rid()])
		var floor_hit := get_world_3d().direct_space_state.intersect_ray(query)
		if floor_hit.is_empty() or floor_hit.normal.dot(Vector3.UP) < 0.7: continue
		var point: Vector3 = floor_hit.position + Vector3.UP * 0.035
		if _is_exit_position_clear(point): return point
	# Destruction must release player ownership even if the entire surrounding volume is blocked.
	# Find clear air immediately above; gravity then resolves the landing.
	if forced:
		for height in range(2, 21):
			var point := global_position + Vector3.UP * height
			if _is_exit_position_clear(point): return point
		return global_position + Vector3.UP * 22.0
	return Vector3.INF

func _is_exit_position_clear(candidate: Vector3) -> bool:
	if not is_instance_valid(current_driver): return false
	var collider: CollisionShape3D = current_driver.body_collision_shape
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = Transform3D(current_driver.global_basis, candidate) * collider.transform
	query.collision_mask = current_driver.collision_mask
	query.exclude = [current_driver.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _on_before_destroy() -> void:
	if current_driver:
		exit_seat(true)

func _on_service_stopped() -> void:
	if is_instance_valid(current_driver):
		if current_driver.is_inside_tree() and is_inside_tree():
			exit_seat(true)
		else:
			current_driver = null

func _physics_process(_delta: float) -> void:
	if is_instance_valid(current_driver):
		var rv := get_connected_rv()
		if not rv or current_driver.is_player_dead:
			exit_seat(true)

func get_interaction_prompt(_player: Node3D) -> String:
	if not can_operate(): return "駕駛座｜尚未接入或已損壞"
	return "駕駛座／控制台｜長按 E 1 秒：入座；長按 F：搬移整組\nB 引擎／L 頭燈／Space 手煞車／Z X C 排檔；需燃油"
