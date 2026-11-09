extends Node3D
class_name WhiteApparition
## Transient outdoor encounter. The player, camera, and apparition share a World3D.
const CENTER := Rect2(0.30, 0.30, 0.40, 0.40)
const SPAWN_FRAME := Rect2(0.05, 0.05, 0.90, 0.90)
const CHEST := Vector3(0.0, 2.00, 0.0)
const HEAD := Vector3(0.0, 2.45, 0.0)
const NEAR_SPAWN_MIN := 15.0
const NEAR_SPAWN_MAX := 25.0
const DISTANT_SPAWN_MIN := 40.0
const DISTANT_SPAWN_CHANCE := 0.4
const MAX_SPAWN_ATTEMPTS := 16
const GAZE_SECONDS := 0.6
const COVER_DESPAWN_SECONDS := 3.0
const UNSEEN_DESPAWN_SECONDS := 8.0
const REPOSITION_DELAY := 0.35
const MAX_GROUND_STEP := 0.15
const MIN_SUPPORT_NORMAL_Y := 0.82
const CLEARANCE_RADIUS := 0.44
const CLEARANCE_HEIGHT := 2.75

enum Phase { HIDDEN, VISIBLE, CONFIRMED }

@onready var _visual = $Visual
var _rng := RandomNumberGenerator.new()
var _player: Node3D
var _world_id := 0
var _camera_id := 0
var _phase := Phase.HIDDEN
var _time_left := 0.0
var _gaze_elapsed := 0.0
var _unseen_elapsed := 0.0
var _covered_elapsed := 0.0
var _look_away_elapsed := 0.0
var _reposition_spent := false
var _reposition_target := Vector3.INF
var _appearance_origin := Vector3.INF
var _capsule := CapsuleShape3D.new()

func _ready() -> void:
	_rng.randomize()
	_capsule.radius = CLEARANCE_RADIUS
	_capsule.height = CLEARANCE_HEIGHT
	hide()

func configure(player: Node3D) -> void:
	if is_instance_valid(_player) and player == _player: return
	_player = player
	_world_id = 0
	_reset()

func _reset() -> void:
	_camera_id = 0
	_appearance_origin = Vector3.INF
	_enter_hidden()

func _enter_hidden() -> void:
	_phase = Phase.HIDDEN
	_time_left = _rng.randf_range(25.0, 40.0)
	_gaze_elapsed = 0.0
	_unseen_elapsed = 0.0
	_covered_elapsed = 0.0
	_look_away_elapsed = 0.0
	_reposition_spent = false
	_reposition_target = Vector3.INF
	hide()

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
	if not PlayerSurvival.simulation_active(_player): return

	var camera := _active_player_camera()
	if camera == null:
		_camera_id = 0
		if _phase == Phase.VISIBLE: _enter_hidden()
		return
	if _camera_id != camera.get_instance_id():
		_camera_id = camera.get_instance_id()
		_gaze_elapsed = 0.0
	if _phase != Phase.CONFIRMED:
		_time_left -= delta
	match _phase:
		Phase.HIDDEN:
			if _time_left <= 0.0 and not _try_emerge(camera):
				_time_left = 2.0
		Phase.VISIBLE, Phase.CONFIRMED:
			_update_visible(camera, delta)

func _active_player_camera() -> Camera3D:
	if _player.get("in_ui_mode") == true or _player.is_gameplay_input_blocked() or _player.is_grabbed(): return null
	var camera := get_viewport().get_camera_3d()
	var seat := _player.get("seated_in") as Node3D
	var player_camera := (seat.get("seat_camera") if is_instance_valid(seat) else _player.get("camera")) as Camera3D
	if camera == null or camera != player_camera or not WorldEntities.same_world(self, camera): return null
	return camera

func _update_visible(camera: Camera3D, delta: float) -> void:
	var points: PackedVector3Array = _visual.gaze_points()
	if points.size() != 2: points = PackedVector3Array([to_global(CHEST), to_global(HEAD)])
	var chest := points[0]
	var head := points[1]
	if _phase == Phase.CONFIRMED:
		_update_confirmed(camera, chest, head, delta)
		return

	_gaze_elapsed = _gaze_elapsed + delta if _can_confirm(camera, chest, head) else 0.0
	if _gaze_elapsed >= GAZE_SECONDS:
		_phase = Phase.CONFIRMED
	elif _time_left <= 0.0:
		_enter_hidden()

