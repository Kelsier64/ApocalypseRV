extends RefCounted
class_name WorldEntities
## Each independent World3D owns its active entities. Chunk deletion never owns them.
const CONTAINER_NAME := "WorldEntities"

static func same_world(a: Node3D, b: Node3D) -> bool:
	return is_instance_valid(a) and is_instance_valid(b) and a.is_inside_tree() and b.is_inside_tree() and a.get_world_3d() == b.get_world_3d()

static func get_container(caller: Node) -> Node3D:
	if caller == null or not caller.is_inside_tree():
		return null
	var anchor: Node = caller
	while anchor != null and not anchor.has_meta("entity_domain"):
		anchor = anchor.get_parent()
	if anchor == null:
		anchor = caller.get_tree().current_scene
	if anchor == null:
		anchor = caller.get_tree().root
	var existing := anchor.get_node_or_null(CONTAINER_NAME) as Node3D
	if existing != null:
		return existing
	var container := Node3D.new()
	container.name = CONTAINER_NAME
	anchor.add_child(container)
	return container
