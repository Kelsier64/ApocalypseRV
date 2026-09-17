extends Equipment

@export var structure_kind: String = ""
@export var mount_slot: String = ""

func _ready() -> void:
	super._ready()
	var wear := Node.new()
	wear.set_script(load("res://rv/panel_wear.gd"))
	add_child(wear)
	if structure_kind == "roof":
		var lamps := Node3D.new()
		lamps.name = "CabinLighting"
		lamps.set_script(preload("res://rv/cabin_lighting.gd"))
		add_child(lamps)
	call_deferred("_setup_if_on_rv")

func _setup_if_on_rv() -> void:
	var rv := get_connected_rv()
	if not rv:
		return
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1
	collision_mask = 0
	_add_collision_exceptions_with_ancestors(get_parent())

func get_mount_snap_points() -> Array[Vector3]:
	var bounds := get_placement_bounds()
	var points: Array[Vector3] = []
	var center := bounds.get_center()
	var half := bounds.size * 0.5
	for axis in range(3):
		for direction in [-1.0, 1.0]:
			var point := center
			point[axis] += half[axis] * direction
			points.append(to_global(point))
	return points

func confirm_placement(pose: Transform3D, new_parent: Node3D, support: Node3D = null) -> void:
	super.confirm_placement(pose, new_parent, support)
	mount_slot = ""
	var rv := get_connected_rv()
	if rv and not structure_kind.is_empty():
		var slots := rv.get_node_or_null("StructureSlots")
		if slots: mount_slot = slots.identify(rv.global_transform.affine_inverse() * pose, structure_kind)

func detach_from_support() -> void:
	mount_slot = ""
	super.detach_from_support()

func start_placement(player: Node3D) -> void:
	var already_moving := is_being_placed
	super.start_placement(player)
	if not already_moving and is_being_placed:
		# Only devices actually supported by this panel detach; neighbouring slots belong to the chassis.
		removing.emit()

func get_interaction_prompt(_player: Node3D) -> String:
	return equipment_name + "｜拆裝時自動對齊底盤槽位\n" + dependent_summary()

func dependent_summary() -> String:
	var rv := get_connected_rv()
	if rv == null: return "未接入車輛"
	var names := PackedStringArray()
	for device in rv.get_equipment():
		if device == self: continue
		var cursor: Node = device.mount_support
		var visited: Array[Node] = []
		while cursor is Equipment and not visited.has(cursor):
			if cursor == self:
				names.append(device.equipment_name)
				break
			visited.append(cursor)
			cursor = cursor.mount_support
	if names.is_empty(): return "無附掛設備"
	var shown := names.slice(0, 3)
	return "搬移將掉落 %d 件：%s%s" % [names.size(), "、".join(shown), "…" if names.size() > 3 else ""]
