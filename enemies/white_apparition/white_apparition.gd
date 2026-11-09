extends Node3D
class_name WhiteApparition
## Transient outdoor encounter. The player, camera, and apparition share a World3D.
signal threshold_reached(player: Node3D)

const GazeTracker := preload("res://enemies/white_apparition/gaze_tracker.gd")
const CENTER := Rect2(0.30, 0.30, 0.40, 0.40)
const SPAWN_FRAME := Rect2(0.05, 0.05, 0.90, 0.90)
const CHEST := Vector3(0.0, 2.00, 0.0)
const HEAD := Vector3(0.0, 2.45, 0.0)
const MAX_GAZE_DISTANCE := 40.0
const MIN_SPAWN_DISTANCE := 10.0
const MAX_SPAWN_DISTANCE := 22.0
const MAX_SPAWN_ATTEMPTS := 16
const MAX_DRIFT := 2.0
const DRIFT_SPEED := 0.45
const FADE_IN := 0.7
const FADE_OUT := 0.35
const CONFIRMED_HOLD := 0.7
const COOLDOWN := 90.0
const MIN_PRESENCE := 0.7
const MIN_SUPPORT_NORMAL_Y := 0.82
const CLEARANCE_RADIUS := 0.44
const CLEARANCE_HEIGHT := 2.75

enum Phase { HIDDEN, VISIBLE, CONFIRMED, FADING, COOLDOWN }

@onready var _visual = $Visual
var _gaze := GazeTracker.new()
var _rng := RandomNumberGenerator.new()
var _player: Node3D
var _world_id := 0
var _camera_id := 0
var _phase := Phase.HIDDEN
var _time_left := 0.0
var _presence := 0.0
var _appearance_origin := Vector3.INF
var _capsule := CapsuleShape3D.new()

func _ready() -> void:
	_rng.randomize()
	_capsule.radius = CLEARANCE_RADIUS
	_capsule.height = CLEARANCE_HEIGHT
	_set_presence(0.0)

func configure(player: Node3D) -> void:
	if is_instance_valid(_player) and player == _player: return
	_player = player
	_world_id = 0
	_reset()

func _reset() -> void:
	_gaze.reset()
	_camera_id = 0
	_appearance_origin = Vector3.INF
	_enter_hidden()

func _enter_hidden() -> void:
	_phase = Phase.HIDDEN
	_time_left = _rng.randf_range(4.0, 8.0)
	_set_presence(0.0)
	if is_node_ready(): _visual.confirmed = 0.0

func _set_presence(amount: float) -> void:
	_presence = amount
	visible = amount > 0.0
	if is_node_ready(): _visual.set_presence(amount)

func _physics_process(delta: float) -> void:
	if not WorldEntities.same_world(self, _player) or _player.is_queued_for_deletion() or _player.get("is_player_dead") == true:
		if _world_id != 0:
			_world_id = 0
			_reset()
		return
	var world_id := get_world_3d().get_instance_id()
	if world_id != _world_id:
		_world_id = world_id
		_reset()
	var camera := _active_player_camera()
	if camera == null:
		_gaze.sample(false, delta)
		_camera_id = 0
		if _phase == Phase.VISIBLE:
			_enter_hidden()
		elif _phase in [Phase.CONFIRMED, Phase.FADING]:
			_finish_fade()
		return
	if _camera_id != camera.get_instance_id():
		_camera_id = camera.get_instance_id()
		_gaze.sample(false, 0.0)
	_time_left -= delta
	match _phase:
		Phase.HIDDEN:
			_gaze.sample(false, delta)
			if _time_left <= 0.0 and not _try_emerge(camera):
				_time_left = 2.0
		Phase.VISIBLE:
			_update_visible(camera, delta)
		Phase.CONFIRMED:
			if _time_left <= 0.0: _phase = Phase.FADING
		Phase.FADING:
			_gaze.sample(false, delta)
			_set_presence(move_toward(_presence, 0.0, delta / FADE_OUT))
			if _presence <= 0.0: _finish_fade()
		Phase.COOLDOWN:
			if _time_left <= 0.0: _reset()

func _active_player_camera() -> Camera3D:
	if _player.get("in_ui_mode") == true or _player.is_gameplay_input_blocked() or _player.is_grabbed(): return null
	var camera := get_viewport().get_camera_3d()
	var seat := _player.get("seated_in") as Node3D
	var player_camera := (seat.get("seat_camera") if is_instance_valid(seat) else _player.get("camera")) as Camera3D
	if camera == null or camera != player_camera or not WorldEntities.same_world(self, camera): return null
	return camera

func _update_visible(camera: Camera3D, delta: float) -> void:
	_set_presence(move_toward(_presence, 1.0, delta / FADE_IN))
	var points: PackedVector3Array = _visual.gaze_points()
	if points.size() != 2: points = PackedVector3Array([to_global(CHEST), to_global(HEAD)])
	if _gaze.sample(_can_confirm(camera, points[0], points[1]), delta):
		_phase = Phase.CONFIRMED
		_time_left = CONFIRMED_HOLD
		_visual.confirmed = 1.0
		_set_presence(1.0)
		if _gaze.completed: threshold_reached.emit(_player)
	elif _time_left <= 0.0:
		_phase = Phase.FADING
	else:
		_drift_toward_center(camera, delta)

