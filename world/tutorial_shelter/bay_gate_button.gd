extends "res://world/starting_shelter/garage_button.gd"
## Same physical case, press animation and status materials as the old shelter.
@export var target_gate: NodePath
var _gate: ShelterGarageGate
var _shown_phase := ""

func _ready() -> void:
	_gate = get_node_or_null(target_gate) as ShelterGarageGate
	_button = get_node("Visuals/Button")
	_lamp = get_node("Visuals/StatusLamp")
	_rest_position = _button.position
	_button.material_override = _button.material_override.duplicate()
	_lamp.material_override = _lamp.material_override.duplicate()
	_process(0.0)

func _process(_delta: float) -> void:
	if not is_instance_valid(_gate): return
	var phase := "opening" if not _gate.stable() else ("started" if _gate.is_open() else "preparing")
	if phase == _shown_phase: return
	_shown_phase = phase
	_set_color(_phase_color(phase))

func get_interaction_prompt(_player: Node3D) -> String:
	if not is_instance_valid(_gate): return ""
	return "Bay gate | E: " + ("Close" if _gate.target > 0.5 else "Open")

func interact(_player: Node3D) -> String:
	if not is_instance_valid(_gate): return "Gate unavailable"
	var opening := _gate.target < 0.5
	_gate.move_to(opening)
	_on_phase_changed("opening")
	return "Opening bay gate" if opening else "Closing bay gate"
