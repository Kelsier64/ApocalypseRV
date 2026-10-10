extends RefCounted
class_name WorldActorSnapshot
## Unified world records. Restore bodies first, then bind support references.
static func capture(child: Node) -> Dictionary:
	if child.is_queued_for_deletion(): return {}
	if child is Item:
		if child.is_destroyed or is_instance_valid(child.processing_owner) or child.is_being_placed or child.presentation_only: return {}
		return {"kind": "item", "scene": child.scene_file_path, "transform": child.global_transform,
			"state": child.capture_item_state(), "fixed": child.is_fixed, "support": support_state(child),
			"name": child.item_name, "large": child.is_large,
			"physics": {"freeze": child.freeze, "mode": child.freeze_mode, "layer": child.collision_layer, "mask": child.collision_mask, "linear": child.linear_velocity, "angular": child.angular_velocity}}
	if child is Monster and not child.is_dead:
		var data := {"kind": "monster", "scene": child.scene_file_path, "transform": child.global_transform, "health": child.current_health}
		if child.has_meta("bunker_actor_id"): data["id"] = str(child.get_meta("bunker_actor_id"))
		if child is Raker:
			var ragdoll: Dictionary = child.ragdoll.capture_snapshot()
			if not ragdoll.is_empty(): data["ragdoll"] = ragdoll
		elif child is BarrelMan:
			data["barrel"] = child.capture_barrel_state()
		return data
	return {}

static func domain(node: Node) -> Node:
	var anchor := node
	while anchor != null and not anchor.has_meta("entity_domain"): anchor = anchor.get_parent()
	return anchor if anchor else node.get_tree().current_scene

static func support_state(item: Item) -> Dictionary:
	var support := item.mount_support
	if not item.is_fixed or not is_instance_valid(support): return {"kind": "none"}
	if support is Item: return {"kind": "item", "id": support.persistent_id}
	if support is RVStructurePanel:
		var rv: Node = support.get_connected_rv() if support.has_method("get_connected_rv") else _chassis(support)
		return {"kind": "structure", "rv": rv.persistent_id if rv else "", "slot": support.mount_slot}
	if support.is_in_group(Groups.CHASSIS): return {"kind": "chassis", "rv": support.persistent_id}
	var anchor := domain(item)
	if anchor != null and anchor.is_ancestor_of(support): return {"kind": "static", "path": str(anchor.get_path_to(support))}
	return {"kind": "none"}

static func _chassis(node: Node) -> Node:
	while node != null:
		if node.is_in_group(Groups.CHASSIS): return node
		node = node.get_parent()
	return null

static func valid_support(value: Variant) -> bool:
	if not value is Dictionary or not value.get("kind") is String: return false
	match value.kind:
		"none": return value.size() == 1
		"item": return value.size() == 2 and value.get("id") is String and not value.id.is_empty()
		"chassis": return value.size() == 2 and value.get("rv") is String and not value.rv.is_empty()
		"structure": return value.size() == 3 and value.get("rv") is String and not value.rv.is_empty() and value.get("slot") is String and not value.slot.is_empty()
		"static":
			return value.size() == 2 and value.get("path") is String and not value.path.is_empty() and not NodePath(value.path).is_absolute() and not ".." in value.path.split("/")
	return false

static func validation_error(actor: Variant, field: String) -> String:
	if not actor is Dictionary or not actor.get("kind") is String: return field + ".kind"
	if actor.kind not in ["item", "monster"] or SaveSceneCatalog.resolve(actor.get("scene"), actor.kind) == null: return field + ".scene"
	if not CheckpointSchema.valid_transform(actor.get("transform")): return field + ".transform"
	if actor.kind == "item":
		if not actor.get("state") is Dictionary or not ItemState.valid(actor.scene, actor.state): return field + ".state"
		if not actor.get("fixed") is bool or not valid_support(actor.get("support")): return field + ".support"
		if not actor.get("name") is String or not actor.get("large") is bool: return field + ".item"
		if not CheckpointSchema.physics(actor.get("physics"), true): return field + ".physics"
	else:
		if actor.has("state"): return field + ".unexpected_item_state"
		if not VehicleSnapshot._number(actor.get("health")) or actor.health < 0: return field + ".health"
		if actor.has("barrel"):
			if actor.scene != "res://enemies/barrel_man.tscn" or not BarrelMan.validate_barrel_state(actor.barrel): return field + ".barrel"
		if actor.has("ragdoll"):
			if actor.scene != "res://enemies/raker.tscn" or not actor.ragdoll is Dictionary: return field + ".ragdoll"
			var ragdoll: Dictionary = actor.ragdoll
			if not CheckpointSchema.valid_transform(ragdoll.get("visual_transform")): return field + ".ragdoll.visual_transform"
			if not ragdoll.get("poses") is Array or ragdoll.poses.size() != 54: return field + ".ragdoll.poses"
			for pose in ragdoll.poses:
				if not CheckpointSchema.valid_transform(pose): return field + ".ragdoll.poses"
			if not CheckpointSchema.vector(ragdoll.get("linear")): return field + ".ragdoll.linear"
	return ""

