extends RefCounted
class_name CombatTargeting
## Selection policy only. The actor supplies candidates and physical contact checks.

static func node_position(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position

static func is_live_target(node: Node3D) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion(): return false
	if node is RVStructurePanel:
		return not node.is_destroyed and (not node.is_inside_tree() or node.is_visible_in_tree())
	# All portable/fixed Items are physical obstacles, never monster targets.
	if node is Item: return false
	return true

static func build_target(node: Node3D, target_type: String, source: String = "state_attack") -> Dictionary:
	if not is_live_target(node):
		return {}
	return {"node": node, "position": node_position(node), "target_type": target_type, "attack_source": source}

static func nearest(candidates: Array, origin: Vector3, excluded: Node3D = null) -> Node3D:
	var picked: Node3D = null
	var nearest_distance := INF
	for candidate in candidates:
		if not is_instance_valid(candidate) or not candidate is Node3D or candidate == excluded or not is_live_target(candidate):
			continue
		var distance := origin.distance_to(node_position(candidate))
		if distance < nearest_distance:
			nearest_distance = distance
			picked = candidate
	return picked

static func structure_type(node: Node3D) -> String:
	return "chassis" if is_instance_valid(node) and node.is_in_group(Groups.CHASSIS) else "equipment"

static func preferred_structure(candidates: Array, origin: Vector3, excluded: Node3D = null) -> Node3D:
	var chassis: Array = []
	var equipment: Array = []
	var fallback: Array = []
	for candidate in candidates:
		if not is_instance_valid(candidate) or not candidate is Node3D or not is_live_target(candidate):
			continue
		if candidate.is_in_group(Groups.CHASSIS):
			chassis.append(candidate)
		elif candidate is RVStructurePanel:
			equipment.append(candidate)
		else:
			fallback.append(candidate)
	for category in [chassis, equipment, fallback]:
		var picked := nearest(category, origin, excluded)
		if picked != null:
			return picked
	return null

static func related(candidate: Node3D, reference: Node3D) -> bool:
	return is_instance_valid(candidate) and is_instance_valid(reference) and (
		candidate == reference or candidate.is_ancestor_of(reference) or reference.is_ancestor_of(candidate))

static func select_target(players: Array, structures: Array, climbing: bool,
		origin: Vector3, actor: Node3D, underfoot: Node3D, touching: Callable) -> Dictionary:
	var eligible: Array = []
	for candidate in structures:
		if not is_instance_valid(candidate) or not candidate is Node3D or not is_live_target(candidate) or related(candidate, underfoot):
			continue
		if not climbing or touching.call(candidate):
			eligible.append(candidate)
	if climbing:
		var target := nearest(eligible, origin, actor)
		return build_target(target, structure_type(target))
	var player := nearest(players, origin, actor)
	if player != null:
		return build_target(player, "player")
	var structure := preferred_structure(eligible, origin, actor)
	return build_target(structure, structure_type(structure))