func _finish_fade() -> void:
	_enter_hidden()
	if _gaze.completed:
		_phase = Phase.COOLDOWN
		_time_left = COOLDOWN

func _can_confirm(camera: Camera3D, chest: Vector3, head: Vector3) -> bool:
	if _presence < MIN_PRESENCE or not is_visible_in_tree(): return false
	if camera.get_camera_transform().origin.distance_squared_to(chest) > MAX_GAZE_DISTANCE * MAX_GAZE_DISTANCE: return false
	if not _point_in_frame(camera, chest, CENTER) or not camera.is_position_in_frustum(head): return false
	return _clear_sight(camera, chest, head)

func _point_in_frame(camera: Camera3D, point: Vector3, frame: Rect2) -> bool:
	if not camera.is_position_in_frustum(point): return false
	var viewport_rect := camera.get_viewport().get_visible_rect()
	if viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0: return false
	return frame.has_point((camera.unproject_position(point) - viewport_rect.position) / viewport_rect.size)

func _clear_sight(camera: Camera3D, chest: Vector3, head: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(camera.get_camera_transform().origin, chest)
	query.hit_from_inside = true
	if _player is CollisionObject3D: query.exclude = [_player.get_rid()]
	if not space.intersect_ray(query).is_empty(): return false
	query.to = head
	return space.intersect_ray(query).is_empty()

func _try_emerge(camera: Camera3D) -> bool:
	var camera_pose := camera.get_camera_transform()
	var forward := -camera_pose.basis.z.slide(Vector3.UP).normalized()
	if forward.length_squared() < 0.5: return false
	var anchor := camera_pose.origin
	anchor.y = _player.global_position.y
	var space := get_world_3d().direct_space_state
	for attempt in MAX_SPAWN_ATTEMPTS:
		var angle := deg_to_rad(_rng.randf_range(13.0, 35.0)) * (-1.0 if _rng.randf() < 0.5 else 1.0)
		var candidate := anchor + forward.rotated(Vector3.UP, angle) * _rng.randf_range(MIN_SPAWN_DISTANCE, MAX_SPAWN_DISTANCE)
		var point := _grounded_position(space, candidate, 6.0, 8.0)
		if not point.is_finite() or _appearance_origin.distance_squared_to(point) < 9.0: continue
		var chest := point + CHEST
		var distance := camera_pose.origin.distance_to(chest)
		if distance < MIN_SPAWN_DISTANCE or distance > MAX_SPAWN_DISTANCE: continue
		if not _point_in_frame(camera, chest, SPAWN_FRAME) or _point_in_frame(camera, chest, CENTER): continue
		if not _point_in_frame(camera, point + HEAD, SPAWN_FRAME): continue
		if not _clear_sight(camera, chest, point + HEAD) or not space.intersect_shape(_clearance_at(point), 1).is_empty(): continue
		global_position = point
		look_at(Vector3(anchor.x, point.y, anchor.z))
		_appearance_origin = point
		_gaze.begin_appearance()
		_phase = Phase.VISIBLE
		_time_left = _rng.randf_range(6.0, 10.0)
		return true
	return false

func _grounded_position(space: PhysicsDirectSpaceState3D, point: Vector3, above: float, below: float) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * above, point - Vector3.UP * below, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < MIN_SUPPORT_NORMAL_Y or not hit.collider is StaticBody3D: return Vector3.INF
	# Only streamed terrain and road collision can support an emergence. Roofs,
	# props, and bridges can otherwise be mistaken for level terrain by a ray.
	var surface := (hit.collider as StaticBody3D).get_parent()
	if not surface is MeshInstance3D or not surface.get_parent() is ChunkGenerator or surface.name not in [&"Ground", &"Road"]:
		return Vector3.INF
	return hit.position + Vector3.UP * (CLEARANCE_RADIUS * (1.0 / hit.normal.y - 1.0) + 0.04)

func _clearance_at(point: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (CLEARANCE_HEIGHT * 0.5))
	return query

func _drift_toward_center(camera: Camera3D, delta: float) -> void:
	var camera_pose := camera.get_camera_transform()
	var forward := -camera_pose.basis.z.slide(Vector3.UP).normalized()
	if forward.length_squared() < 0.5: return
	var offset := global_position - camera_pose.origin
	if offset.dot(forward) <= 0.0: return
	var right := forward.cross(Vector3.UP)
	var motion := right * clampf(-offset.dot(right), -DRIFT_SPEED * delta, DRIFT_SPEED * delta)
	if motion.length_squared() < 0.000001: return
	var current := global_position
	var target := current + motion
	var drift := (target - _appearance_origin).slide(Vector3.UP)
	if drift.length_squared() > MAX_DRIFT * MAX_DRIFT: return
	var space := get_world_3d().direct_space_state
	target = _grounded_position(space, target, 0.3, 0.3)
	if not target.is_finite() or not space.intersect_shape(_clearance_at(target), 1).is_empty(): return
	var query := _clearance_at(current)
	query.motion = target - current
	var safe := space.cast_motion(query)
	if safe.size() == 2 and safe[0] >= 1.0:
		global_position = target
