extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var inventory := PlayerInventory.new()
	_expect(not inventory.is_holding_large_item(), "Empty hands do not block climbing.")
	_expect(not inventory.consume_active(), "Empty inventory cannot consume an item.")
	_expect(inventory.add_item("Scrap", false, "res://props/scrap.tscn"), "Small items fit.")
	_expect(not inventory.is_holding_large_item(), "Small items do not block climbing.")
	var large_state := {"id": "large-climb-test", "condition": 37.0}
	_expect(inventory.add_item("Custom cargo", true, "res://props/oil_barrel.tscn", large_state), "First large item fits.")
	_expect(inventory.is_holding_large_item(), "Active is_large flag blocks climbing independently of the item name.")
	_expect(inventory.active_item().state == large_state, "Query preserves the large item's identity and condition.")
	_expect(inventory.active_item().get("name") == "Custom cargo", "Large item becomes active.")
	_expect(not inventory.select_slot(0), "Large item prevents switching slots.")
	_expect(not inventory.add_item("Barrel", true, "unused"), "Second large item is refused.")
	_expect(inventory.consume_active(), "Active large item can be consumed.")
	_expect(not inventory.is_holding_large_item(), "Removing the large item immediately releases the climb restriction.")
	_expect(inventory.active_item().get("name") == "Scrap", "Selection clamps after removal.")
	_expect(inventory.add_item("Wheel", true, "res://props/wheel.tscn"), "Removing a large item releases the limit.")
	inventory.consume_active()
	_expect(inventory.select_slot(5), "Empty hotbar slots remain selectable.")
	_expect(not inventory.is_holding_large_item(), "Selected empty hotbar slot does not block climbing.")
	_expect(inventory.active_item().is_empty(), "Empty slot has no active item.")
	_expect(not inventory.select_slot(-1) and not inventory.select_slot(6), "Out-of-range slots are refused.")
	for index in range(5):
		_expect(inventory.add_item("Scrap", false, "unused"), "Remaining slots accept items.")
	_expect(not inventory.add_item("Overflow", false, "unused"), "Capacity is enforced.")
	_expect(inventory.consume_active() and inventory.active_slot == 4, "Removing the final slot clamps selection.")
	if failures.is_empty():
		print("PASS: player inventory rules")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
