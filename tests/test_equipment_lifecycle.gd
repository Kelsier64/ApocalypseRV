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
	var equipment := Item.new()
	first.add_child(equipment)
	_expect(equipment.get_connected_rv() == null, "Loose item is not registered to an ancestor RV.")
	first.add_to_group(Groups.RV)
	equipment.confirm_placement(Transform3D.IDENTITY, first)
	_expect(equipment.get_connected_rv() == first and equipment.is_fixed, "Fixed item discovers its RV support.")
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	_expect(player.add_item("Wheel", true, "res://props/wheel.tscn"), "Wheel scene supports unified item pickup.")
	_expect(player.get_active_item_name() == "Wheel" and is_instance_valid(player.held_item_node), "Inventory selection reaches held-item presentation.")
	_expect(player.held_item_node.presentation_only and not player.held_item_node.is_fixed, "Held scene is a presentation-only item.")
	player.consume_active_item()
	_expect(player.get_active_item_name().is_empty(), "Consuming updates inventory API.")
	equipment.confirm_placement(Transform3D.IDENTITY, second)
	_expect(equipment.get_connected_rv() == second, "Confirm reconnects to the new RV.")
	_expect(equipment.consume_rv_power(2.0) and second.power == 8.0 and first.power == 10.0, "Only connected RV supplies power.")
	equipment.confirm_placement(Transform3D.IDENTITY, world)
	_expect(equipment.get_connected_rv() == null and not equipment.consume_rv_power(1.0), "Ground item cannot draw RV power.")
	equipment.confirm_placement(Transform3D.IDENTITY, first)
	equipment.detach_from_support()
	_expect(not equipment.is_fixed and equipment.get_connected_rv() == null and not equipment.freeze, "Support release produces a loose item with physics.")
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
