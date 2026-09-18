extends RefCounted
class_name WorldEntities
## Each independent World3D owns its active entities. Chunk deletion never owns them.
const CONTAINER_NAME := "WorldEntities"

## Moving a prepared hierarchy between World3Ds is not equipment removal.
## Suppress teardown refunds/drops and support loss only for this synchronous move.
static func transfer(node: Node, destination: Node) -> void:
	var devices: Array[Equipment] = []
	_collect_equipment(node, devices)
	for device in devices: device.begin_world_transfer()
	node.reparent(destination)
	for device in devices: device.end_world_transfer()

static func _collect_equipment(node: Node, result: Array[Equipment]) -> void:
	if node is Equipment: result.append(node)
	for child in node.get_children(): _collect_equipment(child, result)

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
