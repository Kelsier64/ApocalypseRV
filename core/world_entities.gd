extends RefCounted
class_name WorldEntities
## Ownership rule for runtime-spawned nodes:
## - Static chunk content (terrain, POI buildings, scavenge loot) stays a child
##   of its chunk and dies with it.
## - Active entities (enemies, crafted outputs, dropped items) live under one
##   shared container at the scene root, so a despawning chunk cannot delete a
##   monster mid-chase and spawned items do not pile up on the scene root.
##   WorldGenerator despawns far-behind entities with the same distance rule it
##   uses for chunks.

const CONTAINER_NAME := "WorldEntities"

static var _container: Node3D = null

## Returns (creating on demand) the shared entity container. Anchored on the
## current scene when available, else the tree root (covers headless tests).
## Safe to call during scene _ready: if the anchor is still setting up its
## children the container is attached deferred, and children added to it in the
## meantime enter the tree together with it.
static func get_container(caller: Node) -> Node3D:
	if _container != null and is_instance_valid(_container):
		return _container

	if caller == null or not caller.is_inside_tree():
		return null
	var tree := caller.get_tree()
	if tree == null:
		return null
	var anchor: Node = tree.current_scene
	if anchor == null:
		anchor = tree.root

	var existing := anchor.get_node_or_null(CONTAINER_NAME)
	if existing is Node3D:
		_container = existing
		return existing

	var container := Node3D.new()
	container.name = CONTAINER_NAME
	anchor.add_child(container)
	if container.get_parent() == null:
		# Anchor is busy setting up its own children (scene _ready) and rejected
		# the synchronous add; finish the attach once the tree settles.
		anchor.add_child.call_deferred(container)
	_container = container
	return container
