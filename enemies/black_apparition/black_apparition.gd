extends CharacterBody3D
class_name BlackApparition

const Perception := preload("res://core/apparition_perception.gd")
const Exposure := preload("res://core/apparition_light_exposure.gd")
const CENTER := Rect2(0.30, 0.30, 0.40, 0.40)
const GAZE_SECONDS := 2.0
const CHASE_SPEED := 6.5
const LOST_SECONDS := 10.0
const LIGHT_INTERVAL := 0.1
const REPATH_INTERVAL := 0.25
const SPAWN_ATTEMPTS := 24

enum Phase { HIDDEN, OBSERVING, FRENZIED }

@onready var _visual = $Visual
@onready var _body: CollisionShape3D = $CollisionShape3D
@onready var _capsule: CapsuleShape3D = _body.shape
var phase := Phase.HIDDEN
var _player: CharacterBody3D
var _indoors := false
var _rng := RandomNumberGenerator.new()
var _gaze_time := 0.0
var _gaze_camera: Camera3D
var _relocation_time := 0.0
var _light_time := 0.0
var _lost_time := 0.0
var _last_seen := Vector3.ZERO
var _path := PackedVector3Array()
var _path_index := 0
var _repath_time := 0.0
var _daylight := false

func configure(player: CharacterBody3D, indoors: bool) -> void:
	_player = player
	_indoors = indoors
	# Some interior doorways are lower than the outdoor model.
	var factor := 0.88 if indoors else 1.0
	_capsule = _capsule.duplicate() as CapsuleShape3D
	_capsule.height *= factor
	_capsule.radius *= factor
	_body.shape = _capsule
	_body.position.y = _capsule.height * 0.5
	_visual.scale = Vector3.ONE * factor

func set_daylight(daylight: bool) -> void:
	_daylight = daylight and not _indoors

func try_emerge() -> bool:
	var camera := Perception.player_camera(self, _player)
	if camera == null: return false
	var point := _find_dark_spot(camera)
	if not point.is_finite(): return false
	emerge(point, camera)
	return true

func emerge(at: Vector3, camera: Camera3D) -> void:
	global_position = at
	var facing := (camera.global_position - at).slide(Vector3.UP)
	if not facing.is_zero_approx(): look_at(at + facing)
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_visual.begin_appearance()
	_visual.focus = camera.global_position
	phase = Phase.OBSERVING
	_gaze_camera = camera
	_gaze_time = 0.0
	_light_time = 0.0
	_relocation_time = _rng.randf_range(12.0, 24.0)
	show()

func _physics_process(delta: float) -> void:
	if phase == Phase.HIDDEN or not WorldEntities.same_world(self, _player) or not PlayerSurvival.simulation_active(_player):
		_gaze_time = 0.0
		return
	var camera := Perception.player_camera(self, _player)
	if camera == null:
		_gaze_time = 0.0
		return
	if _touches_player():
		_player.kill()
		_retire()
		return
	if phase == Phase.FRENZIED:
		_chase(camera, delta)
	else:
		_observe(camera, delta)

func _observe(camera: Camera3D, delta: float) -> void:
	_visual.focus = camera.global_position
	if _daylight and _outside_view(camera, global_position):
		_retire()
		return
	if camera != _gaze_camera:
		_gaze_camera = camera
		_gaze_time = 0.0
	var points: PackedVector3Array = _visual.gaze_points()
	if points.size() != 2: points = _body_points(global_position)
	var watched := (Perception.point_in_frame(camera, points[0], CENTER) or Perception.point_in_frame(camera, points[1], CENTER)) \
		and camera.is_position_in_frustum(points[1]) and Perception.clear_sight(camera, _player, points[0]) \
		and Perception.clear_sight(camera, _player, points[1])
	_gaze_time = _gaze_time + delta if watched else 0.0
	if _gaze_time >= GAZE_SECONDS:
		_frenzy()
		return
	_light_time -= delta
	if _light_time <= 0.0:
		_light_time = LIGHT_INTERVAL
		points.append(global_position + Vector3.UP * (_capsule.height * 0.29))
		if Exposure.is_exposed(self, points, Exposure.active_lights(self)):
			_frenzy()
			return
	_relocation_time -= delta
	if _relocation_time <= 0.0 and _outside_view(camera, global_position):
		_relocation_time = _rng.randf_range(12.0, 24.0)
		var point := _find_dark_spot(camera)
		if point.is_finite(): emerge(point, camera)

func _frenzy() -> void:
	phase = Phase.FRENZIED
	_visual.running = true
	_last_seen = _player.global_position
	_lost_time = 0.0
	_repath_time = 0.0
	_path.clear()

func _chase(camera: Camera3D, delta: float) -> void:
	var head := global_position + Vector3.UP * (_capsule.height * 0.89)
	var sees_player := Perception.clear_sight(camera, _player, head)
	if sees_player:
		_last_seen = _player.global_position
		_lost_time = 0.0
	else:
		_lost_time += delta
		if _lost_time >= LOST_SECONDS and _outside_view(camera, global_position):
			_retire()
			return
	var toward := _chase_direction(sees_player, delta)
	if not toward.is_zero_approx(): look_at(global_position + toward)
	velocity.x = toward.x * CHASE_SPEED
	velocity.z = toward.z * CHASE_SPEED
	velocity.y = -0.5 if is_on_floor() else maxf(-24.0, velocity.y - 18.0 * delta)
	var before := global_position
	move_and_slide()
	_visual.advance_stride((global_position - before).slide(Vector3.UP).length(), delta)
	for index in get_slide_collision_count():
		if get_slide_collision(index).get_collider() == _player:
			_player.kill()
			_retire()
			return
	if _touches_player():
		_player.kill()
		_retire()

