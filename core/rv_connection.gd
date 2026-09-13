extends RefCounted
class_name RVConnection
## Shared equipment-to-RV contract. Avoid a Chassis/Equipment preload cycle.

static func is_rv(node: Node) -> bool:
	return is_instance_valid(node) and node is Node3D and node.is_in_group(Groups.RV) \
		and node.has_method("add_item") and node.has_method("deduct_materials")

static func resolve(start: Node) -> Node3D:
	var current := start
	while is_instance_valid(current):
		if is_rv(current):
			return current as Node3D
		current = current.get_parent()
	return null
