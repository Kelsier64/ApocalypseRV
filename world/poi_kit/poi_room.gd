@tool
extends Node3D
class_name PoiRoom
## Floor-centred, +X east, -Z north, metres. Visuals are replaceable.
@export var room_id: StringName = &""
@export var footprint := Vector2(6, 6)
@export var clear_height: float = 3.6
@export var category: StringName = &"utility"

func get_size() -> Vector3:
	return Vector3(footprint.x, clear_height, footprint.y)

func occupancy() -> AABB:
	return AABB(Vector3(-footprint.x / 2, -0.25, -footprint.y / 2), Vector3(footprint.x, clear_height + 0.5, footprint.y))

func get_socket(socket_id: StringName) -> PoiDoorSocket:
	for child in $DoorSockets.get_children():
		if child is PoiDoorSocket and child.socket_id == socket_id:
			return child
	return null

func socket_transform(socket: PoiDoorSocket) -> Transform3D:
	return $DoorSockets.transform * socket.transform

func connect_to(own_socket_id: StringName, target: PoiDoorSocket) -> bool:
	var own := get_socket(own_socket_id)
	if own == null or not own.can_connect(target):
		return false
	var local_socket := global_transform.affine_inverse() * own.global_transform
	global_transform = target.global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * local_socket.affine_inverse()
	return true

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not scale.is_equal_approx(Vector3.ONE): errors.append("Room root must use unit scale")
	if room_id.is_empty() or not footprint.is_finite() or footprint.x <= 0 or footprint.y <= 0 or not is_finite(clear_height) or clear_height < 2.8:
		errors.append("Invalid room metadata: " + str(name))
	for required in ["Visuals", "Collision", "DoorSockets", "Furnishings", "Walkway"]:
		if not has_node(required):
			errors.append("Missing authoring layer: " + required)
	if not has_node("DoorSockets"):
		return errors
	var ids: Array[StringName] = []
	var visuals := get_node_or_null("Visuals")
	var half := get_size() * 0.5
	for socket in $DoorSockets.get_children():
		if not socket is PoiDoorSocket:
			errors.append("DoorSockets must contain PoiDoorSocket markers")
			continue
		if socket.socket_id.is_empty() or ids.has(socket.socket_id):
			errors.append("Missing/duplicate door ID: " + str(socket.name))
		ids.append(socket.socket_id)
		for path in socket.frame_nodes:
			var frame := socket.get_node_or_null(path)
			if not frame is MeshInstance3D or visuals == null or not visuals.is_ancestor_of(frame):
				errors.append("Door frame must reference a mesh in Visuals: " + str(path))
		var pose := socket_transform(socket)
		var p := pose.origin
		var facing := -pose.basis.z
		var on_x: bool = is_equal_approx(absf(p.x), half.x) and absf(p.z) + socket.opening.x / 2.0 <= half.z
		var on_z: bool = is_equal_approx(absf(p.z), half.z) and absf(p.x) + socket.opening.x / 2.0 <= half.x
		var outward: bool = (on_x and facing.dot(Vector3(signf(p.x), 0, 0)) > 0.999) \
			or (on_z and facing.dot(Vector3(0, 0, signf(p.z))) > 0.999)
		if not pose.is_finite() or not socket.opening.is_finite() or p.y < 0 or not outward or p.y + socket.opening.y > clear_height + 0.001 or socket.opening.x <= 0 or socket.opening.y <= 0 or not pose.basis.get_scale().is_equal_approx(Vector3.ONE) or not pose.basis.y.is_equal_approx(Vector3.UP):
			errors.append("Door must fit a boundary and face outward: " + str(socket.name))
	if ids.is_empty():
		errors.append("Room needs an entrance socket")
	for marker in find_children("*", "Marker3D", true, false):
		if marker is PoiLootPoint:
			errors.append_array(marker.validate())
	return errors
