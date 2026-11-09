extends Item
class_name Flashlight

const FULL_CHARGE := 100.0
const DRAIN_SECONDS := 300.0

var charge: float = FULL_CHARGE
var switched_on: bool = false
var _lens_material: StandardMaterial3D

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
	var lens := get_node("Lens") as MeshInstance3D
	_lens_material = lens.get_active_material(0).duplicate() as StandardMaterial3D
	lens.material_override = _lens_material
	set_held_active(false)

func set_held_active(active: bool) -> void:
	var light := get_node_or_null("Beam") as SpotLight3D
	var emitting := active and switched_on and charge > 0.0
	# Spill inherits Beam visibility, so all light shuts off with one authority.
	if light: light.visible = emitting
	if _lens_material: _lens_material.emission_enabled = emitting
