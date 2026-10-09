extends RefCounted
## Pursuit goals stay outside the chassis; the CharacterBody owns all motion.
## Speed is measured at the moving rear slot, including the RV's angular motion.
const ROOT_CLEARANCE := 4.0
const BODY_MARGIN := 1.25
const ROUTE_MARGIN := 2.85
const GAP_GAIN := 0.65
## Normal catch-up shares this limit with the actor's acceleration step.
## The collision envelope below still uses settings.braking for emergencies.
const FOLLOW_BRAKING := 2.0
const FOLLOW_RESPONSE_SECONDS := 1.0
const LOOKAHEAD_SECONDS := 0.9

var _vehicle_id := 0
var _shape_refresh := 0.0
var _chassis_shapes: Array[CollisionShape3D] = []
var _panel_shapes: Array[CollisionShape3D] = []
var _travel_direction := Vector3.ZERO

func reset() -> void:
	_vehicle_id = 0
	_shape_refresh = 0.0
	_chassis_shapes.clear()
	_panel_shapes.clear()
	_travel_direction = Vector3.ZERO

func constrain_velocity(actor: SlenderSpeaker, vehicle: Node3D, proposed_horizontal: Vector3, delta: float) -> Vector3:
	# Navigation can steer differently from the plan, and an RV can abruptly
	# stop against a tree. Check the actual post-acceleration velocity against
	# the current physical edge before the CharacterBody performs its sweep.
	# Emergency braking removes only an infeasible inward relative component;
	# ordinary acceleration, cornering and matched-speed pursuit are unchanged.
	if not is_instance_valid(vehicle) or not WorldEntities.same_world(actor, vehicle): return proposed_horizontal
	if _vehicle_id != vehicle.get_instance_id():
		reset()
		_vehicle_id = vehicle.get_instance_id()
		_refresh_shapes(vehicle)
	var right := vehicle.global_basis.x.slide(Vector3.UP).normalized()
	if right.length_squared() < 0.5: return proposed_horizontal
	var frame := Transform3D(Basis(right, Vector3.UP, right.cross(Vector3.UP)), vehicle.global_position)
	var footprint := _footprint(frame, true)
	if footprint.size.x <= 0.0 or footprint.size.z <= 0.0: return proposed_horizontal
	var local_actor := frame.affine_inverse() * actor.global_position
	local_actor.y = 0.0
	var near := _nearest_footprint(local_actor, footprint)
	var edge: Vector3 = frame * near.point
	var inward := (edge - actor.global_position).slide(Vector3.UP).normalized()
	if float(near.clearance) < 0.0: inward = -inward
	if inward.length_squared() < 0.5: return proposed_horizontal
	var edge_velocity := ClimbMath.point_velocity(vehicle, edge).slide(Vector3.UP)
	var closing := (proposed_horizontal - edge_velocity).dot(inward)
	if closing <= 0.0: return proposed_horizontal
	var available := maxf(0.0, float(near.clearance) - BODY_MARGIN - 0.08 - closing * maxf(delta, 0.0))
	var safe_closing := sqrt(2.0 * actor.settings.braking * available)
	if closing <= safe_closing: return proposed_horizontal
	return proposed_horizontal - inward * (closing - safe_closing)

