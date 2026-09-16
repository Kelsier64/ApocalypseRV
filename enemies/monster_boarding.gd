class_name MonsterBoarding
extends RefCounted
## Monster-only intent and grip policy. ClimbMath/RVSupport still own geometry.
enum Mode { NONE, DOOR, ROOF }

var mode: Mode = Mode.NONE
var door: Node3D
var leaf: int = -1
var vehicle: Node3D
var target_vehicle: Node3D
var grip: float = 100.0
var recovery: float = 0.0
var settle: float = 0.0
var strain: float = 0.0
var slip := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var _sample_vehicle: Node3D
var _previous_pose := Transform3D.IDENTITY
var _previous_linear := Vector3.ZERO
var _previous_angular := Vector3.ZERO
var _acceleration := Vector3.ZERO
var _motion_samples: int = 0
var _scan_timer: float = 0.0
var _route_door: Node3D
var _route_leaf: int = -1
var cabin := preload("res://enemies/monster_cabin_route.gd").new()
var cabin_vehicle: Node3D
var cabin_exit_grace: float = 0.0

func _init() -> void:
	rng.randomize()

static func grab_probability(relative_velocity: Vector3, normal: Vector3, tolerance: float = 10.0) -> float:
	# Normal closing is impact; tangential speed is the hand slipping past a hold.
	var closing := maxf(0.0, -relative_velocity.dot(normal))
	var sliding := relative_velocity.slide(normal).length()
	return clampf(1.0 - maxf(0.0, closing + sliding - 3.0) / maxf(tolerance, 0.1), 0.0, 1.0)

func begin(actor, rv: Node3D, hit: Node3D, point: Vector3) -> void:
	vehicle = rv
	door = hit if hit.has_method("boarding_leaf_at") else null
	leaf = door.boarding_leaf_at(point) if door != null else -1
	mode = Mode.DOOR if leaf >= 0 else Mode.ROOF
	grip = actor.grip_capacity
	settle = actor.boarding_windup
	_sample_vehicle = null

func occupied(actor, rv: Node3D, hit: Node3D, point: Vector3) -> bool:
	var index: int = hit.boarding_leaf_at(point) if hit.has_method("boarding_leaf_at") else -1
	for other in actor.get_tree().get_nodes_in_group(Groups.MONSTERS):
		if other == actor or not is_instance_valid(other) or other.is_dead: continue
		if other.locomotion_state != other.LocomotionState.CLIMBING: continue
		if other.active_climb_rv != rv: continue
		if index >= 0 and other.boarding.door == hit and other.boarding.leaf == index: return true
		if other.global_position.distance_to(actor.global_position) < 0.95: return true
	return false

func release(reason: String, actor) -> void:
	door = null
	leaf = -1
	if reason == "roof reached":
		mode = Mode.ROOF
		settle = actor.boarding_windup
	else:
		mode = Mode.NONE
		vehicle = null
		recovery = actor.grab_retry_delay
		actor.climb_reenter_cooldown_remaining = recovery
		actor.ai_state = actor.State.CHASE
	_sample_vehicle = null

