extends "res://scripts/build_poi_kit_20260915.gd"
## Fresh authoring pass; shared helpers only, never overwrites existing assets.
func _run() -> void:
	concrete = load(BASE + "materials/concrete.tres")
	paint = load(BASE + "materials/paint.tres")
	steel = load(BASE + "materials/steel.tres")
	orange = load(BASE + "materials/orange.tres")
	floor_mat = load(BASE + "materials/floor.tres")
	wood = load(BASE + "materials/wood.tres")
	glow = load(BASE + "materials/light.tres")
	var small := _room("utility_small", Vector2i(1, 1), 4.5, ["north", "south", "east", "west"], "STORES")
	small.room_id = &"maze_utility"
	small.get_node("Furnishings/BenchEast").position.z = 2.6
	_save(small, "rooms/maze_utility.tscn")
	var hall := _room("maintenance_hall", Vector2i(2, 2), 6.0, ["north", "south", "east", "west"], "WORKSHOP")
	hall.room_id = &"maze_hall"
	hall.get_node("Furnishings/Rack1").position.z = -3.0
	_save(hall, "rooms/maze_hall.tscn")
	quit(failures)