func update(actor: SlenderSpeaker, vehicle: Node3D, delta: float) -> Dictionary:
	var stopped := {"navigation_point": actor.global_position, "speed": 0.0, "surface_point": actor.global_position, "gap": INF, "can_attack": false}
	if not is_instance_valid(vehicle) or not vehicle.is_inside_tree() or not WorldEntities.same_world(actor, vehicle):
		reset()
		return stopped
	if _vehicle_id != vehicle.get_instance_id():
		reset()
		_vehicle_id = vehicle.get_instance_id()
	_shape_refresh -= delta
	if _shape_refresh <= 0.0:
		_refresh_shapes(vehicle)
		_shape_refresh = 1.0
	var right := vehicle.global_basis.x.slide(Vector3.UP).normalized()
	if right.length_squared() < 0.5: return stopped
	var frame := Transform3D(Basis(right, Vector3.UP, right.cross(Vector3.UP)), vehicle.global_position)
	var footprint := _footprint(frame)
	if footprint.size.x <= 0.0 or footprint.size.z <= 0.0: return stopped
	var center := footprint.get_center()
	center.y = 0.0
	var vehicle_velocity := ClimbMath.point_velocity(vehicle, frame * center).slide(Vector3.UP)
	if vehicle_velocity.length() > 0.75:
		_travel_direction = vehicle_velocity.normalized()
	elif _travel_direction.length_squared() < 0.5:
		_travel_direction = -frame.basis.z
	# Projection support includes the real twelve-metre chassis, rather than
	# treating the remembered panel's centre as the vehicle's physical edge.
	var outward := frame.basis.inverse() * -_travel_direction
	var half := footprint.size * 0.5
	var extent := absf(outward.x) * half.x + absf(outward.z) * half.z
	var bumper := frame * (center + outward * extent)
	var slot := bumper - _travel_direction * ROOT_CLEARANCE
	slot.y = actor.global_position.y
	var slot_velocity := ClimbMath.point_velocity(vehicle, slot).slide(Vector3.UP)
	var local_actor := frame.affine_inverse() * actor.global_position
	var local_slot := frame.affine_inverse() * slot
	local_actor.y = 0.0
	local_slot.y = 0.0
	var route := _route_point(local_actor, local_slot, footprint)
	var routing: bool = route.distance_squared_to(local_slot) > 0.01
	var goal := frame * route
	goal.y = actor.global_position.y
	var navigation_point := goal
	if not routing and slot_velocity.length() > 0.1:
		# Keep NavigationAgent beyond its 1.5m arrival radius while the RV moves.
		# This prediction affects steering only; speed uses the actual slot error.
		navigation_point += slot_velocity.normalized() * maxf(2.0, slot_velocity.length() * LOOKAHEAD_SECONDS)
	var direction := (navigation_point - actor.global_position).slide(Vector3.UP).normalized()
	var slot_error := (goal - actor.global_position).slide(Vector3.UP)
	var feedforward := maxf(0.0, slot_velocity.dot(direction))
	var desired_speed := clampf(feedforward + slot_error.dot(direction) * GAP_GAIN, 0.0, actor.settings.chase_speed)
	var near := _nearest_footprint(local_actor, footprint)
	var clearance: float = near.clearance
	var nearest_world: Vector3 = frame * near.point
	var toward_body := (nearest_world - actor.global_position).slide(Vector3.UP).normalized()
	if direction.dot(toward_body) > 0.1:
		# Reserve a second of closing travel as well as the comfortable braking
		# distance. Solving v*T + v*v/(2*a) <= spare starts matching speed well
		# before the stand-off and eases the closing speed down continuously.
		var edge_velocity := ClimbMath.point_velocity(vehicle, nearest_world).slide(Vector3.UP)
		var edge_speed := maxf(0.0, edge_velocity.dot(toward_body))
		var closing := maxf(0.0, (actor.velocity.slide(Vector3.UP) - edge_velocity).dot(toward_body))
		var spare := maxf(0.0, clearance - ROOT_CLEARANCE - closing * maxf(delta, 0.0) - 0.08)
		var braking := minf(actor.settings.braking, FOLLOW_BRAKING)
		var response_speed := braking * FOLLOW_RESPONSE_SECONDS
		var safe_closing := sqrt(response_speed * response_speed + 2.0 * braking * spare) - response_speed
		var safe_speed := edge_speed + safe_closing
		desired_speed = minf(desired_speed, safe_speed / maxf(0.1, direction.dot(toward_body)))
	var surface := _nearest_panel_surface(actor, vehicle)
	var surface_point: Vector3 = surface.point
	var gap := actor.global_position.slide(Vector3.UP).distance_to(surface_point.slide(Vector3.UP))
	var surface_velocity := ClimbMath.point_velocity(vehicle, surface_point).slide(Vector3.UP)
	var relative_speed := (actor.velocity.slide(Vector3.UP) - surface_velocity).length()
	var map_ready := actor.giant_navigation_map.is_valid() and actor.nav_agent != null
	if map_ready: map_ready = NavigationServer3D.map_get_iteration_id(actor.giant_navigation_map) > 0
	return {
		"navigation_point": navigation_point,
		"speed": desired_speed if map_ready else 0.0,
		"surface_point": surface_point,
		"gap": gap,
		"can_attack": map_ready and surface.valid and not routing and clearance >= BODY_MARGIN + .08 and gap <= 5.5 and relative_speed <= 2.5,
		"standoff_point": slot,
		"clearance": clearance,
		"relative_speed": relative_speed,
	}

func _refresh_shapes(vehicle: Node3D) -> void:
	_chassis_shapes.clear()
	_panel_shapes.clear()
	for node in vehicle.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		var owner := shape.get_parent()
		while owner != null and not owner is CollisionObject3D: owner = owner.get_parent()
		if owner == vehicle: _chassis_shapes.append(shape)
		elif owner is RVStructurePanel and owner.get_connected_rv() == vehicle: _panel_shapes.append(shape)

