extends StaticBody3D
var opened: bool = false
func bay() -> Node3D: return get_parent()
func interact(_player: Node3D) -> String:
	var rv := bay().get_parent()
	if rv.linear_velocity.length() > 0.5: return "請停穩後操作維修蓋"
	var target := Vector3(0, -0.05, -0.58) if opened else Vector3(0, 0.65, -1.35)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = $Collision.shape
	query.exclude = [get_rid(), bay().get_rid(), rv.get_rid()]
	query.collision_mask = 1
	for i in range(1, 11):
		query.transform = Transform3D(global_basis, get_parent().to_global(position.lerp(target, i / 10.0)))
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return "維修蓋被擋住，請退後或移開物品"
	set_open(not opened)
	return "維修蓋已打開" if opened else "維修蓋已關閉"
func set_open(value: bool) -> void:
	opened = value
	bay().hatch_open = value
	position = Vector3(0, 0.65 if value else -0.05, -1.35 if value else -0.58)
func get_interaction_prompt(_player: Node3D) -> String:
	return "引擎維修蓋｜E " + ("關閉" if opened else "打開")
func allows_mount_at(_point: Vector3) -> bool: return false
