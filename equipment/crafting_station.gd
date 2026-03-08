extends Equipment
class_name CraftingStation

@onready var spawn_marker = $SpawnMarker

func _ready():
	super._ready()
	add_to_group("crafting_stations")
	
func spawn_item(scene_path: String) -> bool:
	var item_scene = load(scene_path)
	if not item_scene:
		push_error("CraftingStation: Failed to load " + scene_path)
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
