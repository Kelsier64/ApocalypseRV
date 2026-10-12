extends StaticBody3D
## Local manual control for the stage-one structural acceptance build.
@export var target_gate: NodePath

func get_interaction_prompt(_player: Node3D) -> String:
	var gate := get_node_or_null(target_gate) as ShelterGarageGate
	if gate == null: return ""
	return "Bay gate | E: " + ("Close" if gate.target > 0.5 else "Open")

func interact(_player: Node3D) -> String:
	var gate := get_node_or_null(target_gate) as ShelterGarageGate
	if gate == null: return "Gate unavailable"
	var opening := gate.target < 0.5
	gate.move_to(opening)
	return "Opening bay gate" if opening else "Closing bay gate"
