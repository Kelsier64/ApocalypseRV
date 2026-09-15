extends Equipment

func get_interaction_prompt(player: Node3D) -> String:
	var rv := get_connected_rv()
	if rv == null: return "加油孔｜未接入 RV，請先安裝到車上"
	var text := "加油孔｜本車燃油 %.1f / %.0f\n燃油保存在底盤；拆除加油孔不會損失燃油" % [rv.current_fuel, rv.max_fuel]
	if not can_operate(): return text + "\n無法使用：請先維修或結束搬移"
	if rv.current_fuel >= rv.max_fuel - 0.01: return text + "\n燃油已滿"
	return text + ("\nE：加入手持汽油罐" if player.get_active_item_name() == ItemNames.GAS_CAN else "\n請手持汽油罐，再按 E 加油")

func interact(player: Node3D) -> String:
	if not can_operate(): return "加油孔尚未接入或無法使用，請先安裝／維修"
	var rv := get_connected_rv()
	if player.get_active_item_name() != ItemNames.GAS_CAN: return "需要手持汽油罐"
	if rv.current_fuel >= rv.max_fuel - 0.01: return "燃油已滿，未消耗汽油罐"
	if not player.inventory.consume_active(): return "找不到手持汽油罐"
	var added: float = rv.add_fuel(rv.fuel_per_gas_can)
	player.add_item(ItemNames.GAS_CAN_EMPTY, false, "res://props/gas_can_empty.tscn")
	player.refresh_inventory()
	return "已加入 %.1f 燃油，空罐已放回背包" % added
