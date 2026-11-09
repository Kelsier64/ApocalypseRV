extends Item
class_name PistolAmmo
var rounds := PistolRules.BOX_CAPACITY

func capture_item_state() -> Dictionary:
	var state := super.capture_item_state()
	state["ammo"] = {"rounds": rounds}
	return state

func restore_item_state(state: Dictionary) -> void:
	super.restore_item_state(state)
	rounds = int(state.get("ammo", {}).get("rounds", PistolRules.BOX_CAPACITY))