func _can_confirm(camera: Camera3D, chest: Vector3, head: Vector3) -> bool:
	if not is_visible_in_tree(): return false
	return _point_in_frame(camera, chest, CENTER) and camera.is_position_in_frustum(head) \
		and _clear_sight(camera, chest) and _clear_sight(camera, head)

func _update_confirmed(camera: Camera3D, chest: Vector3, head: Vector3, delta: float) -> void:
	var chest_clear := _clear_sight(camera, chest)
	var head_clear := _clear_sight(camera, head)
	var chest_in_frame := camera.is_position_in_frustum(chest)
	var head_in_frame := camera.is_position_in_frustum(head)
	var centered := _point_in_frame(camera, chest, CENTER)
	if centered and chest_clear and head_clear and head_in_frame:
		var distance := camera.get_camera_transform().origin.distance_to(to_global(CHEST))
		_player.drain_san(_san_drain_rate(distance) * delta)

	var seen := (chest_clear and chest_in_frame) or (head_clear and head_in_frame)
	var covered := not chest_clear and not head_clear
	_unseen_elapsed = 0.0 if seen else _unseen_elapsed + delta
	_covered_elapsed = _covered_elapsed + delta if covered else 0.0
	if _covered_elapsed >= COVER_DESPAWN_SECONDS or _unseen_elapsed >= UNSEEN_DESPAWN_SECONDS:
		_enter_hidden()
		return

	if covered or centered:
		_look_away_elapsed = 0.0
		_reposition_target = Vector3.INF
		return
	_look_away_elapsed += delta
	if _look_away_elapsed >= REPOSITION_DELAY:
		_reposition(camera, chest, delta)

static func _san_drain_rate(distance: float) -> float:
	if distance < 8.0: return 100.0 + (8.0 - distance) * 15.0
	if distance < 15.0: return lerpf(100.0, 50.0, (distance - 8.0) / 7.0)
	if distance < 25.0: return lerpf(50.0, 15.0, (distance - 15.0) / 10.0)
	var falloff := 25.0 / distance
	return 15.0 * falloff * falloff

func _point_in_frame(camera: Camera3D, point: Vector3, frame: Rect2) -> bool:
	if not camera.is_position_in_frustum(point): return false
	var viewport_rect := camera.get_viewport().get_visible_rect()
	if viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0: return false
	return frame.has_point((camera.unproject_position(point) - viewport_rect.position) / viewport_rect.size)

