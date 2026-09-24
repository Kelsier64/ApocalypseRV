@tool
extends Marker3D
class_name PoiDoorSocket
## Origin is at the floor of the opening; local -Z points OUT of the room.

@export var socket_id: StringName = &""
@export var interface_type: StringName = &"industrial_3m"
@export var opening := Vector2(3.0, 3.5)
## Optional visual door trim removed when an unused opening becomes a plain wall.
@export var frame_nodes: Array[NodePath] = []

func can_connect(other: PoiDoorSocket) -> bool:
	return other != null and other != self and interface_type == other.interface_type \
		and opening.is_equal_approx(other.opening)
