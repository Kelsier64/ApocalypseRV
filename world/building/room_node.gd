extends Node3D
class_name RoomNode

@export var room_name: String = "Standard Room"
@export var weight: float = 1.0  # Higher = more likely to spawn
@export var grid_size: Vector3i = Vector3i.ONE # How many 9m cubes this room takes up

# Array of dictionaries: {"wall": String, "grid_offset": Vector3i}
@export var doors: Array = []

func get_real_size() -> Vector3:
	return Vector3(grid_size.x, grid_size.y, grid_size.z) * 9.0  # BASE_UNIT