func tick(actor, delta: float) -> void:
	cabin.tick(delta)
	cabin_vehicle = null
	if actor.locomotion_state == actor.LocomotionState.NORMAL:
		for rv in actor.get_tree().get_nodes_in_group(Groups.CHASSIS):
			if WorldEntities.same_world(actor, rv) and cabin.inside(actor, rv):
				cabin_vehicle = rv
				break
	cabin_exit_grace = 2.0 if is_instance_valid(cabin_vehicle) else maxf(0.0, cabin_exit_grace - delta)
	recovery = maxf(0.0, recovery - delta)
	settle = maxf(0.0, settle - delta)
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.35
		target_vehicle = null
		if is_instance_valid(actor.target_player):
			for rv in actor.get_tree().get_nodes_in_group(Groups.CHASSIS):
				if WorldEntities.same_world(actor, rv) and actor.global_position.distance_to(rv.global_position) < actor.lose_interest_range:
					if actor._is_node_on_specific_rv_surface(actor.target_player, rv):
						target_vehicle = rv
						break
	var carrier: Node3D
	if actor.locomotion_state == actor.LocomotionState.CLIMBING:
		carrier = actor.active_climb_rv if is_instance_valid(actor.active_climb_rv) else null
	elif is_instance_valid(actor.rv_support.rv):
		carrier = actor.rv_support.rv
	# Floor contacts can be absent for one tick while a moving panel catches up.
	# Keep sampling the same carrier; reacquiring a hold is not acceleration from zero.
	if not is_instance_valid(carrier) and mode == Mode.ROOF and is_instance_valid(vehicle): carrier = vehicle
	if not is_instance_valid(carrier):
		_sample_vehicle = null
		strain = 0.0
		slip = Vector3.ZERO
		return
	_sample_motion(actor, carrier, delta)
	if actor.locomotion_state == actor.LocomotionState.CLIMBING:
		grip = maxf(0.0, grip - (actor.grip_drain + strain * actor.grip_strain_scale) * delta)
		if grip <= 0.0:
			actor._abort_climb("grip exhausted")
			return
		if strain > actor.brace_acceleration: settle = actor.boarding_windup
	elif on_roof(actor):
		if mode == Mode.NONE:
			mode = Mode.ROOF
			vehicle = carrier
			settle = actor.boarding_windup
		if strain > actor.brace_acceleration: settle = actor.boarding_windup
		if strain > actor.slip_acceleration:
			slip += -_acceleration.slide(Vector3.UP) * delta
		else:
			slip = slip.move_toward(Vector3.ZERO, delta * 5.0)
		slip = slip.limit_length(6.0)
	elif mode == Mode.ROOF and (is_instance_valid(actor.rv_support.rv) or actor.is_on_floor()):
		# A supported interior floor ends external boarding behavior.
		mode = Mode.NONE
		vehicle = null
		slip = Vector3.ZERO

func _sample_motion(actor, rv: Node3D, delta: float) -> void:
	var linear := Vector3.ZERO
	var angular := Vector3.ZERO
	if rv is RigidBody3D and not rv.freeze:
		linear = rv.linear_velocity
		angular = rv.angular_velocity
	elif _sample_vehicle == rv:
		linear = (rv.global_position - _previous_pose.origin) / delta
		angular = (rv.global_basis * _previous_pose.basis.inverse()).get_euler() / delta
	if _sample_vehicle == rv and (not rv is RigidBody3D or not rv.freeze or _motion_samples >= 2):
		var offset: Vector3 = actor.global_position - rv.global_position
		var acceleration := (linear - _previous_linear) / delta + ((angular - _previous_angular) / delta).cross(offset) + angular.cross(angular.cross(offset))
		_acceleration = _acceleration.lerp(acceleration, 1.0 - exp(-delta / 0.15))
		strain = _acceleration.length()
	else:
		_acceleration = Vector3.ZERO
		strain = 0.0
		if _sample_vehicle != rv: _motion_samples = 0
	_motion_samples += 1
	_sample_vehicle = rv
	_previous_pose = rv.global_transform
	_previous_linear = linear
	_previous_angular = angular

func on_roof(actor) -> bool:
	var surface: Node3D = actor.rv_support.surface if is_instance_valid(actor.rv_support.surface) else null
	if not is_instance_valid(surface) and actor.is_inside_tree():
		surface = actor._select_underfoot_equipment_target()
		if is_instance_valid(surface) and absf(actor.global_position.y - surface.global_position.y) > 0.4: return false
	return is_instance_valid(surface) and surface.get("structure_kind") == "roof"

func can_attack(actor, target: Node3D) -> bool:
	if recovery > 0.0: return false
	if cabin_exit_grace > 0.0 and is_instance_valid(actor.target_player) and not target.is_in_group(Groups.PLAYER): return false
	if mode == Mode.DOOR:
		return target == door and valid_door(actor) and settle <= 0.0 and grip > actor.grip_capacity * 0.2
	if actor.locomotion_state == actor.LocomotionState.CLIMBING:
		return mode == Mode.NONE # Legacy helper callers; real roof climbers cannot attack walls.
	if on_roof(actor) and settle > 0.0: return false
	if mode == Mode.ROOF and on_roof(actor) and not target.is_in_group(Groups.PLAYER):
		return target.get("structure_kind") == "roof" and actor._select_underfoot_equipment_target() == target and is_instance_valid(actor.target_player) and actor._is_tracking_target_below(actor.target_player.global_position)
	if is_instance_valid(target_vehicle) and not actor._is_on_rv_surface() and not target.is_in_group(Groups.PLAYER):
		return false
	return true

