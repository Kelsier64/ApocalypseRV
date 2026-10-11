extends RefCounted
class_name CraftingOutputPlacement
## Keep manufactured bodies usable in cabins by selecting a full-size standing or crouched posture on the bed.

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

static func body_can_stand(station: CraftingStation, pose: Transform3D, crouching: bool = false) -> bool:
	# Reserve the playable controller's 0.4m shoulder radius too. A narrow
	# idle-body fit (including a roof hatch) must not block control transfer.
	var standing := CapsuleShape3D.new()
	standing.radius = 0.4
	standing.height = 1.05 if crouching else 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing
	query.transform = pose * Transform3D(Basis.IDENTITY, Vector3(0, standing.height * 0.5, 0))
	query.collision_mask = 1
	return station.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
