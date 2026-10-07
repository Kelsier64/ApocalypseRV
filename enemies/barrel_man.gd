extends Monster
class_name BarrelMan
## Grounded barrel mimic. No inherited boarding, grabbing or melee processing.
enum Phase { DISGUISED, RISING, CHASE, RETRACTING, DETONATED }
const BARREL_RADIUS := 0.32959
const DISGUISED_HEIGHT := 1.0
const STANDING_HEIGHT := 1.9

@export var settings: BarrelManSettings = BarrelManSettings.new()
var phase: Phase = Phase.DISGUISED
var phase_elapsed := 0.0
var visual_height := 0.5
var horizontal_speed := 0.0
var target_vehicle: Node3D
var lost_interest_elapsed := 0.0
var _target_refresh := 0.0
var _collision_height := DISGUISED_HEIGHT
var _last_rise_fraction := 0.0
var _explosion_queued := false
var _remembered_player: Node3D
var _remembered_vehicle: Node3D
var _disguised_shape: CylinderShape3D
var _standing_shape: CapsuleShape3D
var _clearance_shape: CapsuleShape3D
var _cached_goal_vehicle: Node3D
var _vehicle_goal_local := Vector3.ZERO
## Negative means unarmed. Once started, target loss cannot cancel the fuse.
var proximity_fuse_remaining := -1.0
var _proximity_shape: SphereShape3D

func _ready() -> void:
	enable_boarding_visual = false
	max_health = settings.max_health
	monster_name = "油桶人"
	contact_damage = 0.0
	super._ready()
	if nav_agent:
		nav_agent.height = STANDING_HEIGHT
		nav_agent.radius = BARREL_RADIUS
		nav_agent.path_height_offset = 0.5
		nav_agent.target_desired_distance = 0.15
	_update_collision(DISGUISED_HEIGHT)

func _physics_process(delta: float) -> void:
	if is_dead: return
	# Check actual shape overlap even when stationary; broad HitBox notifications
	# alone must never make a nearby car explode the barrel ahead of contact.
	_check_body_contacts()
	if is_dead: return
	_update_proximity_fuse(delta)
	if is_dead: return
	_target_refresh -= delta
	if _target_refresh <= 0.0:
		_refresh_barrel_target()
		_target_refresh = 0.2
	nav_repath_timer = maxf(0.0, nav_repath_timer - delta)
	var live_target := is_instance_valid(target_player) or is_instance_valid(target_vehicle)
	if live_target: lost_interest_elapsed = 0.0
	else: lost_interest_elapsed = minf(settings.lose_interest_time, lost_interest_elapsed + delta)
	var desired := Vector3.ZERO
	match phase:
		Phase.DISGUISED:
			if live_target: _set_phase(Phase.RISING)
		Phase.RISING:
			if _can_fit_height(STANDING_HEIGHT):
				phase_elapsed = minf(phase_elapsed + delta, settings.rise_duration)
				_last_rise_fraction = clampf(phase_elapsed / maxf(settings.rise_duration, 0.001), 0.0, 1.0)
				_update_collision(lerpf(DISGUISED_HEIGHT, STANDING_HEIGHT, _last_rise_fraction))
				visual_height = lerpf(0.5, 1.4, _last_rise_fraction)
				if _last_rise_fraction >= 1.0: _set_phase(Phase.CHASE)
			if not live_target and lost_interest_elapsed >= settings.lose_interest_time: _set_phase(Phase.RETRACTING)
		Phase.CHASE:
			phase_elapsed = minf(60.0, phase_elapsed + delta)
			if live_target:
				var destination := _barrel_destination()
				var direction := _get_navigation_direction(destination)
				direction = item_detour.direction(self, destination, direction)
				var speed := settings.chase_speed
				if is_instance_valid(target_vehicle):
					speed = clampf(ClimbMath.point_velocity(target_vehicle, target_vehicle.global_position).slide(Vector3.UP).length() + settings.vehicle_speed_margin, settings.chase_speed, settings.vehicle_speed_cap)
				desired = direction * speed
			elif lost_interest_elapsed >= settings.lose_interest_time: _set_phase(Phase.RETRACTING)
		Phase.RETRACTING:
			phase_elapsed = minf(phase_elapsed + delta, settings.retract_duration)
			var progress := clampf(phase_elapsed / maxf(settings.retract_duration, 0.001), 0.0, 1.0)
			var fraction := _last_rise_fraction * (1.0 - progress)
			_update_collision(lerpf(DISGUISED_HEIGHT, STANDING_HEIGHT, fraction))
			visual_height = lerpf(0.5, 1.4, fraction)
			if live_target:
				_set_phase(Phase.RISING)
				phase_elapsed = fraction * settings.rise_duration
			elif progress >= 1.0: _set_phase(Phase.DISGUISED)
	var horizontal := velocity.slide(Vector3.UP).move_toward(desired, settings.acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor(): velocity.y -= gravity * delta
	else: velocity.y = minf(velocity.y, 0.0)
	contact_approach_velocity = velocity
	contact_sample_frame = Engine.get_physics_frames()
	move_and_slide()
	horizontal_speed = get_real_velocity().slide(Vector3.UP).length()
	if horizontal.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-horizontal.x, -horizontal.z), minf(1.0, delta * 7.0))
	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		_receive_body_contact(hit.get_collider(), hit.get_normal(), hit.get_position())
		if is_dead: return