func _clear_sight(camera: Camera3D, point: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(camera.get_camera_transform().origin, point)
	query.hit_from_inside = true
	if _player is CollisionObject3D: query.exclude = [_player.get_rid()]
	return space.intersect_ray(query).is_empty()

func _try_emerge(camera: Camera3D) -> bool:
	var distant := _rng.randf() < DISTANT_SPAWN_CHANCE
	var point := _find_emergence(camera, distant)
	if not point.is_finite(): point = _find_emergence(camera, not distant)
	if not point.is_finite(): return false
	global_position = point
	var observer := camera.get_camera_transform().origin
	look_at(Vector3(observer.x, point.y, observer.z))
	_appearance_origin = point
	_phase = Phase.VISIBLE
	_time_left = _rng.randf_range(6.0, 10.0)
	_visual.begin_appearance()
	show()
	return true

func _find_emergence(camera: Camera3D, distant: bool) -> Vector3:
	var min_depth := DISTANT_SPAWN_MIN if distant else NEAR_SPAWN_MIN
	var max_depth := camera.far
	var environment := camera.environment if camera.environment != null else get_world_3d().environment
	if environment != null and environment.fog_enabled and environment.fog_mode == Environment.FOG_MODE_DEPTH and environment.fog_density >= 0.999:
		max_depth = minf(max_depth, environment.fog_depth_end)
	if not distant: max_depth = minf(max_depth, NEAR_SPAWN_MAX)
	if max_depth <= min_depth: return Vector3.INF

	var rect := camera.get_viewport().get_visible_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0: return Vector3.INF
	var view := camera.get_camera_transform()
	var space := get_world_3d().direct_space_state
	for attempt in MAX_SPAWN_ATTEMPTS:
		var x := _rng.randf_range(0.12, 0.26)
		if _rng.randf() < 0.5: x = 1.0 - x
		var depth := _rng.randf_range(min_depth, max_depth)
		if distant:
			x = _rng.randf_range(0.24, 0.76)
			# Sample the start of the far band first, then search out to the view limit.
			depth = minf(46.0, max_depth) if attempt == 0 else min_depth * pow(max_depth / min_depth, _rng.randf())
		var screen := rect.position + rect.size * Vector2(x, _rng.randf_range(0.42, 0.58))
		var point := _grounded_position(space, camera.project_position(screen, depth), 24.0, 24.0)
		if not point.is_finite() or _appearance_origin.distance_squared_to(point) < 9.0: continue
		var chest := point + CHEST
		var offset := chest - view.origin
		if offset.slide(Vector3.UP).length_squared() < 1.0: continue
		var distance := offset.length()
		if distance < min_depth or (not distant and distance > NEAR_SPAWN_MAX): continue
		if -view.basis.z.dot(offset) > max_depth: continue
		if not _point_in_frame(camera, chest, SPAWN_FRAME): continue
		if not distant and _point_in_frame(camera, chest, CENTER): continue
		if not _point_in_frame(camera, point + HEAD, SPAWN_FRAME): continue
		if not _clear_sight(camera, chest) or not _clear_sight(camera, point + HEAD): continue
		if not space.intersect_shape(_clearance_at(point), 1).is_empty(): continue
		return point
	return Vector3.INF

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

func _reposition(camera: Camera3D, chest: Vector3, delta: float) -> void:
	if _reposition_spent and not _reposition_target.is_finite(): return
	var current := global_position
	var chest_offset := chest - current
	var view := camera.get_camera_transform()
	var inward := (view.origin - current).slide(Vector3.UP)
	var distance := inward.length()
	var space := get_world_3d().direct_space_state
	if not _reposition_spent:
		_reposition_spent = true
		_reposition_target = _find_reposition(camera, chest, inward, distance, space)
	if not _reposition_target.is_finite(): return

	var speed := clampf(distance * 0.16, 3.5, 9.0)
	var step := current.move_toward(_reposition_target, minf(speed * delta, MAX_GROUND_STEP))
	step = _grounded_position(space, step, 0.3, 0.3)
	if not step.is_finite() or _point_in_frame(camera, step + chest_offset, CENTER) or not space.intersect_shape(_clearance_at(step), 1).is_empty():
		_reposition_target = Vector3.INF
		return
	var query := _clearance_at(current)
	query.motion = step - current
	var safe := space.cast_motion(query)
	if safe.size() != 2 or safe[0] < 1.0:
		_reposition_target = Vector3.INF
		return
	global_position = step
	if step.distance_squared_to(_reposition_target) < 0.0001:
		_reposition_target = Vector3.INF

func _find_reposition(camera: Camera3D, chest: Vector3, inward: Vector3, distance: float, space: PhysicsDirectSpaceState3D) -> Vector3:
	if distance < CLEARANCE_RADIUS: return Vector3.INF
	inward /= distance
	var approach := minf(clampf(distance * 0.20, 4.0, 13.0), distance * 0.6)
	var lateral := minf(clampf(distance * 0.22, 4.0, 16.0), distance * 0.35)
	var side := inward.cross(Vector3.UP) * lateral
	if camera.is_position_in_frustum(chest):
		var view := camera.get_camera_transform()
		var screen_side := (chest - view.origin).dot(view.basis.x)
		if side.dot(view.basis.x) * screen_side < 0.0: side = -side
	elif _rng.randf() < 0.5:
		side = -side
	var chest_offset := chest - global_position
	for offset in [side, -side]:
		var target := _grounded_position(space, global_position + inward * approach + offset, 2.0, 2.0)
		if target.is_finite() and not _point_in_frame(camera, target + chest_offset, CENTER) and space.intersect_shape(_clearance_at(target), 1).is_empty():
			return target
	return Vector3.INF
