extends Camera3D
## Detached filming camera: smoothed free flight, a damped follow rig that leaves
## the keyboard to the player, a fixed tracking shot and spline rail playback.

signal rail_finished

enum Mode { FREE, FOLLOW, RAIL, TRACK }

const LOOK_SENSITIVITY := 0.0022
const LOOK_SMOOTHING := 14.0
const MOVE_SMOOTHING := 5.0
const FOV_SMOOTHING := 8.0
const FOLLOW_POSITION_SMOOTHING := 3.0
const FOLLOW_YAW_SMOOTHING := 1.6
const FOLLOW_AIM_SMOOTHING := 6.0
const FOLLOW_AIM_HEIGHT := 1.2
const MIN_SPEED := 0.25
const MAX_SPEED := 80.0
const MIN_FOV := 20.0
const MAX_FOV := 100.0

var mode := Mode.FREE
var speed := 5.0
var target_fov := 70.0
var move_input := Vector3.ZERO
var follow_target: Node3D
var follow_companion: Node3D
var follow_offset := Vector3(0, 3.2, 11)
var follow_aim_offset := Vector3(0, FOLLOW_AIM_HEIGHT, 0)
var rail: RefCounted
var rail_time := -1.0
var _yaw := 0.0
var _pitch := 0.0
var _target_yaw := 0.0
var _target_pitch := 0.0
var _velocity := Vector3.ZERO
var _follow_yaw := 0.0
var _follow_position := Vector3.ZERO
var _follow_aim := Vector3.ZERO
var _track_height := 0.0
## In TRACK mode, the player view this camera takes the picture back from.
var hold_over: Camera3D

func _ready() -> void:
	set_meta(&"promo_camera", true)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func start_from(source: Camera3D) -> void:
	global_transform = source.global_transform
	fov = source.fov
	target_fov = source.fov
	near = source.near
	far = source.far
	_sync_angles()
	_velocity = Vector3.ZERO
	mode = Mode.FREE
	make_current()

func look(relative: Vector2) -> void:
	if mode != Mode.FREE: return
	_target_yaw -= relative.x * LOOK_SENSITIVITY
	_target_pitch = clampf(_target_pitch - relative.y * LOOK_SENSITIVITY, -1.5, 1.5)

func adjust_speed(factor: float) -> void:
	speed = clampf(speed * factor, MIN_SPEED, MAX_SPEED)

func adjust_fov(step: float) -> void:
	target_fov = clampf(target_fov + step, MIN_FOV, MAX_FOV)

func free_flight() -> void:
	_stop_rail()
	follow_target = null
	_sync_angles()
	_velocity = Vector3.ZERO
	mode = Mode.FREE

## Keeps the current framing relative to the target's heading.
func follow_from_here(target: Node3D) -> void:
	_stop_rail()
	follow_target = target
	follow_companion = null
	_follow_yaw = _heading(target)
	follow_offset = Basis(Vector3.UP, _follow_yaw).inverse() * (global_position - target.global_position)
	follow_aim_offset = Vector3.UP * FOLLOW_AIM_HEIGHT
	_begin_follow()

func follow_with_offset(target: Node3D, offset: Vector3, aim_offset := Vector3(0, FOLLOW_AIM_HEIGHT, 0), companion: Node3D = null) -> void:
	_stop_rail()
	follow_target = target
	follow_companion = companion
	_follow_yaw = _heading(target)
	follow_offset = offset
	follow_aim_offset = aim_offset
	global_position = _follow_origin() + Basis(Vector3.UP, _follow_yaw) * offset
	_begin_follow()

## Stands still at `point` and keeps the target `height` metres above its origin in frame.
func track(target: Node3D, point: Vector3, height: float) -> void:
	_stop_rail()
	follow_target = target
	_track_height = height
	global_position = point
	_follow_aim = target.global_position + Vector3.UP * height
	mode = Mode.TRACK
	if not global_position.is_equal_approx(_follow_aim): look_at(_follow_aim)

func play(next_rail: RefCounted) -> bool:
	if next_rail == null or not next_rail.playable(): return false
	follow_target = null
	rail = next_rail
	rail_time = 0.0
	mode = Mode.RAIL
	_apply_rail(0.0)
	return true

