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
	var ancestor := get_parent()
	while ancestor != null and ancestor is Node3D:
		if ancestor is CollisionObject3D:
			add_collision_exception_with(ancestor)
		ancestor = ancestor.get_parent()
