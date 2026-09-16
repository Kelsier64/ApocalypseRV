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
	return rejection_reason(equipment, target, pose).is_empty()

static func rejection_reason(equipment: Equipment, target: Node3D, pose: Transform3D, contact: Variant = null) -> String:
	if not valid_target(equipment, target):
		return "無效支撐：不能安裝在道具、角色或相依循環上"
	if contact is Vector3 and target.has_method("allows_mount_at") and not target.allows_mount_at(contact):
		return "活動門扇不能安裝設備，請瞄準固定門框"
	var rv := RVConnection.resolve(target)
	var up := rv.global_basis.y.normalized() if rv else Vector3.UP
	if equipment.definition and equipment.definition.requires_upright and pose.basis.y.normalized().dot(up) < 0.9:
		return "設備必須保持直立"
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
		var hits := equipment.get_world_3d().direct_space_state.intersect_shape(query, 1)
		if not hits.is_empty():
			return "被 %s 擋住，請移開障礙物" % object_name(hits[0].collider)
	if equipment.definition and equipment.definition.placement_clearance.length_squared() > 0.0:
		var clearance := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = equipment.definition.placement_clearance
		clearance.shape = box
		clearance.transform = pose * Transform3D(Basis.IDENTITY, equipment.definition.clearance_center)
		clearance.exclude = [equipment.get_rid()]
		clearance.collision_mask = 1
		var hits := equipment.get_world_3d().direct_space_state.intersect_shape(clearance, 1)
		if not hits.is_empty():
			return "操作空間被 %s 擋住" % object_name(hits[0].collider)
	return ""

static func object_name(node: Node) -> String:
	if node is Equipment: return node.equipment_name
	if node is CharacterBody3D: return "角色"
	if node is Prop: return node.item_name
	if RVConnection.is_rv(node): return "底盤"
	return str(node.name)
