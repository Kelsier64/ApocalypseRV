extends Node
class_name RVStructureConstruction
## One transactional construction job belongs to the vehicle, not the terminal.
signal changed
signal operation_committed(slot: String, operation: String)
var job: Dictionary = {}
var last_message := ""
var _shape_cache: Dictionary = {}

func is_building() -> bool:
	return not job.is_empty()

func progress() -> float:
	return clampf(1.0 - float(job.remaining) / float(job.duration), 0.0, 1.0) if is_building() else 0.0

func status_message() -> String:
	return "%s | %.1f s | Saving unavailable during construction" % [job.label, job.remaining] if is_building() else last_message

func _rv() -> Node3D:
	return get_parent().get_parent()

func _service_reason(terminal: Node) -> String:
	if not is_instance_valid(terminal) or not terminal.can_operate() or terminal.get_connected_rv() != _rv():
		return "Tablet unavailable: install and restore its connection"
	if not is_instance_valid(terminal.current_user) or not is_instance_valid(terminal.ui_instance) or not terminal.ui_instance.visible:
		return "Open the tablet interface"
	if not terminal.has_method("is_management_active") or not terminal.is_management_active():
		return "Open vehicle management before starting construction"
	var user: Node = terminal.current_user
	if user.get("is_player_dead") == true: return "Operator is dead"
	if user.has_method("can_use_hands") and not user.can_use_hands(): return "Operator cannot use the tablet"
	if user.has_method("get_player_mode") and user.get_player_mode() != user.PlayerMode.UI: return "Operator has left tablet mode"
	if not _rv().has_usable_power(): return "Tablet has no power"
	if _rv().energy.engine_running: return "Stop the engine first"
	if _rv().linear_velocity.length() > 0.5: return "Vehicle speed must be at or below 0.5 m/s"
	return ""

func rejection_reason(terminal: Node, slot: String, operation: String, type: String = "", completing: bool = false) -> String:
	if is_building() and not completing: return "Another structure job is in progress"
	var service := _service_reason(terminal)
	if not service.is_empty(): return service
	var target: Node = get_parent().panel(slot)
	if not is_instance_valid(target): return "Structure slot unavailable"
	if not operation in ["repair", "rebuild", "convert"]: return "Unknown construction operation"
	if operation == "repair" and not type.is_empty() and type != target.definition.type_id:
		return "Repair cannot change the part type"
	var chosen := type if not type.is_empty() else str(target.definition.type_id)
	if not chosen in RVStructureSlots.types_for_slot(slot): return "This slot does not support that type"
	var definition: Resource = RVStructureSlots.definition_for(chosen)
	if definition == null: return "Structure type unavailable"
	if operation == "repair":
		if target.is_destroyed: return "Part destroyed: rebuild it"
		if target.current_health >= target.max_health: return "Durability is full"
	elif operation == "rebuild":
		if not target.is_destroyed: return "Slot already contains a part"
	else:
		if target.is_destroyed: return "Part destroyed: rebuild it"
		if chosen == target.definition.type_id: return "Already using this type"
		if not chosen in target.definition.allowed_conversions: return "This type conversion is not allowed"
		var attached: PackedStringArray = target.dependent_names()
		if not attached.is_empty(): return "Move attached equipment first | " + ", ".join(attached)
	var costs := {"Metal Parts": operation_cost(operation, definition)}
	if not _rv().has_materials(costs): return "Insufficient Metal Parts"
	if operation != "repair":
		var blocker := collision_reason(slot, definition, target)
		if not blocker.is_empty(): return blocker
	return ""

func operation_cost(operation: String, definition: Resource) -> int:
	match operation:
		"repair": return definition.repair_cost
		"rebuild": return definition.rebuild_cost
	return definition.convert_cost

func operation_seconds(operation: String, definition: Resource) -> float:
	match operation:
		"repair": return definition.repair_seconds
		"rebuild": return definition.rebuild_seconds
	return definition.convert_seconds

func begin(terminal: Node, slot: String, operation: String, type: String = "") -> String:
	var reason := rejection_reason(terminal, slot, operation, type)
	if not reason.is_empty():
		last_message = reason
		changed.emit()
		return reason
	var target: Node = get_parent().panel(slot)
	var chosen := type if not type.is_empty() else str(target.definition.type_id)
	var definition: Resource = RVStructureSlots.definition_for(chosen)
	var seconds := operation_seconds(operation, definition)
	job = {"terminal": terminal, "target": target, "slot": slot, "operation": operation, "type": chosen,
		"health": target.current_health, "duration": seconds, "remaining": seconds,
		"label": {"repair": "Repair", "rebuild": "Rebuild", "convert": "Convert"}[operation] + " " + target.equipment_name}
	target.damaged.connect(_on_target_damaged)
	changed.emit()
	return ""