func valid_door(actor) -> bool:
	return is_instance_valid(door) and door.get_connected_rv() == actor.active_climb_rv and door.boarding_leaf_closed(leaf)

func hang_at_door(actor, delta: float) -> void:
	if not valid_door(actor):
		actor._abort_climb("door removed or opened")
		return
	actor.climb_wall_probe.force_raycast_update()
	if not actor.climb_wall_probe.is_colliding() or actor.climb_wall_probe.get_collider() != door or door.boarding_leaf_at(actor.climb_wall_probe.get_collision_point()) != leaf:
		actor._abort_climb("door contact lost")
		return
	actor._align_to_climb_wall(actor.active_climb_rv.global_basis.y)
	actor.velocity = Vector3.ZERO
	if grip <= actor.grip_capacity * 0.2:
		actor._move_with_climb_collision(Vector3.DOWN * 0.35 * delta)
		return
	if settle <= 0.0 and actor.attack_timer <= 0.0:
		actor._execute_attack_on_target(CombatTargeting.build_target(door, "equipment", "door_breach"))
		grip = maxf(0.0, grip - actor.grip_attack_cost)
		settle = actor.boarding_windup

func try_door_hold(actor) -> void:
	# A tall chassis can be the first contact below the chosen door. Clamber up
	# to the real leaf before hanging; never attack the frame as a substitute.
	if mode != Mode.ROOF or not is_instance_valid(_route_door): return
	var probe: RayCast3D = actor.climb_wall_probe
	if not probe.is_colliding() or probe.get_collider() != _route_door: return
	var point := probe.get_collision_point()
	var index: int = _route_door.boarding_leaf_at(point)
	if index < 0 or occupied(actor, actor.active_climb_rv, _route_door, point): return
	door = _route_door
	leaf = index
	mode = Mode.DOOR
	settle = actor.boarding_windup

func chase_destination(actor, destination: Vector3) -> Vector3:
	var routing_vehicle: Node3D = cabin_vehicle if is_instance_valid(cabin_vehicle) else target_vehicle
	if is_instance_valid(routing_vehicle):
		var routed: Vector3 = cabin.destination(actor, routing_vehicle, destination)
		if cabin.active: return routed
	if not is_instance_valid(target_vehicle) or actor._is_on_rv_surface(): return destination
	var rv := target_vehicle
	# Stay on the approaching side; never steer straight across the vehicle to a far door.
	if not is_instance_valid(_route_door) or _route_door.get_connected_rv() != rv:
		_route_door = null
		var best := 5.0
		for device in rv.get_equipment():
			if not device.has_method("boarding_leaf_closed"): continue
			var outward: Vector3 = device.global_basis.z
			if (actor.global_position - device.global_position).dot(outward) < 0.0: continue
			for index in range(device.leaf_count):
				var point: Vector3 = device.boarding_entry_point(index)
				var distance: float = actor.global_position.distance_to(point)
				if distance < best and not occupied(actor, rv, device, point):
					best = distance
					_route_door = device
					_route_leaf = index
	if is_instance_valid(_route_door):
		var point: Vector3 = _route_door.boarding_entry_point(_route_leaf)
		var outward: Vector3 = _route_door.global_basis.z
		if (actor.global_position - point).dot(outward) < -0.3:
			_route_door = null
			return destination
		if occupied(actor, rv, _route_door, point):
			_route_door = null
			return destination
		if not _route_door.boarding_leaf_closed(_route_leaf):
			# Enter through the actual opening, not a swinging leaf's current center.
			return point - Vector3.UP * 0.9 - outward * 1.0
		return point - Vector3.UP * 0.9 + outward * 0.35
	return destination

func describe(actor) -> String:
	if recovery > 0.0: return "失衡恢復"
	if is_instance_valid(cabin_vehicle): return "車內追擊／尋找出口"
	if mode == Mode.DOOR: return "掛門破門｜抓握 %d%%" % roundi(grip / actor.grip_capacity * 100.0)
	if mode == Mode.ROOF:
		if actor.locomotion_state == actor.LocomotionState.CLIMBING: return "登頂攀爬｜抓握 %d%%" % roundi(grip / actor.grip_capacity * 100.0)
		return "車頂抓穩" if settle > 0.0 else "車頂追擊／破頂"
	return "接近目標"
