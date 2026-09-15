extends Prop

var materials: Dictionary = {}

func capture_item_state() -> Dictionary:
	var state := super.capture_item_state()
	state["materials"] = materials.duplicate(true)
	return state

func restore_item_state(state: Dictionary) -> void:
	super.restore_item_state(state)
	materials = state.get("materials", {}).duplicate(true)
	scrap_yields.clear()
	for material in materials:
		scrap_yields[material] = Vector2(materials[material], materials[material])
