extends Equipment
class_name CabinLightStrip

func get_status() -> String:
	if not can_operate(): return "未供電｜設備停用、拆下或損壞"
	var rv := get_connected_rv()
	if not rv.interior_requested.cabin: return "照明關閉"
	return "照明中" if rv.interior_powered.cabin and rv.has_usable_power() else "等待供電"

func get_interaction_prompt(_player: Node3D) -> String:
	return "車內燈條｜由控制台控制照明\n長按 F 搬移／拆裝｜H 維修"
