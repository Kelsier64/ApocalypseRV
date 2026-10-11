extends RefCounted
class_name CraftingOutputPlacement
## Keep manufactured bodies usable in cabins whose roof is lower than the bed + body.

static func is_clear(station: CraftingStation, item: Item, pose: Transform3D, exclude_station: bool) -> bool:
	for collider in item.get_children():
		if not collider is CollisionShape3D or collider.shape == null: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = collider.shape
		query.transform = pose * collider.transform
		query.collision_mask = 1
		if exclude_station: query.exclude = [station.get_rid()]
		if not station.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return false
	return true

static func body_floor_output(station: CraftingStation, item: Item) -> Dictionary:
	var space := station.get_world_3d().direct_space_state
	var facing := Basis(Vector3.UP, station.global_basis.get_euler().y)
	# Start the delivery path at floor height inside the printer footprint.
	# Only the printer is excluded from the sweep, never cabin walls or props.
	var start := Transform3D(facing, station.global_position + Vector3.UP * 0.06)
	var directions := [Vector3(0, 0, -1), Vector3.RIGHT, Vector3.LEFT, Vector3.BACK,
		Vector3(1, 0, -1).normalized(), Vector3(-1, 0, -1).normalized(),
		Vector3(1, 0, 1).normalized(), Vector3(-1, 0, 1).normalized()]
	for distance in [0.95, 1.25]:
		for direction in directions:
			var at: Vector3 = station.global_position + facing * direction * distance
			var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at - Vector3.UP * 0.8, 1, [station.get_rid()])
			var floor_hit := space.intersect_ray(ray)
			if floor_hit.is_empty() or floor_hit.normal.dot(Vector3.UP) < 0.95: continue
			# Do not stack bodies on a loose item or another newly printed body.
			if floor_hit.collider is Item and not floor_hit.collider.is_fixed: continue
			var pose := Transform3D(facing, floor_hit.position + Vector3.UP * 0.06)
			if not is_clear(station, item, pose, false): continue
			if not body_can_stand(station, pose): continue
			var clear_path := true
			for collider in item.get_children():
				if not collider is CollisionShape3D or collider.shape == null: continue
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = collider.shape
				query.transform = start * collider.transform
				query.collision_mask = 1
				query.exclude = [station.get_rid()]
				# cast_motion ignores starting overlap, so check it explicitly.
				if not space.intersect_shape(query, 1).is_empty():
					clear_path = false
					break
				query.motion = pose.origin - start.origin
				if space.cast_motion(query)[0] < 0.999:
					clear_path = false
					break
			if clear_path: return {"transform": pose}
	return {}

static func body_can_stand(station: CraftingStation, pose: Transform3D) -> bool:
	# Reserve the playable controller's 0.4m shoulder radius too. A narrow
	# idle-body fit (including a roof hatch) must not block control transfer.
	var standing := CapsuleShape3D.new()
	standing.radius = 0.4
	standing.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing
	query.transform = pose * Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0))
	query.collision_mask = 1
	return station.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
