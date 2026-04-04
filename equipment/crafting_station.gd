extends Equipment
class_name CraftingStation

@onready var spawn_marker = $SpawnMarker
@export var power_cost_per_spawn: float = 0.6

func _ready():
	super._ready()
	add_to_group("crafting_stations")
	
func spawn_item(scene_path: String) -> bool:
	var rv = get_connected_rv()
	if not rv:
		print("CraftingStation: Offline (not connected to RV).")
		return false
	if rv.has_method("has_usable_power") and not rv.has_usable_power():
		print("CraftingStation: No power available.")
		return false

	var item_scene = load(scene_path)
	if not item_scene:
		push_error("CraftingStation: Failed to load " + scene_path)
		return false

	if not consume_rv_power(power_cost_per_spawn):
		print("CraftingStation: Insufficient power for craft output.")
		return false
		
	var item = item_scene.instantiate()
	
	# Spawn it in the world, not as a child, so it can be picked up and physics drop normally
	# But actually, spawned items from machines usually pop out into the world.
	var world = get_tree().current_scene
	if world:
		world.add_child(item)
		if spawn_marker:
			item.global_transform = spawn_marker.global_transform
		else:
			item.global_position = global_position + Vector3(0, 1.0, 0)
			
		print("CraftingStation: Successfully spawned " + scene_path)
		return true
		
	return false