func cancel_for(terminal: Node) -> void:
	if is_building() and job.terminal == terminal: cancel("Tablet closed")

func cancel(reason: String = "Construction cancelled") -> void:
	if not is_building(): return
	_clear_job()
	last_message = reason
	changed.emit()

func _clear_job() -> void:
	var target: Node = job.get("target")
	if is_instance_valid(target) and target.damaged.is_connected(_on_target_damaged):
		target.damaged.disconnect(_on_target_damaged)
	job.clear()

func _on_target_damaged(_amount: float = 0.0) -> void:
	cancel("Target damaged: construction cancelled")

func _physics_process(delta: float) -> void:
	if not is_building(): return
	var reason := _service_reason(job.terminal)
	if reason.is_empty() and (not is_instance_valid(job.target) or get_parent().panel(job.slot) != job.target):
		reason = "Target changed: construction cancelled"
	if reason.is_empty() and not is_equal_approx(float(job.target.current_health), float(job.health)):
		reason = "Target durability changed: construction cancelled"
	if not reason.is_empty():
		cancel(reason)
		return
	job.remaining = maxf(0.0, float(job.remaining) - delta)
	if job.remaining <= 0.000001: _finish()

func _finish() -> void:
	var reason := rejection_reason(job.terminal, job.slot, job.operation, job.type, true)
	if not reason.is_empty():
		cancel(reason)
		return
	var definition: Resource = RVStructureSlots.definition_for(job.type)
	var target: Node = job.target
	var completed := job.duplicate()
	# All validation precedes this synchronous material/state commit.
	var costs := {"Metal Parts": operation_cost(job.operation, definition)}
	var paid_costs: Dictionary = {} if _rv().unlimited_materials else costs.duplicate()
	if not _rv().deduct_materials(costs):
		cancel("Insufficient materials: construction cancelled")
		return
	_clear_job()
	if completed.operation == "repair":
		target.set_health(minf(target.max_health, target.current_health + definition.repair_amount))
	else:
		var health: float = definition.health
		if completed.operation == "convert": health *= target.current_health / target.max_health
		if get_parent().replace_panel(completed.slot, completed.type, health) == null:
			_rv().deposit_materials(paid_costs, true)
			last_message = "Construction failed; materials returned"
			changed.emit()
			return
	last_message = "Construction complete"
	operation_committed.emit(completed.slot, completed.operation)
	changed.emit()

func collision_reason(slot: String, definition: Resource, old_panel: Node) -> String:
	if not _shape_cache.has(definition.type_id):
		var packed: PackedScene = load(definition.scene_path)
		if packed == null: return "Structure asset unavailable"
		var candidate: Node3D = packed.instantiate()
		var collected: Array[Dictionary] = []
		_collect_shapes(candidate, Transform3D.IDENTITY, collected)
		candidate.free()
		for entry in collected:
			var shape: Shape3D = entry.shape.duplicate()
			if shape is BoxShape3D: shape.size = (shape.size - Vector3.ONE * 0.02).max(Vector3.ONE * 0.001)
			entry.shape = shape
		_shape_cache[definition.type_id] = collected
	var pose := Transform3D.IDENTITY
	for entry in RVStructureSlots.layout():
		if entry.id == slot: pose = entry.pose
	var exclude: Array[RID] = []
	if _rv() is CollisionObject3D: exclude.append(_rv().get_rid())
	if old_panel is CollisionObject3D: exclude.append(old_panel.get_rid())
	var shapes: Array[Dictionary] = _shape_cache[definition.type_id]
	var reason := ""
	for entry in shapes:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = entry.shape
		query.transform = _rv().global_transform * pose * entry.pose
		query.exclude = exclude
		query.collision_mask = 0xFFFFFFFF
		query.collide_with_areas = false
		query.margin = 0.0
		var hits := _rv().get_world_3d().direct_space_state.intersect_shape(query, 16)
		if not hits.is_empty():
			reason = "Construction space blocked by " + str(hits[0].collider.name)
			break
	return reason

func _collect_shapes(node: Node, pose: Transform3D, found: Array[Dictionary]) -> void:
	var local := pose
	if node is Node3D: local *= node.transform
	if node is CollisionShape3D and node.shape and not node.disabled:
		found.append({"shape": node.shape, "pose": local})
	for child in node.get_children(): _collect_shapes(child, local, found)
