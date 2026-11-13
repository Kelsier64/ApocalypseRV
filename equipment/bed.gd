extends Item
class_name Bed

const MAX_REST_SPEED := 0.5
var occupant: Node3D

func can_operate() -> bool:
	if presentation_only or not is_fixed or not enabled or support_lost or is_being_placed or is_destroyed or is_queued_for_deletion() or current_health <= 0.0:
		return false
	var rv := get_connected_rv() as RigidBody3D
	return global_basis.y.dot(Vector3.UP) > 0.93 and (rv == null or ClimbMath.point_velocity(rv, global_position).length() <= MAX_REST_SPEED)

func interact(player: Node3D) -> String:
	if not can_operate() or is_instance_valid(occupant): return "Bed unavailable"
	return player.begin_rest(self)

func can_pickup(player: Node3D) -> bool:
	return not is_instance_valid(occupant) and super.can_pickup(player)