func _shape_box(shape: Shape3D) -> AABB:
	if shape is BoxShape3D: return AABB(-shape.size * 0.5, shape.size)
	if shape is SphereShape3D: return AABB(-Vector3.ONE * shape.radius, Vector3.ONE * shape.radius * 2.0)
	if shape is CapsuleShape3D or shape is CylinderShape3D:
		var size := Vector3(shape.radius * 2.0, shape.height, shape.radius * 2.0)
		return AABB(-size * 0.5, size)
	var mesh := shape.get_debug_mesh()
	return mesh.get_aabb() if mesh != null else AABB()

func _footprint(frame: Transform3D, include_panels := false) -> AABB:
	var result := AABB()
	var have_point := false
	var inverse := frame.affine_inverse()
	var shapes: Array[CollisionShape3D] = []
	shapes.append_array(_chassis_shapes)
	if include_panels: shapes.append_array(_panel_shapes)
	for node in shapes:
		if not is_instance_valid(node) or node.disabled or node.shape == null: continue
		var owner := node.get_parent()
		while owner != null and not owner is CollisionObject3D: owner = owner.get_parent()
		if owner is RVStructurePanel and owner.is_destroyed: continue
		var box := _shape_box(node.shape)
		for index in 8:
			var point := inverse * (node.global_transform * box.get_endpoint(index))
			point.y = 0.0
			if not have_point:
				result = AABB(point, Vector3.ZERO)
				have_point = true
			else: result = result.expand(point)
	return result

func _nearest_footprint(point: Vector3, box: AABB) -> Dictionary:
	var end := box.end
	var nearest := Vector3(clampf(point.x, box.position.x, end.x), 0.0, clampf(point.z, box.position.z, end.z))
	var clearance := point.distance_to(nearest)
	if clearance < 0.0001:
		var distances := [point.x - box.position.x, end.x - point.x, point.z - box.position.z, end.z - point.z]
		var edge := 0
		for index in 4:
			if distances[index] < distances[edge]: edge = index
		match edge:
			0: nearest.x = box.position.x
			1: nearest.x = end.x
			2: nearest.z = box.position.z
			3: nearest.z = end.z
		clearance = -float(distances[edge])
	return {"point": nearest, "clearance": clearance}

func _route_point(actor: Vector3, goal: Vector3, box: AABB) -> Vector3:
	var blocked_box := box.grow(BODY_MARGIN)
	blocked_box.position.y = -1.0
	blocked_box.size.y = 2.0
	if not _crosses_box(actor, goal, blocked_box): return goal
	# A reversed RV may put the old rear slot inside the new approach route.
	# Traverse visible outside corners rather than taking a line through it.
	var route_box := box.grow(ROUTE_MARGIN)
	var best := actor
	var cost := INF
	for x in [route_box.position.x, route_box.end.x]:
		for z in [route_box.position.z, route_box.end.z]:
			var corner := Vector3(x, 0.0, z)
			if actor.distance_to(corner) < 1.6 or _crosses_box(actor, corner, blocked_box): continue
			var length := actor.distance_to(corner) + corner.distance_to(goal)
			if length < cost:
				best = corner
				cost = length
	if cost < INF: return best
	# If already too close, retreat to the nearest face before pursuing again.
	var nearest := _nearest_footprint(actor, box)
	var normal: Vector3 = (actor - nearest.point).normalized()
	if float(nearest.clearance) <= 0.0: normal = -normal
	if normal.length_squared() < 0.5: normal = Vector3.RIGHT
	return nearest.point + normal * ROOT_CLEARANCE

func _crosses_box(from: Vector3, to: Vector3, box: AABB) -> bool:
	return box.intersects_segment(from, to) != null

func _nearest_panel_surface(actor: SlenderSpeaker, vehicle: Node3D) -> Dictionary:
	var reference := actor.global_position + Vector3.UP * 3.0
	var nearest := actor._vehicle_surface(vehicle)
	var best := INF
	var valid := false
	for node in _panel_shapes:
		if not is_instance_valid(node) or node.disabled or node.shape == null: continue
		var panel := node.get_parent()
		while panel != null and not panel is CollisionObject3D: panel = panel.get_parent()
		if not panel is RVStructurePanel or panel.is_destroyed or panel.get_connected_rv() != vehicle: continue
		var box := _shape_box(node.shape)
		var local := node.to_local(reference)
		var closest := local.clamp(box.position, box.end)
		var point := node.to_global(closest)
		var distance := reference.distance_squared_to(point)
		if distance < best:
			best = distance
			nearest = point
			valid = true
	return {"point": nearest, "valid": valid}