static func graph_error(actors: Array) -> String:
	var graph := {}
	for actor: Dictionary in actors:
		if actor.get("kind") != "item": continue
		var identity: String = actor.state.get("id", "")
		if identity.is_empty() or graph.has(identity): return "item.id.duplicate_or_missing"
		graph[identity] = actor.support
	for identity in graph:
		var visited := {}
		var cursor: String = identity
		while graph.has(cursor):
			if visited.has(cursor): return "item.support.cycle"
			visited[cursor] = true
			var support: Dictionary = graph[cursor]
			if support.kind != "item": break
			cursor = support.id
	return ""

static func restore(saved: Dictionary, container: Node) -> Node3D:
	var actor: Node3D = SaveSceneCatalog.resolve(saved.scene, saved.kind).instantiate()
	container.add_child(actor)
	actor.global_transform = saved.transform
	if actor is Item:
		actor.item_name = saved.name
		actor.is_large = saved.large
		var initial: Dictionary = saved.state.duplicate(true)
		if saved.fixed: initial["service"] = {}
		actor.restore_item_state(initial)
		actor.is_fixed = false
		actor.freeze = saved.physics.freeze
		actor.freeze_mode = saved.physics.mode
		actor.collision_layer = saved.physics.layer
		actor.collision_mask = saved.physics.mask
		actor.linear_velocity = saved.physics.linear
		actor.angular_velocity = saved.physics.angular
	elif actor is Monster:
		actor.current_health = saved.health
		if actor.has_method("reset_after_restore"): actor.reset_after_restore()
		if saved.has("id"):
			actor.set_meta("bunker_actor_id", saved.id)
			BunkerContent.configure_monster(actor)
		if actor is Raker and saved.has("ragdoll"): actor.ragdoll.restore_snapshot(saved.ragdoll)
		elif actor is BarrelMan: actor.restore_barrel_state(saved.get("barrel", {}))
	return actor

static func restore_supports(records: Array, actors: Array, anchor: Node) -> void:
	var by_id := {}
	for actor in actors:
		if actor is Item: by_id[actor.persistent_id] = actor
	for child in anchor.find_children("*", "RigidBody3D", true, false):
		if child is Item: by_id[child.persistent_id] = child
	var resolved := {}
	for index in range(records.size()):
		_restore_support(index, records, actors, anchor, by_id, resolved)

static func _restore_support(index: int, records: Array, actors: Array, anchor: Node, by_id: Dictionary, resolved: Dictionary) -> void:
	if resolved.has(index): return
	resolved[index] = true
	var saved: Dictionary = records[index]
	var item := actors[index] as Item
	if item == null or not saved.fixed: return
	var reference: Dictionary = saved.support
	var support: Node3D
	if reference.kind == "item":
		for dependency in range(records.size()):
			if records[dependency].get("kind") == "item" and records[dependency].state.id == reference.id:
				_restore_support(dependency, records, actors, anchor, by_id, resolved)
		var candidate := by_id.get(reference.id) as Item
		if candidate != null and candidate.is_fixed: support = candidate
	elif reference.kind == "static":
		support = anchor.get_node_or_null(NodePath(reference.path)) as StaticBody3D
	elif reference.kind in ["chassis", "structure"]:
		for rv in anchor.get_tree().get_nodes_in_group(Groups.CHASSIS):
			if not anchor.is_ancestor_of(rv) or rv.persistent_id != reference.rv: continue
			support = rv if reference.kind == "chassis" else rv.get_node("StructureSlots").occupant(reference.slot)
	if support != null and not PlacementRules.valid_target(item, support): support = null
	if support != null:
		item.confirm_placement(saved.transform, support, support)
		# Restore work only after the complete support chain is operational.
		item.restore_item_state(saved.state)
	else:
		# Failed RV support still stops jobs against their original material owner.
		var original_rv := RVConnection.resolve(item.get_parent())
		if original_rv != null: item.confirm_placement(saved.transform, original_rv, original_rv)
		item.restore_item_state(saved.state)
		item.detach_from_support()