func _set_phase(next: Phase) -> void:
	phase = next
	phase_elapsed = 0.0
	if next == Phase.RETRACTING: _last_rise_fraction = clampf((visual_height - 0.5) / 0.9, 0.0, 1.0)
	elif next == Phase.DISGUISED:
		visual_height = 0.5
		_last_rise_fraction = 0.0
		_remembered_player = null
		_remembered_vehicle = null
		_update_collision(DISGUISED_HEIGHT)
	elif next == Phase.CHASE:
		visual_height = 1.4
		_last_rise_fraction = 1.0
		_update_collision(STANDING_HEIGHT)

func _refresh_barrel_target() -> void:
	var nearest_player: Node3D
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group(Groups.PLAYER):
		if not candidate is Node3D or not WorldEntities.same_world(self, candidate) or candidate.get("is_player_dead") == true: continue
		var range_limit := settings.lose_interest_range if candidate == target_player or candidate == _remembered_player else settings.player_detection_range
		var distance := global_position.distance_to(candidate.global_position)
		var seated: Node = candidate.get("seated_in")
		var vehicle := RVConnection.resolve(seated) if is_instance_valid(seated) else null
		if vehicle != null: range_limit = settings.lose_interest_range if candidate == target_player or candidate == _remembered_player else settings.vehicle_detection_range
		if distance > range_limit or distance >= nearest_distance: continue
		if not _barrel_line_of_sight(candidate, vehicle): continue
		nearest_player = candidate
		nearest_distance = distance
	if nearest_player != null:
		target_player = nearest_player
		_remembered_player = nearest_player
		var seated: Node = nearest_player.get("seated_in")
		target_vehicle = RVConnection.resolve(seated) if is_instance_valid(seated) else null
		_remembered_vehicle = target_vehicle
		if target_vehicle != null: _cache_vehicle_goal(target_vehicle)
		return
	target_player = null
	var nearest_vehicle: Node3D
	nearest_distance = INF
	for candidate in get_tree().get_nodes_in_group(Groups.CHASSIS):
		if not candidate is Node3D or not WorldEntities.same_world(self, candidate): continue
		var range_limit := settings.lose_interest_range if candidate == target_vehicle or candidate == _remembered_vehicle else settings.vehicle_detection_range
		var distance := global_position.distance_to(_vehicle_surface(candidate))
		if distance > range_limit or distance >= nearest_distance or not _barrel_line_of_sight(candidate, candidate): continue
		nearest_vehicle = candidate
		nearest_distance = distance
	target_vehicle = nearest_vehicle
	if nearest_vehicle != null:
		_remembered_vehicle = nearest_vehicle
		_cache_vehicle_goal(nearest_vehicle)

