extends RefCounted
class_name PlacementRules

static func valid_target(equipment: Node3D, target: Node) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion() or target == equipment or equipment.is_ancestor_of(target):
		return false
	var ancestor := target
	while ancestor:
		if ancestor is Prop or ancestor is CharacterBody3D:
			return false
		ancestor = ancestor.get_parent()
	if target is Equipment:
		if target.is_being_placed or target.is_destroyed:
			return false
		var support: Node = target
		var seen: Array[Node] = []
		while support is Equipment:
			if support == equipment or seen.has(support):
				return false
			seen.append(support)
			support = support.mount_support
		return true
	return target is StaticBody3D or RVConnection.is_rv(target)

static func can_place(equipment: Equipment, target: Node3D, pose: Transform3D) -> bool:
	if not valid_target(equipment, target):
		return false
	var rv := RVConnection.resolve(target)
	var up := rv.global_basis.y.normalized() if rv else Vector3.UP
	if equipment.definition and equipment.definition.requires_upright and pose.basis.y.normalized().dot(up) < 0.9:
		return false
	for child in equipment.get_children():
		if not child is CollisionShape3D or child.disabled or not child.shape:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = child.shape.duplicate()
		if query.shape is BoxShape3D:
			query.shape.size = (query.shape.size - Vector3.ONE * 0.02).max(Vector3.ONE * 0.001)
		query.transform = pose * child.transform
		query.exclude = [equipment.get_rid()]
		query.collision_mask = 1
		if not equipment.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	if equipment.definition and equipment.definition.placement_clearance.length_squared() > 0.0:
		var clearance := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = equipment.definition.placement_clearance
		clearance.shape = box
		clearance.transform = pose * Transform3D(Basis.IDENTITY, equipment.definition.clearance_center)
		clearance.exclude = [equipment.get_rid()]
		clearance.collision_mask = 1
		if not equipment.get_world_3d().direct_space_state.intersect_shape(clearance, 1).is_empty():
			return false
	return true
