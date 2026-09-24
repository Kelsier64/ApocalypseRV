@tool
extends Resource
class_name InteriorRoomDefinition
## Immutable catalog entry. Scene markers are the single source of socket transforms.
@export var id: StringName
@export var scene: PackedScene
@export var content_version := 1
@export var weight := 1.0
@export var role: StringName = &"ordinary"
@export var selection_group: StringName = &"small"
@export var enabled := true
var _description: Dictionary = {}

func describe() -> Dictionary:
	if not _description.is_empty(): return _description
	if scene == null: return {}
	var room := scene.instantiate() as PoiRoom
	if room == null: return {}
	var sockets: Dictionary = {}
	for socket in room.get_node("DoorSockets").get_children():
		sockets[str(socket.socket_id)] = {"transform": room.socket_transform(socket), "opening": socket.opening, "type": str(socket.interface_type)}
	_description = {"bounds": room.occupancy(), "sockets": sockets}
	room.free()
	return _description

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty() or scene == null or content_version < 1 or not is_finite(weight) or weight < 0 or role not in [&"ordinary", &"entry", &"stairs"]:
		errors.append("Invalid room definition: " + str(id))
		return errors
	var room := scene.instantiate() as PoiRoom
	if room == null:
		errors.append("Room scene must use PoiRoom: " + str(id))
		return errors
	errors.append_array(room.validate())
	var route := room.get_node_or_null("Walkway")
	if route == null or route.get_child_count() == 0 or not route.get_child(0) is Marker3D:
		errors.append("Room needs a walkable navigation anchor: " + str(id))
	if role == &"entry":
		for path in ["Walkway/Spawn", "Walkway/Exit"]:
			if not room.get_node_or_null(path) is Marker3D: errors.append("Entry missing marker: " + path)
	room.free()
	return errors
