@tool
extends Node3D
class_name PoiRoom
## Floor-centred, +X east, -Z north, metres. Visuals are replaceable.
## Floor-centered authored room; shared by the workshop and production maze.

const GRID_UNIT := 9.0
@export var room_id: StringName = &""
@export var size_cells := Vector2i.ONE
@export var clear_height: float = 4.5
@export var category: StringName = &"utility"

func get_size() -> Vector3:
	return Vector3(size_cells.x * GRID_UNIT, clear_height, size_cells.y * GRID_UNIT)

func get_socket(socket_id: StringName) -> PoiDoorSocket:
	for child in $DoorSockets.get_children():
		if child is PoiDoorSocket and child.socket_id == socket_id:
			return child
	return null

func connect_to(own_socket_id: StringName, target: PoiDoorSocket) -> bool:
	var own := get_socket(own_socket_id)
	if own == null or not own.can_connect(target):
		return false
	var local_socket := global_transform.affine_inverse() * own.global_transform
	global_transform = target.global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * local_socket.affine_inverse()
	return true

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if room_id.is_empty() or size_cells.x < 1 or size_cells.y < 1 or clear_height < 3.5:
		errors.append("Invalid room metadata: " + str(name))
	for required in ["Visuals", "Collision", "DoorSockets", "Furnishings", "LootSpawns", "EnemySpawns", "Walkway"]:
		if not has_node(required):
			errors.append("Missing authoring layer: " + required)
	if not has_node("DoorSockets"):
		return errors
	var ids: Array[StringName] = []
	var half := get_size() * 0.5
	for socket in $DoorSockets.get_children():
		if not socket is PoiDoorSocket:
			errors.append("DoorSockets must contain PoiDoorSocket markers")
			continue
		if socket.socket_id.is_empty() or ids.has(socket.socket_id):
			errors.append("Missing/duplicate door ID: " + str(socket.name))
		ids.append(socket.socket_id)
		var p: Vector3 = socket.position
		var facing: Vector3 = -socket.basis.z
		var on_x: bool = is_equal_approx(absf(p.x), half.x) and absf(p.z) + socket.opening.x / 2.0 <= half.z
		var on_z: bool = is_equal_approx(absf(p.z), half.z) and absf(p.x) + socket.opening.x / 2.0 <= half.x
		var outward: bool = (on_x and facing.dot(Vector3(signf(p.x), 0, 0)) > 0.999) \
			or (on_z and facing.dot(Vector3(0, 0, signf(p.z))) > 0.999)
		if p.y < 0 or not outward or p.y + socket.opening.y > clear_height or socket.opening.x <= 0:
			errors.append("Door must fit a boundary and face outward: " + str(socket.name))
	if ids.is_empty():
		errors.append("Room needs an entrance socket")
	for marker in find_children("*", "Marker3D", true, false):
		if marker is PoiLootPoint:
			errors.append_array(marker.validate())
	return errors
