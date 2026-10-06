extends RefCounted
class_name PlacementRules

static func valid_target(equipment: Node3D, target: Node) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion() or target == equipment or equipment.is_ancestor_of(target):
		return false
	var ancestor := target
	while ancestor:
		if ancestor is CharacterBody3D:
			return false
		if ancestor is Item and not _usable_fixed_item(ancestor):
			return false
		ancestor = ancestor.get_parent()
	if target is Item:
		if not _usable_fixed_item(target):
			return false
		var support: Node = target
		var seen: Array[Node] = []
		while is_instance_valid(support) and (support is Item or support is RVStructurePanel):
			if support == equipment or seen.has(support):
				return false
			if support.is_destroyed:
				return false
			if support is Item and not _usable_fixed_item(support):
				return false
			seen.append(support)
			support = support.mount_support if support is Item else support.get_connected_rv()
		return is_instance_valid(support) and not support.is_queued_for_deletion()
	if target is RVStructurePanel:
		return target.can_operate()
	return target is StaticBody3D or RVConnection.is_rv(target)

static func _usable_fixed_item(item: Item) -> bool:
	# Support chains become unavailable as soon as pickup/recycling/release
	# starts, including the tick before the deferred physics release occurs.
	return item.is_fixed and not item.is_queued_for_deletion() and not item.is_destroyed and not item.is_being_placed and not item.presentation_only and not item.support_lost and not item._support_release_pending and not is_instance_valid(item.processing_owner)

static func can_place(equipment: Item, target: Node3D, pose: Transform3D) -> bool:
	return rejection_reason(equipment, target, pose).is_empty()

static func rejection_reason(equipment: Item, target: Node3D, pose: Transform3D, contact: Variant = null, surface_normal: Variant = null) -> String:
	if not valid_target(equipment, target):
		return "無效支撐：不能固定在散落物、角色或相依循環上"
	if contact is Vector3 and target.has_method("allows_mount_at") and not target.allows_mount_at(contact):
		return "活動門扇、坡板與維修區域不能安裝設備，請選擇固定支撐面"
	var rv := RVConnection.resolve(target)
	var up := rv.global_basis.y.normalized() if rv else Vector3.UP
	if equipment is RVLadder:
		var normal := Vector3.ZERO
		if surface_normal is Vector3 and contact is Vector3:
			normal = surface_normal.normalized()
		else:
			# Programmatic callers must prove the same real wall contact as the
			# preview. Merely naming a wall or pointing the ladder is insufficient.
			var bounds := equipment.get_placement_bounds()
			var center := bounds.get_center()
			var back := pose * Vector3(center.x, center.y, bounds.position.z)
			var approach := pose.basis.z.normalized()
			var query := PhysicsRayQueryParameters3D.create(back + approach * 0.1, back - approach * 0.15, 1, [equipment.get_rid()])
			var hit := equipment.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.get("collider") != target: return "梯子背面必須貼住實際牆面"
			if target.has_method("allows_mount_at") and not target.allows_mount_at(hit.position):
				return "活動門扇、坡板與維修區域不能安裝設備，請選擇固定支撐面"
			normal = hit.normal
		if absf(normal.dot(up)) > 0.15: return "梯子只能貼牆安裝，不能放在地板或天花板"
		if pose.basis.z.normalized().dot(normal) < 0.98: return "梯面必須平行牆面，正面朝外"
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
		query.collision_mask = 0xFFFFFFFF
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
		clearance.collision_mask = 0xFFFFFFFF
		var hits := equipment.get_world_3d().direct_space_state.intersect_shape(clearance, 1)
		if not hits.is_empty():
			return "操作空間被 %s 擋住" % object_name(hits[0].collider)
	return ""

static func object_name(node: Node) -> String:
	if node is RVStructurePanel: return node.equipment_name
	if node is CharacterBody3D: return "角色"
	if node is Item: return node.item_name
	if RVConnection.is_rv(node): return "底盤"
	return str(node.name)
