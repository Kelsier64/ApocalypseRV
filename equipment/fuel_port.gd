extends Item

func get_interaction_prompt(player: Node3D) -> String:
	var rv := get_connected_rv()
	if rv == null: return "加油孔｜未接入 RV，請先安裝到車上"
	var text := "加油孔｜本車燃油 %.1f / %.0f\n燃油保存在底盤；拆除加油孔不會損失燃油" % [rv.current_fuel, rv.max_fuel]
	if not can_operate(): return text + "\n無法使用：請先維修或結束搬移"
	if rv.current_fuel >= rv.max_fuel - 0.01: return text + "\n燃油已滿"
	return text + ("\nE：加入手持汽油罐" if player.get_active_item_name() == ItemNames.GAS_CAN else "\n請手持汽油罐，再按 E 加油")

func interact(player: Node3D) -> String:
	if not player.can_use_hands(): return "加油需要可用手臂"
	if not can_operate(): return "加油孔尚未接入或無法使用，請先安裝／維修"
	var rv := get_connected_rv()
	if player.get_active_item_name() != ItemNames.GAS_CAN: return "需要手持汽油罐"
	if rv.current_fuel >= rv.max_fuel - 0.01: return "燃油已滿，未消耗汽油罐"
	if not is_finite(rv.fuel_per_gas_can) or rv.fuel_per_gas_can <= 0.0: return "Fuel transfer unavailable"
	# The can conversion must succeed before the chassis receives any fuel.
	# Retain the original records and selection so failed grants lose nothing.
	var previous_items: Array[Dictionary] = player.inventory.items.duplicate(true)
	var previous_slot: int = player.inventory.active_slot
	var can_id: String = player.inventory.active_item().get("state", {}).get("id", "")
	if not player.inventory.consume_active(): return "找不到手持汽油罐"
	if not player.add_item(ItemNames.GAS_CAN_EMPTY, false, "res://props/gas_can_empty.tscn"):
		_restore_inventory(player, previous_items, previous_slot)
		return "Empty can could not be created; fuel can retained"
	if player.inventory.items.size() != previous_items.size():
		_restore_inventory(player, previous_items, previous_slot)
		return "Empty can could not be created; fuel can retained"
	var empty: Dictionary = player.inventory.items.back()
	var empty_id: String = empty.get("state", {}).get("id", "")
	if empty.get("scene_path", "") != "res://props/gas_can_empty.tscn" or empty_id.is_empty():
		_restore_inventory(player, previous_items, previous_slot)
		return "Empty can could not be created; fuel can retained"
	var added: float = rv.add_fuel(rv.fuel_per_gas_can)
	if added <= 0.0:
		_restore_inventory(player, previous_items, previous_slot)
		return "No fuel transferred; fuel can retained"
	rv.refuel_committed.emit(persistent_id, can_id, empty_id, added)
	player.refresh_inventory()
	return "已加入 %.1f 燃油，空罐已放回背包" % added

func _restore_inventory(player: Node3D, items: Array[Dictionary], slot: int) -> void:
	player.inventory.items = items
	player.inventory.active_slot = slot
	player.refresh_inventory()
