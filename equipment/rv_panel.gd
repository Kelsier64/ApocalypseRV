extends Equipment

@export var structure_kind: String = ""
@export var mount_slot: String = ""

func _ready() -> void:
	super._ready()
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
	return equipment_name + "｜拆裝時自動對齊底盤槽位\n搬移會使附掛在本片上的設備掉落"
