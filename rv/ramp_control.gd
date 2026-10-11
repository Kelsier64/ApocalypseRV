extends StaticBody3D
## Presentation follows the ramp state; the interaction body stays active during travel.
var _presentation_state := -1
func sync_state(moving: bool, extending: bool, deployed: bool) -> void:
	var state := 2 + int(extending) if moving else int(deployed)
	if state == _presentation_state: return
	_presentation_state = state
	$Visuals/Rocker.rotation.x = deg_to_rad(-12 if extending else 12) if moving else 0.0
	$Visuals/Status.modulate = Color("ffc15a") if moving else (Color("8fe3ad") if deployed else Color("b4c3c7"))
	$Visuals/Status.text = "MOVING" if moving else ("DEPLOYED" if deployed else "STOWED")
	var light: StandardMaterial3D = $Visuals/Lamp.material_override
	light.albedo_color = $Visuals/Status.modulate
	light.emission = light.albedo_color
func interact(player: Node3D) -> String: return get_parent().interact(player)
func get_interaction_prompt(player: Node3D) -> String: return get_parent().get_interaction_prompt(player)
func allows_mount_at(_point: Vector3) -> bool: return false