func _chase_direction(sees_player: bool, delta: float) -> Vector3:
	# The same world's navmesh routes around walls and other solid obstacles.
	_repath_time -= delta
	if _repath_time <= 0.0:
		_repath_time = REPATH_INTERVAL
		var map := get_world_3d().navigation_map
		_path.clear()
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			_path = NavigationServer3D.map_get_path(map, global_position, _last_seen, true)
		_path_index = 0
	while _path_index < _path.size():
		var offset := _path[_path_index] - global_position
		var flat := offset.slide(Vector3.UP)
		if flat.length_squared() > 0.16: return flat.normalized()
		_path_index += 1
	if sees_player and absf(_last_seen.y - global_position.y) < 0.8:
		return (_last_seen - global_position).slide(Vector3.UP).normalized()
	return Vector3.ZERO

func _touches_player() -> bool:
	if Perception.touching_seated_player(self, _player, _capsule): return true
	if _player.global_position.distance_squared_to(global_position) > 9.0: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform = _body.global_transform
	query.collision_mask = _player.collision_layer
	query.margin = 0.015
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 12):
		if hit.collider == _player: return true
	return false

func _retire() -> void:
	phase = Phase.HIDDEN
	velocity = Vector3.ZERO
	hide()

func _outside_view(camera: Camera3D, point: Vector3) -> bool:
	var radius := 2.4 if phase == Phase.FRENZIED else 1.45
	var center := point + Vector3.UP * (_capsule.height * 0.5)
	for plane in camera.get_frustum():
		if plane.distance_to(center) > radius: return true
	return false

func _body_points(point: Vector3) -> PackedVector3Array:
	return PackedVector3Array([
		point + Vector3.UP * (_capsule.height * 0.72),
		point + Vector3.UP * (_capsule.height * 0.89)])

func _find_dark_spot(camera: Camera3D) -> Vector3:
	var space := get_world_3d().direct_space_state
	var map := get_world_3d().navigation_map
	var player_floor := _player.global_position
	if _indoors:
		if NavigationServer3D.map_get_iteration_id(map) == 0: return Vector3.INF
		player_floor = NavigationServer3D.map_get_closest_point(map, player_floor)
	var view_forward := -camera.global_basis.z.slide(Vector3.UP).normalized()
	if view_forward.is_zero_approx(): view_forward = Vector3.FORWARD
	var min_distance := 5.0 if _indoors else 20.0
	var max_distance := 17.0 if _indoors else 39.0
	var frustum_distance := minf(max_distance, camera.far)
	var environment := camera.environment if camera.environment != null else get_world_3d().environment
	if environment != null and environment.fog_enabled and environment.fog_mode == Environment.FOG_MODE_DEPTH and environment.fog_density >= 0.999:
		frustum_distance = minf(frustum_distance, environment.fog_depth_end)
	if frustum_distance <= min_distance: return Vector3.INF
	var lights := Exposure.active_lights(self)
	for _attempt in SPAWN_ATTEMPTS:
		var angle := deg_to_rad(_rng.randf_range(55.0, 178.0))
		if _rng.randf() < 0.5: angle = -angle
		var sample := player_floor + view_forward.rotated(Vector3.UP, angle) * _rng.randf_range(min_distance, frustum_distance)
		var point := _spawn_floor(space, map, sample)
		if not point.is_finite() or not _outside_view(camera, point): continue
		var distance := (point - player_floor).slide(Vector3.UP).length()
		if distance < min_distance or distance > frustum_distance: continue
		if phase != Phase.HIDDEN and point.distance_squared_to(global_position) < 16.0: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _capsule
		query.transform = Transform3D(Basis.IDENTITY, point + _body.position)
		query.collision_mask = collision_mask
		if not space.intersect_shape(query, 1).is_empty(): continue
		if _indoors:
			var path := NavigationServer3D.map_get_path(map, point, player_floor, true)
			if path.size() < 2 or path[-1].distance_to(player_floor) > 1.1: continue
		else:
			var points := _body_points(point)
			if not Perception.clear_sight(camera, _player, points[1]): continue
		var light_points := _body_points(point)
		light_points.append(point + Vector3.UP * (_capsule.height * 0.29))
		if not Exposure.is_exposed(self, light_points, lights): return point
	return Vector3.INF

func _spawn_floor(space: PhysicsDirectSpaceState3D, map: RID, sample: Vector3) -> Vector3:
	var height := 10.0
	if _indoors:
		var projected := NavigationServer3D.map_get_closest_point(map, sample)
		if absf(projected.y - sample.y) > 0.9 or projected.distance_to(sample) > 3.0: return Vector3.INF
		sample = projected
		height = 0.7
	var ray := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * height, sample - Vector3.UP * height, 1)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < 0.82: return Vector3.INF
	if not _indoors:
		var surface: Node = hit.collider.get_parent()
		if not surface is MeshInstance3D or not surface.get_parent() is ChunkGenerator or surface.name not in [&"Ground", &"Road"]: return Vector3.INF
	return hit.position + Vector3.UP * (_capsule.radius * (1.0 / hit.normal.y - 1.0) + 0.025)
