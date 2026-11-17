extends Item

const MOUSE_SENSITIVITY: float = 0.002
const REST_CAMERA_ROTATION := Vector3(-0.12, 0.0, 0.0)
const IMPACT_SECONDS := 0.18

@onready var seat_camera: Camera3D = $Camera3D
@onready var game_settings = get_node("/root/GameSettings")

var current_driver: Node3D = null
var _camera_rest_position := Vector3.ZERO
var _last_driver_velocity := Vector3.ZERO
var _inertia_offset := Vector3.ZERO
var _impact_direction := Vector3.ZERO
var _impact_strength := 0.0
var _impact_age := IMPACT_SECONDS

func _ready() -> void:
	super._ready()
	if presentation_only: return
	_camera_rest_position = seat_camera.position
	seat_camera.rotation = REST_CAMERA_ROTATION
	seat_camera.cull_mask = (seat_camera.cull_mask & ~PlayerModelVisual.FULL_BODY_LAYER) | PlayerModelVisual.LOCAL_VIEW_LAYER
	seat_camera.fov = float(game_settings.get_setting(&"drive_fov"))
	game_settings.setting_changed.connect(_on_setting_changed)
	# Defer setup so the RV parent's _ready() (which calls add_to_group("rv"))
	# has already run before we walk up the tree looking for it.
	call_deferred("_setup_if_on_rv")

func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"drive_fov": seat_camera.fov = float(value)

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
	if not can_operate() or current_driver or not player.can_drive():
		return

	var rv := get_connected_rv()
	if not rv:
		print("Driver Seat: not mounted on an RV — cannot drive.")
		return

	# The player owns its mode state; refuse when it can't sit down right now.
	if not player.enter_seat_mode(self):
		return
	current_driver = player
	_last_driver_velocity = rv.linear_velocity
	_reset_camera_motion()
	seat_camera.current = true

	if rv.has_method("set_driving_state"):
		rv.set_driving_state(true, player)

func _unhandled_input(event: InputEvent) -> void:
	if not current_driver or current_driver.is_grabbed() or not current_driver.can_drive() or current_driver.is_gameplay_input_blocked():
		return
	if current_driver.handle_hotbar_input(event):
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := MOUSE_SENSITIVITY * float(game_settings.get_setting(&"sensitivity"))
		var y_direction := -1.0 if bool(game_settings.get_setting(&"invert_y")) else 1.0
		seat_camera.rotation.y -= event.relative.x * sensitivity
		seat_camera.rotation.x -= event.relative.y * sensitivity * y_direction
		seat_camera.rotation.x = clamp(seat_camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))
		seat_camera.rotation.y = clamp(seat_camera.rotation.y, deg_to_rad(-120), deg_to_rad(120))

	# Only fresh presses can trigger a drive action; skip the RV lookup otherwise.
	if event.is_pressed() and not event.is_echo():
		var rv := get_connected_rv()
		if rv:
			if event.is_action_pressed("drive_engine_toggle"): rv.set_engine_running(not rv.energy.engine_running)
			elif event.is_action_pressed("drive_headlights"): rv.headlights_requested = not rv.headlights_requested
			elif event.is_action_pressed("drive_handbrake"): rv.set_handbrake(not rv.handbrake)
			elif event.is_action_pressed("drive_gear_reverse"): rv.set_gear(-1)
			elif event.is_action_pressed("drive_gear_neutral"): rv.set_gear(0)
			elif event.is_action_pressed("drive_gear_forward"): rv.set_gear(1)
			elif event.is_action_pressed("drive_gear_up"): rv.set_gear(rv.gear + 1)
			elif event.is_action_pressed("drive_gear_down"): rv.set_gear(maxi(1, rv.gear - 1))
	if event.is_action_pressed("interact"):
		exit_seat()
		get_viewport().set_input_as_handled()

func exit_seat(forced: bool = false) -> void:
	if not current_driver:
		return

	var player := current_driver
	if forced: player.close_settings()
	var exit := _find_clear_exit(forced)
	if exit.is_empty():
		return
	current_driver = null

	var rv := get_connected_rv() as Chassis
	var leaves_rv := not forced and rv != null and rv.rollover_state() == Chassis.Rollover.UPRIGHT and ClimbMath.find_rv_ancestor(exit.support) != rv
	player.exit_seat_mode(exit.position, leaves_rv)

	if rv and rv.has_method("set_driving_state"):
		rv.set_driving_state(false)

	seat_camera.rotation = REST_CAMERA_ROTATION
	_reset_camera_motion()