func _begin_follow() -> void:
	_follow_position = global_position
	_follow_aim = _follow_origin() + Basis(Vector3.UP, _follow_yaw) * follow_aim_offset
	mode = Mode.FOLLOW
	if not global_position.is_equal_approx(_follow_aim): look_at(_follow_aim)

func _stop_rail() -> void:
	rail_time = -1.0

func _follow_origin() -> Vector3:
	var origin := follow_target.global_position
	return origin.lerp(follow_companion.global_position, 0.5) if is_instance_valid(follow_companion) else origin

func _process(delta: float) -> void:
	# Filming speed stays real-time under slow motion.
	var dt := delta / maxf(Engine.time_scale, 0.01)
	fov = lerpf(fov, target_fov, _blend(FOV_SMOOTHING, dt)) if mode != Mode.RAIL else fov
	match mode:
		Mode.FREE: _process_free(dt)
		Mode.FOLLOW: _process_follow(dt)
		Mode.RAIL: _process_rail(dt)
		Mode.TRACK: _process_track(dt)

func _process_free(dt: float) -> void:
	_yaw = lerp_angle(_yaw, _target_yaw, _blend(LOOK_SMOOTHING, dt))
	_pitch = lerpf(_pitch, _target_pitch, _blend(LOOK_SMOOTHING, dt))
	rotation = Vector3(_pitch, _yaw, 0.0)
	var wanted := global_basis * move_input.limit_length(1.0) * speed
	_velocity = _velocity.lerp(wanted, _blend(MOVE_SMOOTHING, dt))
	global_position += _velocity * dt

func _process_follow(dt: float) -> void:
	if not is_instance_valid(follow_target) or not follow_target.is_inside_tree():
		free_flight()
		return
	# Follow heading only: rolls, pitching and bumps of the target never reach the camera.
	_follow_yaw = lerp_angle(_follow_yaw, _heading(follow_target), _blend(FOLLOW_YAW_SMOOTHING, dt))
	var heading := Basis(Vector3.UP, _follow_yaw)
	var origin := _follow_origin()
	var wanted := origin + heading * follow_offset
	_follow_position = _follow_position.lerp(wanted, _blend(FOLLOW_POSITION_SMOOTHING, dt))
	_follow_aim = _follow_aim.lerp(origin + heading * follow_aim_offset, _blend(FOLLOW_AIM_SMOOTHING, dt))
	global_position = _follow_position
	if not global_position.is_equal_approx(_follow_aim): look_at(_follow_aim)

func _process_track(dt: float) -> void:
	if not is_instance_valid(follow_target) or not follow_target.is_inside_tree():
		free_flight()
		return
	# Runs after physics and before drawing, so a grab that takes the player's view back
	# during the physics step never reaches the picture.
	if is_instance_valid(hold_over) and hold_over.current: make_current()
	_follow_aim = _follow_aim.lerp(follow_target.global_position + Vector3.UP * _track_height, _blend(FOLLOW_AIM_SMOOTHING, dt))
	if not global_position.is_equal_approx(_follow_aim): look_at(_follow_aim)

func _process_rail(dt: float) -> void:
	rail_time += dt
	var progress := rail_time / maxf(float(rail.duration), 0.01)
	_apply_rail(progress)
	if progress >= 1.0:
		rail_time = -1.0
		free_flight()
		target_fov = fov
		rail_finished.emit()

func _apply_rail(progress: float) -> void:
	var frame: Dictionary = rail.sample(progress)
	if frame.is_empty(): return
	global_transform = frame.transform
	fov = frame.fov

func _sync_angles() -> void:
	var euler := global_basis.get_euler()
	_yaw = euler.y
	_pitch = euler.x
	_target_yaw = _yaw
	_target_pitch = _pitch

static func _heading(target: Node3D) -> float:
	var back := target.global_basis.z.slide(Vector3.UP)
	if back.length_squared() < 0.0001: return 0.0
	return atan2(back.x, back.z)

static func _blend(rate: float, dt: float) -> float:
	return 1.0 - exp(-rate * dt)
