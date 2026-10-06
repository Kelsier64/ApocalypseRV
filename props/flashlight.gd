extends Item
class_name Flashlight

const FULL_CHARGE := 100.0
const DRAIN_SECONDS := 300.0

var charge: float = FULL_CHARGE
var switched_on: bool = false

func capture_item_state() -> Dictionary:
	var state := super.capture_item_state()
	state["flashlight"] = {"charge": charge, "on": switched_on}
	return state

func restore_item_state(state: Dictionary) -> void:
	super.restore_item_state(state)
	var saved: Dictionary = state.get("flashlight", {})
	charge = clampf(float(saved.get("charge", FULL_CHARGE)), 0.0, FULL_CHARGE)
	switched_on = bool(saved.get("on", false)) and charge > 0.0
	set_held_active(false)

func _ready() -> void:
	super._ready()
	set_held_active(false)

func set_held_active(active: bool) -> void:
	var light := get_node_or_null("Beam") as SpotLight3D
	if light: light.visible = active and switched_on and charge > 0.0

func get_interaction_prompt(player: Node3D) -> String:
	return "手電筒｜電量 %.0f%%\n%s" % [charge, super.get_interaction_prompt(player)]