func release_for_execution(player: Node3D) -> bool:
	if current_driver != player or player.seated_in != self: return false
	current_driver = null
	# The validated hand contact already chooses the release location. Keep
	# the body there so subsequent extraction is collision-swept by Player.
	player.exit_seat_mode(player.global_position)
	var rv := get_connected_rv()
	if rv and rv.has_method("set_driving_state"): rv.set_driving_state(false)
	seat_camera.rotation = REST_CAMERA_ROTATION
	_reset_camera_motion()
	return true

# Use the real standing collider and supported floor points, never teleport into geometry.
func _find_clear_exit(forced: bool = false) -> Dictionary:
	var candidates: Array[Vector3] = []
	var rv := get_connected_rv() as Chassis
	var overturned := rv != null and rv.rollover_state() != Chassis.Rollover.UPRIGHT
	if overturned:
		for z in [-4.5, -2.0, 0.0, 2.0, 4.5]:
			for x in [-3.8, 3.8]:
				candidates.append(rv.to_global(Vector3(0, 1.0, z)) + rv.global_basis.z.slide(Vector3.UP).normalized().cross(Vector3.UP) * x)
	else:
		for offset in [Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5), Vector3(0, 0, -1.5)]:
			candidates.append(to_global(offset))
		if rv:
			for z in [-3.0, -1.5, 0.0, 1.5, 3.0, 4.6]: candidates.append(rv.to_global(Vector3(0, 0.55, z)))
	if forced:
		for radius in [2.5, 4.0, 6.0]:
			for i in range(12): candidates.append(global_position + Vector3(cos(i * TAU / 12.0) * radius, 0, sin(i * TAU / 12.0) * radius))
	for candidate in candidates:
		var query := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * (2.0 if overturned else 0.4), candidate - Vector3.UP * (5.0 if forced or overturned else 0.8), 1, [get_rid(), current_driver.get_rid()])
		var floor_hit := get_world_3d().direct_space_state.intersect_ray(query)
		if floor_hit.is_empty() or floor_hit.normal.dot(Vector3.UP) < 0.7: continue
		if overturned and ClimbMath.find_rv_ancestor(floor_hit.collider) == rv: continue
		var point: Vector3 = floor_hit.position + Vector3.UP * 0.035
		if _is_exit_position_clear(point): return {"position": point, "support": floor_hit.collider}
	# Destruction must release player ownership even if the entire surrounding volume is blocked.
	# Find clear air immediately above; gravity then resolves the landing.
	if forced:
		for height in range(2, 21):
			var point := global_position + Vector3.UP * height
			if _is_exit_position_clear(point): return {"position": point, "support": null}
		return {"position": global_position + Vector3.UP * 22.0, "support": null}
	return {}

func _is_exit_position_clear(candidate: Vector3) -> bool:
	if not is_instance_valid(current_driver): return false
	var collider: CollisionShape3D = current_driver.body_collision_shape
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	var upright := Basis(Vector3.UP, current_driver.global_rotation.y)
	query.transform = Transform3D(upright, candidate) * collider.transform
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

func cabin_impact(world_direction: Vector3, strength: float) -> void:
	if not is_instance_valid(current_driver) or current_driver.is_grabbed(): return
	if _impact_age < IMPACT_SECONDS and strength <= _impact_strength: return
	_impact_direction = global_basis.orthonormalized().inverse() * world_direction
	_impact_strength = strength
	_impact_age = 0.0
	_inertia_offset = Vector3.ZERO

func _reset_camera_motion() -> void:
	_inertia_offset = Vector3.ZERO
	_impact_age = IMPACT_SECONDS
	_impact_strength = 0.0
	seat_camera.position = _camera_rest_position

func _physics_process(delta: float) -> void:
	if is_instance_valid(current_driver):
		var rv := get_connected_rv() as Chassis
		if not rv or not current_driver.can_drive():
			exit_seat(true)
			return
		var motion := rv.global_basis.inverse() * (_last_driver_velocity - rv.linear_velocity)
		var offset := Vector3.ZERO
		if _impact_age >= IMPACT_SECONDS:
			offset = (motion * rv.handling_profile.camera_inertia_scale).limit_length(0.08)
		_inertia_offset = _inertia_offset.lerp(offset, 1.0 - exp(-delta * 11.0))
		_last_driver_velocity = rv.linear_velocity
		if current_driver.is_grabbed(): return
		_impact_age = minf(_impact_age + delta, IMPACT_SECONDS)
		var thrust := smoothstep(0.0, 0.035, _impact_age) * (1.0 - smoothstep(0.035, 0.12, _impact_age))
		var shift := (_impact_direction * 0.15 + Vector3.DOWN * 0.045) * _impact_strength * thrust
		seat_camera.position = _camera_rest_position + _inertia_offset + shift