func _barrel_line_of_sight(player_or_vehicle: Node3D, vehicle: Node3D = null) -> bool:
	var destination := _vehicle_surface(vehicle) if is_instance_valid(vehicle) else player_or_vehicle.global_position + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * visual_height, destination, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == player_or_vehicle or (is_instance_valid(vehicle) and RVConnection.resolve(hit.collider) == vehicle)

func _barrel_destination() -> Vector3:
	if is_instance_valid(target_vehicle):
		if _cached_goal_vehicle != target_vehicle: _cache_vehicle_goal(target_vehicle)
		# The nearest facet refreshes with perception; its local point follows the
		# car every frame without resampling the full hierarchy of collision shapes.
		return target_vehicle.to_global(_vehicle_goal_local)
	return target_player.global_position

func _cache_vehicle_goal(rv: Node3D) -> void:
	_cached_goal_vehicle = rv
	_vehicle_goal_local = rv.to_local(_vehicle_surface(rv))

func _vehicle_surface(rv: Node3D) -> Vector3:
	var nearest := rv.global_position
	var results: Array[CollisionShape3D] = []
	_collect_vehicle_shapes(rv, results)
	var distance := INF
	for collision in results:
		# Shape bounds determine a reachable exterior goal; collision detection
		# below still uses the actual physics shape rather than these nav bounds.
		var local := collision.to_local(global_position + Vector3.UP * visual_height)
		var bounds := collision.shape.get_debug_mesh().get_aabb()
		var point := collision.to_global(local.clamp(bounds.position, bounds.end))
		var candidate_distance := global_position.distance_squared_to(point)
		if candidate_distance < distance:
			nearest = point
			distance = candidate_distance
	return nearest

func _collect_vehicle_shapes(node: Node, result: Array[CollisionShape3D]) -> void:
	if node is Item: return
	if node is CollisionShape3D and not node.disabled and node.shape != null: result.append(node)
	for child in node.get_children(): _collect_vehicle_shapes(child, result)

func _update_collision(height: float) -> void:
	var disguised := is_equal_approx(height, DISGUISED_HEIGHT)
	if body_collision_shape != null and is_equal_approx(height, _collision_height):
		var existing := body_collision_shape.shape
		if disguised and existing is CylinderShape3D and is_equal_approx(existing.height, height): return
		if not disguised and existing is CapsuleShape3D and is_equal_approx(existing.height, height): return
	_collision_height = height
	if body_collision_shape == null: return
	var shape: Shape3D
	if disguised:
		if _disguised_shape == null:
			_disguised_shape = CylinderShape3D.new()
			_disguised_shape.radius = BARREL_RADIUS
			_disguised_shape.height = DISGUISED_HEIGHT
		shape = _disguised_shape
	else:
		if _standing_shape == null:
			_standing_shape = CapsuleShape3D.new()
			_standing_shape.radius = BARREL_RADIUS
		_standing_shape.height = height
		shape = _standing_shape
	body_collision_shape.shape = shape
	body_collision_shape.position.y = height * 0.5
	var hit_shape := get_node_or_null("HitBox/CollisionShape") as CollisionShape3D
	if hit_shape:
		hit_shape.shape = shape
		hit_shape.position.y = height * 0.5

func _can_fit_height(height: float) -> bool:
	if body_collision_shape == null: return true
	if _clearance_shape == null:
		_clearance_shape = CapsuleShape3D.new()
		_clearance_shape.radius = BARREL_RADIUS
	_clearance_shape.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _clearance_shape
	query.transform = global_transform
	query.transform.origin += Vector3.UP * (height * 0.5 + 0.04)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _check_body_contacts() -> void:
	if is_dead or body_collision_shape == null or body_collision_shape.disabled: return
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body_collision_shape.shape
	query.transform = body_collision_shape.global_transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.margin = 0.003
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		_receive_body_contact(hit.collider, Vector3.ZERO, global_position)
		if is_dead: return

