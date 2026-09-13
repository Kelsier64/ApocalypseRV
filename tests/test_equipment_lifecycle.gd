extends SceneTree

class TestRV extends Node3D:
	var power := 10.0
	func add_item(_name: String, _amount: int) -> void:
		pass
	func deduct_materials(_costs: Dictionary) -> bool:
		return true
	func consume_power(amount: float) -> bool:
		if amount > power:
			return false
		power -= amount
		return true

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var first := TestRV.new()
	var second := TestRV.new()
	world.add_child(first)
	world.add_child(second)
	second.add_to_group(Groups.RV)
	var equipment := Equipment.new()
	first.add_child(equipment)
	_expect(equipment.get_connected_rv() == null, "Unregistered parent is not an RV.")
	first.add_to_group(Groups.RV)
	_expect(equipment.get_connected_rv() == first, "Early null lookup does not stick after RV registration.")
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	_expect(player.add_item("Wheel", true, "res://props/wheel.tscn"), "Wheel scene still supports pickup after removing its empty subclass.")
	_expect(player.get_active_item_name() == "Wheel" and is_instance_valid(player.held_item_node), "Inventory selection reaches held-item presentation.")
	player.consume_active_item()
	_expect(player.get_active_item_name().is_empty(), "Consuming held item updates the player-facing inventory API.")
	_expect(player.enter_ui_mode(), "Player enters UI mode.")
	equipment.start_placement(player)
	_expect(not equipment.is_being_placed, "UI mode rejects equipment placement without mutating equipment.")
	player.exit_ui_mode()
	equipment.start_placement(player)
	_expect(player.is_placing_equipment() and equipment.is_being_placed, "Authorized placement activates both participants.")
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	player.placement.handle_input(player, cancel)
	_expect(not player.is_placing_equipment() and not equipment.is_being_placed, "Cancel restores player and equipment modes.")
	_expect(equipment.get_connected_rv() == first, "Cancel retains original RV connection.")
	equipment.confirm_placement(Transform3D.IDENTITY, second)
	_expect(equipment.get_connected_rv() == second, "Confirm reconnects to the new RV.")
	_expect(equipment.consume_rv_power(2.0) and second.power == 8.0 and first.power == 10.0, "Only connected RV supplies power.")
	equipment.confirm_placement(Transform3D.IDENTITY, world)
	_expect(equipment.get_connected_rv() == null and not equipment.consume_rv_power(1.0), "Ground equipment cannot draw RV power.")
	equipment.reparent(first)
	_expect(equipment.get_connected_rv() == first, "External reparenting is discovered lazily.")
	first.remove_from_group(Groups.RV)
	_expect(equipment.get_connected_rv() == null, "Removing RV registration invalidates a cached connection.")
	world.free()
	if failures.is_empty():
		print("PASS: equipment and player lifecycle")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
