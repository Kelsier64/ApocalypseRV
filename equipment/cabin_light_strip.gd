extends Item
class_name CabinLightStrip

func get_status() -> String:
	if not can_operate(): return "No power: disabled, removed or damaged"
	var rv := get_connected_rv()
	if not rv.interior_requested.cabin: return "Lighting off"
	return "Lighting on" if rv.interior_powered.cabin and rv.has_usable_power() else "Waiting for power"