func _update_proximity_fuse(delta: float) -> void:
	if is_dead: return
	if proximity_fuse_remaining >= 0.0:
		proximity_fuse_remaining = maxf(0.0, proximity_fuse_remaining - delta)
		# Thirty 60 Hz ticks can leave a sub-picosecond floating point remainder.
		if proximity_fuse_remaining <= 0.0000001:
			proximity_fuse_remaining = 0.0
			detonate()
		return
	if settings.proximity_trigger_radius <= 0.0: return
	var origin := _barrel_blast_origin()
	if _proximity_shape == null: _proximity_shape = SphereShape3D.new()
	# Include the exact tuned boundary despite float32 physics transforms.
	_proximity_shape.radius = settings.proximity_trigger_radius + 0.00001
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _proximity_shape
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 128):
		var body := hit.collider as CollisionObject3D
		if body == null or not WorldEntities.same_world(self, body): continue
		# Mounted Items and their child bodies never stand in for the vehicle.
		var owner: Node = body
		while owner != null and not owner is Item: owner = owner.get_parent()
		if owner is Item: continue
		if body.is_in_group(Groups.PLAYER):
			if body.get("is_player_dead") == true: continue
		elif RVConnection.resolve(body) == null: continue
		# Query actual body surfaces and visibility; neither a chassis centre nor
		# the predictive vehicle probe can start this timer through a wall.
		if not BarrelExplosion.has_visible_body_surface_in_range(self, body, origin, settings.proximity_trigger_radius): continue
		proximity_fuse_remaining = clampf(settings.proximity_fuse_duration, 0.0, 60.0)
		if proximity_fuse_remaining <= 0.0: detonate()
		return

func _receive_body_contact(body: Object, normal: Vector3, point: Vector3) -> void:
	if not body is Node3D or not WorldEntities.same_world(self, body) or body is Item: return
	var owner: Node = body
	while owner != null:
		if owner is Item: return
		owner = owner.get_parent()
	if body.is_in_group(Groups.PLAYER):
		if body.get("is_player_dead") != true: detonate()
		return
	var rv := RVConnection.resolve(body)
	if rv != null:
		if normal.is_zero_approx():
			point = global_position + Vector3.UP * visual_height
			normal = (point - rv.global_position).slide(Vector3.UP).normalized()
		receive_vehicle_body_contact(rv, normal, point)

func _on_hitbox_body_entered(_body: Node3D) -> void:
	# Defer a narrow check until physics has synchronized transforms.
	if not is_dead: _check_body_contacts.call_deferred()

func _apply_vehicle_contact(_rv: Node3D, _normal: Vector3, _point: Vector3) -> bool:
	# This is a predictive probe API and cannot detonate this species.
	return false

func receive_vehicle_body_contact(rv: Node3D, normal: Vector3, point: Vector3) -> bool:
	if not WorldEntities.same_world(self, rv): return false
	if is_dead: return _explosion_queued
	vehicle_impact_cooldown = settings.lose_interest_time
	var relative := ClimbMath.point_velocity(rv, point) - velocity
	var approach := maxf(0.0, relative.dot(normal))
	if rv.has_method("vehicle_impact_point_velocity"):
		approach = maxf(0.0, (rv.vehicle_impact_point_velocity(point) - velocity).dot(normal))
	if rv.has_method("queue_monster_impact") and approach > 0.1:
		rv.queue_monster_impact(self, normal, point, approach, false)
	detonate(rv)
	return true

func take_damage(amount: float) -> void:
	if is_dead or not is_finite(amount) or amount <= 0.0: return
	current_health -= amount
	if _body_mesh != null and _body_mesh.has_method("flash_damage"): _body_mesh.flash_damage()
	if current_health <= 0.0: detonate()
	elif phase == Phase.DISGUISED or phase == Phase.RETRACTING:
		var fraction := clampf((visual_height - 0.5) / 0.9, 0.0, 1.0)
		_set_phase(Phase.RISING)
		phase_elapsed = fraction * settings.rise_duration

