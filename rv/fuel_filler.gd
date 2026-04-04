extends StaticBody3D

func interact(player: Node3D) -> void:
	var chassis := _get_chassis()
	if not chassis:
		return
	if chassis.has_method("refuel_from_player"):
		chassis.refuel_from_player(player)

func _get_chassis() -> Node:
	var current: Node = get_parent()
	while current != null:
		if current.has_method("refuel_from_player") and current.is_in_group("chassis"):
			return current
		current = current.get_parent()
	return null
