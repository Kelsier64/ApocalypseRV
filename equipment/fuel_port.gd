extends Item

func get_interaction_prompt(player: Node3D) -> String:
	var rv := get_connected_rv()
	if rv == null: return "Fuel inlet | Install on the RV first"
	var text := "Fuel inlet | Fuel %.1f / %.0f\nFuel stays in the chassis when the inlet is removed" % [rv.current_fuel, rv.max_fuel]
	if not can_operate(): return text + "\nRepair the inlet or finish moving it first"
	if rv.current_fuel >= rv.max_fuel - 0.01: return text + "\nFuel tank full"
	return text + ("\nE Refuel with held Gasoline Can" if player.get_active_item_name() == ItemNames.GAS_CAN else "\nHold a Gasoline Can and press E to refuel")

func interact(player: Node3D) -> String:
	if not player.can_use_hands(): return "Refueling requires an available arm"
	if not can_operate(): return "Install or repair the fuel inlet first"
	var rv := get_connected_rv()
	if player.get_active_item_name() != ItemNames.GAS_CAN: return "Hold a Gasoline Can"
	if rv.current_fuel >= rv.max_fuel - 0.01: return "Fuel tank full. Gasoline Can kept."
	if not is_finite(rv.fuel_per_gas_can) or rv.fuel_per_gas_can <= 0.0: return "Fuel transfer unavailable"
	# The can conversion must succeed before the chassis receives any fuel.
	# Retain the original records and selection so failed grants lose nothing.
	var previous_items: Array[Dictionary] = player.inventory.items.duplicate(true)
	var previous_slot: int = player.inventory.active_slot
	var can_id: String = player.inventory.active_item().get("state", {}).get("id", "")
	if not player.inventory.consume_active(): return "Held Gasoline Can unavailable"
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
	return "Added %.1f fuel. Empty can returned to inventory." % added

func _restore_inventory(player: Node3D, items: Array[Dictionary], slot: int) -> void:
	player.inventory.items = items
	player.inventory.active_slot = slot
	player.refresh_inventory()