func die() -> void:
	detonate()

func detonate(contacted_rv: Node3D = null) -> void:
	if is_dead or _explosion_queued: return
	is_dead = true
	_explosion_queued = true
	phase = Phase.DETONATED
	set_physics_process(false)
	var origin := _barrel_blast_origin()
	_resolve_explosion.call_deferred(origin, weakref(contacted_rv) if is_instance_valid(contacted_rv) else null)

func _barrel_blast_origin() -> Vector3:
	if _body_mesh != null and _body_mesh.has_method("get_blast_origin"): return _body_mesh.get_blast_origin()
	if has_node("BlastOrigin"): return get_node("BlastOrigin").global_position
	return global_position + Vector3.UP * visual_height

func _resolve_explosion(origin: Vector3, vehicle_ref: WeakRef) -> void:
	if body_collision_shape: body_collision_shape.disabled = true
	var explosion = load("res://enemies/barrel_explosion.gd")
	var rv: Node3D = vehicle_ref.get_ref() if vehicle_ref != null else null
	explosion.explode(self, origin, rv, settings)
	queue_free()

func capture_barrel_state() -> Dictionary:
	var state := {"phase": int(phase), "phase_elapsed": phase_elapsed, "visual_height": visual_height, "lost_interest_elapsed": lost_interest_elapsed}
	# Optional for backwards-compatible checkpoint v5 records.
	if proximity_fuse_remaining >= 0.0: state["proximity_fuse_remaining"] = proximity_fuse_remaining
	return state

static func validate_barrel_state(data: Variant) -> bool:
	if not data is Dictionary: return false
	if not data.get("phase") is int or data.phase < Phase.DISGUISED or data.phase > Phase.RETRACTING: return false
	for field in ["phase_elapsed", "visual_height", "lost_interest_elapsed"]:
		var value: Variant = data.get(field)
		if not (value is int or value is float) or not is_finite(float(value)): return false
	if data.phase_elapsed < 0.0 or data.phase_elapsed > 60.0 or data.lost_interest_elapsed < 0.0 or data.lost_interest_elapsed > 60.0: return false
	if data.visual_height < 0.5 or data.visual_height > 1.4: return false
	if data.phase == Phase.DISGUISED and not is_equal_approx(data.visual_height, 0.5): return false
	if data.phase == Phase.CHASE and not is_equal_approx(data.visual_height, 1.4): return false
	if data.has("proximity_fuse_remaining"):
		var fuse: Variant = data.proximity_fuse_remaining
		if not (fuse is int or fuse is float) or not is_finite(float(fuse)) or fuse < 0.0 or fuse > 60.0: return false
	return true

func restore_barrel_state(data: Dictionary) -> void:
	if not validate_barrel_state(data): return
	phase = data.phase
	phase_elapsed = data.phase_elapsed
	visual_height = data.visual_height
	lost_interest_elapsed = minf(data.lost_interest_elapsed, settings.lose_interest_time)
	proximity_fuse_remaining = data.get("proximity_fuse_remaining", -1.0)
	_last_rise_fraction = clampf((visual_height - 0.5) / 0.9, 0.0, 1.0)
	if phase == Phase.RISING: phase_elapsed = minf(phase_elapsed, settings.rise_duration)
	elif phase == Phase.RETRACTING:
		phase_elapsed = minf(phase_elapsed, settings.retract_duration)
		var remaining := 1.0 - phase_elapsed / maxf(settings.retract_duration, 0.001)
		_last_rise_fraction = minf(1.0, _last_rise_fraction / maxf(remaining, 0.001))
	target_player = null
	target_vehicle = null
	_target_refresh = 0.0
	_update_collision(visual_height + 0.5)
