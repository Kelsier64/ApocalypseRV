extends CharacterBody3D
class_name WhiteApparition
## Transient outdoor encounter. The player, camera, and apparition share a World3D.
const CENTER := Rect2(0.30, 0.30, 0.40, 0.40)
const CHEST := Vector3(0.0, 2.00, 0.0)
const HEAD := Vector3(0.0, 2.45, 0.0)
const BODY_CENTER := Vector3(0.0, 1.3, 0.0)
const BODY_VIEW_RADIUS := 2.5
const NEAR_SPAWN_MIN := 15.0
const NEAR_SPAWN_MAX := 25.0
const DISTANT_SPAWN_MIN := 40.0
const DISTANT_SPAWN_CHANCE := 0.4
const MAX_SPAWN_ATTEMPTS := 16
const GAZE_SECONDS := 0.6
const COVER_DESPAWN_SECONDS := 3.0
const UNSEEN_DESPAWN_SECONDS := 30.0
const PURSUIT_SPEED := 5.5
const PURSUIT_STEP_HEIGHT := 0.18
const MIN_SUPPORT_NORMAL_Y := 0.82
const SEATED_TORSO_RADIUS := 0.22

enum Phase { HIDDEN, VISIBLE, CONFIRMED }

@onready var _visual = $Visual
@onready var _body: CollisionShape3D = $CollisionShape3D
@onready var _capsule: CapsuleShape3D = _body.shape
var _rng := RandomNumberGenerator.new()
var _player: Node3D
var _world_id := 0
var _camera_id := 0
var _phase := Phase.HIDDEN
var _time_left := 0.0
var _gaze_elapsed := 0.0
var _unseen_elapsed := 0.0
var _covered_elapsed := 0.0
var _reposition_armed := false
var _appearance_origin := Vector3.INF

func _ready() -> void:
	_rng.randomize()
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
	_reposition_armed = false
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
			var origin := global_position
			_update_visible(camera, delta)
			if _phase != Phase.HIDDEN and global_position == origin:
				_pursue(delta)

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
		_reposition_armed = true
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
		_reposition_armed = true
		var distance := camera.get_camera_transform().origin.distance_to(to_global(CHEST))
		_player.drain_san(_san_drain_rate(distance) * delta)

	var seen := (chest_clear and chest_in_frame) or (head_clear and head_in_frame)
	var covered := not chest_clear and not head_clear
	_unseen_elapsed = 0.0 if seen else _unseen_elapsed + delta
	_covered_elapsed = _covered_elapsed + delta if covered else 0.0
	if _covered_elapsed >= COVER_DESPAWN_SECONDS or _unseen_elapsed >= UNSEEN_DESPAWN_SECONDS:
		_enter_hidden()
		return

	if _reposition_armed and not covered and not centered:
		var frustum := camera.get_frustum()
		if not _body_outside_view(global_position, frustum): return
		_reposition_armed = false
		var point := _find_reposition(camera, frustum)
		if point.is_finite():
			var observer := camera.get_camera_transform().origin
			global_position = point
			look_at(Vector3(observer.x, point.y, observer.z))
			reset_physics_interpolation()

