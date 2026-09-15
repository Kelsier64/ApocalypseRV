extends Equipment

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
