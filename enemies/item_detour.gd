extends RefCounted
## Local cargo detours supplement the static navigation mesh without changing it.
var active := false
var _path := PackedVector3Array()
var _goal := Vector3.INF
var _next_refresh := 0

func direction(actor, destination: Vector3, preferred: Vector3) -> Vector3:
	active = false
	if not actor.is_inside_tree() or actor.body_collision_shape == null or preferred.is_zero_approx(): return preferred
	var origin: Vector3 = actor.global_position
	var offset := destination - origin
	offset.y = 0.0
	var goal := origin + preferred.normalized() * minf(offset.length(), 8.0)
	goal.y = origin.y
	if _clear(actor, origin, goal):
		_path.clear()
		return preferred
	if not _hits_fixed_item(actor, origin, goal): return preferred
	active = true
	while not _path.is_empty() and origin.distance_to(_path[0]) < 0.22: _path.remove_at(0)
	if _goal.distance_to(goal) > 0.6 or Time.get_ticks_msec() >= _next_refresh or (not _path.is_empty() and not _clear(actor, origin, _path[0])):
		_goal = goal
		_next_refresh = Time.get_ticks_msec() + 500
		_path = _build(actor, origin, goal)
	if _path.is_empty(): return Vector3.ZERO
	return (Vector3(_path[0].x, origin.y, _path[0].z) - origin).normalized()

func _query(actor, origin: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = actor.body_collision_shape.shape
	query.transform = actor.body_collision_shape.global_transform
	query.transform.origin += origin - actor.global_position + Vector3.UP * 0.04
	query.collision_mask = actor.collision_mask
	var excluded: Array[RID] = [actor.get_rid()]
	if is_instance_valid(actor.target_player): excluded.append(actor.target_player.get_rid())
	query.exclude = excluded
	return query

func _clear(actor, from: Vector3, to: Vector3) -> bool:
	var query := _query(actor, from)
	var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return false
	query.motion = to - from
	return space.cast_motion(query)[0] >= 0.999

func _hits_fixed_item(actor, from: Vector3, to: Vector3) -> bool:
	var query := _query(actor, from)
	var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
	query.motion = to - from
	var fraction: float = space.cast_motion(query)[0]
	query.transform.origin += query.motion * minf(1.0, fraction + 0.025)
	query.motion = Vector3.ZERO
	for hit in space.intersect_shape(query, 8):
		var owner := hit.collider as Node
		while owner != null:
			if owner is Item: return owner.is_fixed and not owner.presentation_only and owner.get_connected_rv() == null
			owner = owner.get_parent()
	return false

func _supported(actor, point: Vector3) -> bool:
	var shape_bounds: AABB = actor.body_collision_shape.transform * actor.body_collision_shape.shape.get_debug_mesh().get_aabb()
	var feet := point + Vector3.UP * shape_bounds.position.y
	var ray := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.5, feet - Vector3.UP * 0.5, actor.collision_mask, [actor.get_rid()])
	var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and not hit.collider is Item and hit.normal.dot(Vector3.UP) > 0.7

func _walkable_edge(actor, from: Vector3, to: Vector3) -> bool:
	if not _clear(actor, from, to): return false
	# A clear capsule sweep alone does not detect missing ground below a route.
	var samples := maxi(1, ceili(from.distance_to(to) / 0.75))
	for index in range(samples + 1):
		if not _supported(actor, from.lerp(to, float(index) / samples)): return false
	return true

func _build(actor, origin: Vector3, goal: Vector3) -> PackedVector3Array:
	var graph := AStar3D.new()
	graph.add_point(0, origin)
	graph.add_point(1, goal)
	var shape_bounds: AABB = actor.body_collision_shape.transform * actor.body_collision_shape.shape.get_debug_mesh().get_aabb()
	var margin := maxf(shape_bounds.size.x, shape_bounds.size.z) * 0.5 + 0.22
	var item_count := 0
	for item in actor.get_tree().get_nodes_in_group(Groups.ITEMS):
		if not item is Item or not item.is_fixed or item.presentation_only or not WorldEntities.same_world(actor, item) or item.get_connected_rv() != null: continue
		var bounds: AABB = item.global_transform * item.get_placement_bounds()
		if bounds.end.y < actor.body_collision_shape.global_position.y - shape_bounds.size.y * 0.5: continue
		var center := bounds.get_center()
		if Vector2(center.x - origin.x, center.z - origin.z).length() > 10.0: continue
		for x in [bounds.position.x - margin, bounds.end.x + margin]:
			for z in [bounds.position.z - margin, bounds.end.z + margin]:
				var point := Vector3(x, origin.y, z)
				if _clear(actor, point, point) and _supported(actor, point): graph.add_point(graph.get_available_point_id(), point)
		item_count += 1
		if item_count >= 12: break
	var ids := graph.get_point_ids()
	for index in ids.size():
		for next in range(index + 1, ids.size()):
			if _walkable_edge(actor, graph.get_point_position(ids[index]), graph.get_point_position(ids[next])):
				graph.connect_points(ids[index], ids[next])
	var route := graph.get_point_path(0, 1)
	if not route.is_empty(): route.remove_at(0)
	return route
