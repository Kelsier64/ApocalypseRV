extends StaticBody3D
func interact(player: Node3D) -> String: return get_parent().interact(player)
func get_interaction_prompt(player: Node3D) -> String: return get_parent().get_interaction_prompt(player)
func allows_mount_at(_point: Vector3) -> bool: return false
