@tool
extends Resource
class_name InteriorRoomDefinition
## Immutable catalog entry. Scene markers are the single source of socket transforms.
@export var id: StringName
@export var scene: PackedScene
@export var content_version := 1
@export_range(0.0, 10.0) var weight := 1.0
@export var purpose: StringName = &"service"
var _description: Dictionary = {}

func describe() -> Dictionary:
	if not _description.is_empty(): return _description
	if scene == null: return {}
	var room := scene.instantiate() as PoiRoom
	if room == null: return {}
	var sockets: Dictionary = {}
	for socket in room.get_node("DoorSockets").get_children():
		sockets[str(socket.socket_id)] = {"transform": socket.transform, "opening": socket.opening, "type": str(socket.interface_type)}
	var size := room.get_size()
	_description = {"bounds": AABB(Vector3(-size.x / 2, 0, -size.z / 2), Vector3(size.x, size.y + 0.5, size.z)), "sockets": sockets}
	room.free()
	return _description

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty() or scene == null or content_version != 1 or weight < 0:
		errors.append("Invalid room definition: " + str(id))
		return errors
	var room := scene.instantiate() as PoiRoom
	if room == null:
		errors.append("Room scene must use PoiRoom: " + str(id))
		return errors
	errors.append_array(room.validate())
	room.free()
	return errors