func _pursue(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var toward := (_player.global_position - global_position).slide(Vector3.UP)
	var stride := toward.limit_length(PURSUIT_SPEED * delta)
	if not toward.is_zero_approx():
		look_at(global_position + toward)

	# Try the direct step first, then steer to either side of a local obstacle.
	for angle: float in [0.0, 55.0, -55.0, 85.0, -85.0]:
		var next := global_position + stride.rotated(Vector3.UP, deg_to_rad(angle))
		var ground := _grounded_position(space, next, 0.25, 0.40)
		var motion := ground - global_position if ground.is_finite() else Vector3.ZERO
		var hit := move_and_collide(motion, true, safe_margin, true)
		if hit != null and hit.get_collider() == _player:
			move_and_collide(motion, false, safe_margin, true)
			_player.kill()
			return
		if hit == null and ground.is_finite():
			move_and_collide(motion)
			break
		if hit != null and _step_over_ground_lip(hit, motion):
			break

	if _touching_seated_player(space):
		_player.kill()

func _step_over_ground_lip(hit: KinematicCollision3D, motion: Vector3) -> bool:
	if hit.get_normal().y < MIN_SUPPORT_NORMAL_Y or not _is_terrain_support(hit.get_collider()): return false
	var across := motion.slide(Vector3.UP)
	if across.is_zero_approx(): return false
	# Road and ground meshes can meet under the leading edge of the capsule.
	# Sweep a small lift, the original stride, and the descent separately.
	var lift := Vector3.UP * PURSUIT_STEP_HEIGHT
	if test_move(global_transform, lift) or test_move(global_transform.translated(lift), across): return false
	move_and_collide(lift)
	move_and_collide(across)
	var landing := move_and_collide(Vector3.UP * (motion.y - PURSUIT_STEP_HEIGHT))
	if landing != null and landing.get_collider() == _player:
		_player.kill()
	return true

func _touching_seated_player(space: PhysicsDirectSpaceState3D) -> bool:
	# Seats disable the player's normal capsule. Use the posed torso, and let
	# solid chassis, panels and furniture block contact with it.
	if not is_instance_valid(_player.get("seated_in")): return false
	var torso: Vector3 = _player.execution_contact_position()
	var base := global_position
	var axis_point := Vector3(base.x, clampf(torso.y, base.y + _capsule.radius,
		base.y + _capsule.height - _capsule.radius), base.z)
	if axis_point.distance_to(torso) > _capsule.radius + SEATED_TORSO_RADIUS: return false
	var query := PhysicsRayQueryParameters3D.create(axis_point, torso, collision_mask)
	query.hit_from_inside = true
	return space.intersect_ray(query).is_empty()

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

func _body_outside_view(point: Vector3, frustum: Array[Plane]) -> bool:
	# Leave room for the whole animated silhouette and its echoes at screen edges.
	var center := point + BODY_CENTER
	for plane in frustum:
		if plane.distance_to(center) > BODY_VIEW_RADIUS: return true
	return false

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
	reset_physics_interpolation()
	_appearance_origin = point
	_phase = Phase.VISIBLE
	_time_left = _rng.randf_range(6.0, 10.0)
	_visual.begin_appearance()
	show()
	return true

func _find_emergence(camera: Camera3D, distant: bool) -> Vector3:
	var min_distance := DISTANT_SPAWN_MIN if distant else NEAR_SPAWN_MIN
	var max_distance := camera.far
	var environment := camera.environment if camera.environment != null else get_world_3d().environment
	if environment != null and environment.fog_enabled and environment.fog_mode == Environment.FOG_MODE_DEPTH and environment.fog_density >= 0.999:
		max_distance = minf(max_distance, environment.fog_depth_end)
	if not distant: max_distance = minf(max_distance, NEAR_SPAWN_MAX)
	if max_distance <= min_distance: return Vector3.INF

	var view := camera.get_camera_transform()
	var forward := Vector3.UP.cross(view.basis.x).normalized()
	var frustum := camera.get_frustum()
	var space := get_world_3d().direct_space_state
	for attempt in MAX_SPAWN_ATTEMPTS:
		var angle := deg_to_rad(_rng.randf_range(70.0, 170.0))
		if _rng.randf() < 0.5: angle = -angle
		var radius := _rng.randf_range(min_distance, max_distance)
		if distant:
			# Sample the start of the far band first, then search out to the view limit.
			radius = minf(46.0, max_distance) if attempt == 0 else min_distance * pow(max_distance / min_distance, _rng.randf())
		var point := _grounded_position(space, view.origin + forward.rotated(Vector3.UP, angle) * radius, 24.0, 24.0)
		if not point.is_finite() or _appearance_origin.distance_squared_to(point) < 9.0: continue
		if not _body_outside_view(point, frustum): continue
		var chest := point + CHEST
		if view.origin.distance_to(chest) > max_distance: continue
		if not _clear_sight(camera, chest) or not _clear_sight(camera, point + HEAD): continue
		if not space.intersect_shape(_clearance_at(point), 1).is_empty(): continue
		return point
	return Vector3.INF

func _grounded_position(space: PhysicsDirectSpaceState3D, point: Vector3, above: float, below: float) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * above, point - Vector3.UP * below, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < MIN_SUPPORT_NORMAL_Y or not _is_terrain_support(hit.collider): return Vector3.INF
	return hit.position + Vector3.UP * (_capsule.radius * (1.0 / hit.normal.y - 1.0) + 0.04)

func _is_terrain_support(collider: Object) -> bool:
	# Only streamed terrain and road collision can support an emergence. Roofs,
	# props, and bridges can otherwise be mistaken for level terrain by a ray.
	if not collider is StaticBody3D: return false
	var surface := (collider as StaticBody3D).get_parent()
	return surface is MeshInstance3D and surface.get_parent() is ChunkGenerator and surface.name in [&"Ground", &"Road"]

func _clearance_at(point: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform = Transform3D(Basis.IDENTITY, point + _body.position)
	return query

func _find_reposition(camera: Camera3D, frustum: Array[Plane]) -> Vector3:
	var space := get_world_3d().direct_space_state
	var observer := camera.get_camera_transform().origin
	var offset := (global_position - observer).slide(Vector3.UP)
	var bearing := offset.normalized()
	if bearing.is_zero_approx(): return Vector3.INF
	var side := -1.0 if _rng.randf() < 0.5 else 1.0

	# Change sides around the observer so even a nearby apparition jumps far.
	for radius: float in [clampf(offset.length() * 0.75, 12.0, 22.0), 30.0]:
		for angle: float in [60.0, -60.0, 75.0, -75.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0]:
			var direction := bearing.rotated(Vector3.UP, deg_to_rad(angle) * side)
			var point := _grounded_position(space, observer + direction * radius, 6.0, 10.0)
			if not point.is_finite() or not _body_outside_view(point, frustum): continue
			if not space.intersect_shape(_clearance_at(point), 1).is_empty(): continue
			if not _clear_sight(camera, point + CHEST) or not _clear_sight(camera, point + HEAD): continue
			return point
	return Vector3.INF
