extends Item
class_name CabinLightStrip

func get_status() -> String:
	if not can_operate(): return "未供電｜設備停用、拆下或損壞"
	var rv := get_connected_rv()
	if not rv.interior_requested.cabin: return "照明關閉"
	return "照明中" if rv.interior_powered.cabin and rv.has_usable_power() else "等待供電"
