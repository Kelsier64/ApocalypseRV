extends StaticBody3D
class_name BunkerCache
## A persistent supply chest. Each completed hold transfers at most one item.

var cache_id: String = ""
var searched: bool = false
var remaining: Array[Dictionary] = []

@onready var _lid: Node3D = $Visuals/LidPivot

func _ready() -> void:
	_update_visual()

func capture_state() -> Dictionary:
	return {"id": cache_id, "transform": transform, "searched": searched, "remaining": remaining.duplicate(true)}

func restore_state(data: Dictionary) -> void:
	cache_id = str(data.get("id", cache_id))
	transform = data.get("transform", transform)
	searched = bool(data.get("searched", false))
	remaining.clear()
	for entry in data.get("remaining", []):
		if entry is Dictionary:
			remaining.append(entry.duplicate(true))
	_update_visual()

func get_interaction_prompt(_player: Node3D) -> String:
	if searched and remaining.is_empty():
		return "Supply cache | Empty"
	return "Supply cache | Hold E for 1 second (%d remaining)" % remaining.size()

func interact(_player: Node3D) -> String:
	if searched and remaining.is_empty(): return "Supply cache is empty"
	return "Hold E for 1 second to search"

func interact_hold(player: Node3D) -> String:
	if not _can_search(player): return "Cannot search cache"
	if remaining.is_empty():
		searched = true
		_update_visual()
		return "Supply cache is empty"
	var entry: Dictionary = remaining.front()
	var scene_path := str(entry.get("scene", ""))
	var scene := load(scene_path) as PackedScene
	if scene == null: return "Supply unavailable"
	var item := scene.instantiate() as Item
	if item == null: return "Supply unavailable"
	# Some props initialize model state in _ready. Restore after initialization so
	# the inventory receives their exact saved identity and condition.
	item.freeze = true
	item.collision_layer = 0
	item.collision_mask = 0
	add_child(item)
	item.item_name = str(entry.get("name", item.item_name))
	item.is_large = bool(entry.get("large", item.is_large))
	item.restore_item_state(entry.get("state", {}))
	var accepted: bool = player.add_prop_item(item, scene_path)
	item.queue_free()
	if not accepted: return "Cannot carry: inventory full or large item already held"
	remaining.remove_at(0)
	searched = true
	_update_visual()
	return "Collected %s" % str(entry.get("name", "supply"))

func _can_search(player: Node3D) -> bool:
	return is_inside_tree() and is_instance_valid(player) and player.is_inside_tree() \
		and player.has_method("get_player_mode") and player.has_method("add_prop_item") \
		and player.get_player_mode() == player.PlayerMode.NORMAL \
		and player.get_world_3d() == get_world_3d() \
		and global_position.distance_to(player.global_position) <= 3.0

func _update_visual() -> void:
	if _lid == null: return
	_lid.rotation.x = -1.15 if searched else 0.0
