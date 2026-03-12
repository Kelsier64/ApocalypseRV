extends StaticBody3D

## Hitbox for an installed wheel on the chassis.
## Hold E to remove the wheel and get a Wheel prop back.

var hold_timer: float = 0.0
var slot_index: int = -1

const WHEEL_PROP_SCENE: String = "res://props/wheel.tscn"

func interact_hold(player: Node3D) -> void:
	var chassis := _get_chassis()
	if not chassis:
		return

	if chassis.has_method("remove_wheel"):
		var spawn_pos: Vector3 = global_position + Vector3(0, 1.0, 0)
		chassis.remove_wheel(slot_index)
		# Spawn a wheel prop at the removal position
		var wheel_scene := load(WHEEL_PROP_SCENE) as PackedScene
		if wheel_scene:
			var wheel_prop := wheel_scene.instantiate()
			chassis.get_parent().add_child(wheel_prop)
			wheel_prop.global_position = spawn_pos

func _get_chassis() -> Node3D:
	# Walk up: WheelHitbox -> Wheel_XX -> Chassis
	var wheel_node := get_parent()
	if wheel_node:
		var chassis := wheel_node.get_parent()
		if chassis and chassis.has_method("install_wheel"):
			return chassis
	return null
