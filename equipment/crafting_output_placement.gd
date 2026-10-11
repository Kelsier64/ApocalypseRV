extends RefCounted
class_name CraftingOutputPlacement
## Full-size bed output poses shared by previews, delivery and checkpointed jobs.

static func is_clear(station: CraftingStation, item: Item, pose: Transform3D, exclude_station: bool, planning: bool = false) -> bool:
	for collider in item.get_children():
		if not collider is CollisionShape3D or collider.shape == null or collider.disabled: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = collider.shape
		query.transform = pose * collider.transform
		query.collision_mask = 1
		if exclude_station: query.exclude = [station.get_rid()]
		for hit in station.get_world_3d().direct_space_state.intersect_shape(query, 64):
			if planning and (hit.collider is CharacterBody3D or (hit.collider is Item and not hit.collider.is_fixed and hit.collider != station)): continue
			return false
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

const OFFSETS := [Vector3.ZERO, Vector3(.12, 0, 0), Vector3(-.12, 0, 0), Vector3(0, 0, -.10), Vector3(0, 0, .10), Vector3(.12, 0, -.10), Vector3(-.12, 0, -.10), Vector3(.12, 0, .10), Vector3(-.12, 0, .10), Vector3(.25, 0, -.12), Vector3(-.25, 0, -.12), Vector3(.25, 0, .12), Vector3(-.25, 0, .12)]

static func output_pose(item: Item, marker: Transform3D, orientation: int = 0, offset_index: int = 0) -> Transform3D:
	if item is PrintedPlayerBody:
		marker.origin += marker.basis.y * CraftingPrintVisual.output_lift(item)
		return marker
	var turn := Basis.IDENTITY
	if orientation == 1: turn = Basis(Vector3.RIGHT, PI * .5)
	elif orientation == 2: turn = Basis(Vector3.BACK, PI * .5)
	var bounds := AABB()
	var first := true
	for collider in item.get_children():
		if not collider is CollisionShape3D or collider.shape == null or collider.disabled: continue
		var box: AABB = Transform3D(turn, Vector3.ZERO) * collider.transform * collider.shape.get_debug_mesh().get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var centre := bounds.get_center()
	var shift: Vector3 = Vector3(-centre.x, -bounds.position.y + .06, -centre.z) + OFFSETS[offset_index]
	return marker * Transform3D(turn, shift)

static func select_pose(station: CraftingStation, item: Item) -> Dictionary:
	# Loose output occupancy must not force the next queued product into a pose
	# that cannot fit the cabin after pickup. Final delivery always checks all.
	for orientation in 3:
		for offset_index in OFFSETS.size():
			var pose := output_pose(item, station.spawn_marker.global_transform, orientation, offset_index)
			if is_clear(station, item, pose, false, true):
				return {"print_orientation": orientation, "print_offset": offset_index}
	return {}
