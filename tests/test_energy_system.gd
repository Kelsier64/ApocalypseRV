extends SceneTree

var failures: Array[String] = []

class FakeRefuelPlayer extends Node3D:
	var active_item_name: String = "Gasoline Can"
	var consumed_active: bool = false
	var added_items: Array[Dictionary] = []

	func get_active_item_name() -> String:
		return active_item_name

	func consume_active_item() -> void:
		consumed_active = true

	func add_item(item_name: String, is_large: bool, scene_path: String) -> bool:
		added_items.append({
			"name": item_name,
			"is_large": is_large,
			"scene_path": scene_path
		})
		return true

func _init() -> void:
	_test_chassis_resource_api()
	_test_chassis_resource_behavior()
	_test_generator_behavior()
	_test_equipment_power_usage()
	_test_gas_can_states()
	_finish()

func _test_chassis_resource_api() -> void:
	var rv := Chassis.new()
	_expect(rv.has_method("consume_fuel"), "Chassis should expose consume_fuel(amount).")
	_expect(rv.has_method("consume_power"), "Chassis should expose consume_power(amount).")
	_expect(rv.has_method("add_fuel"), "Chassis should expose add_fuel(amount).")
	_expect(rv.has_method("add_power"), "Chassis should expose add_power(amount).")
	_expect(rv.has_method("step_energy_system"), "Chassis should expose step_energy_system(throttle, braking, steering, delta).")
	_expect(rv.has_method("has_usable_power"), "Chassis should expose has_usable_power(required).")
	_expect(rv.has_method("refuel_from_player"), "Chassis should expose refuel_from_player(player).")
	rv.free()

func _test_chassis_resource_behavior() -> void:
	var rv := Chassis.new()
	rv.max_fuel = 100.0
	rv.max_power = 100.0
	rv.current_fuel = 10.0
	rv.current_power = 10.0

	if rv.has_method("consume_fuel"):
		_expect(rv.consume_fuel(2.5), "consume_fuel should return true when enough fuel exists.")
		_expect(_approx(rv.current_fuel, 7.5), "consume_fuel should decrease current_fuel.")
		_expect(not rv.consume_fuel(8.0), "consume_fuel should fail when amount exceeds available fuel.")

	if rv.has_method("consume_power"):
		_expect(rv.consume_power(2.0), "consume_power should return true when enough power exists.")
		_expect(_approx(rv.current_power, 8.0), "consume_power should decrease current_power.")
		_expect(not rv.consume_power(20.0), "consume_power should fail when amount exceeds available power.")

	if rv.has_method("step_energy_system"):
		rv.current_fuel = 20.0
		rv.current_power = 10.0
		rv.step_energy_system(1.0, 0.0, 0.0, 1.0)
		_expect(rv.current_fuel < 20.0, "Driving step should consume fuel while throttling.")
		_expect(rv.current_power > 10.0, "Driving step should charge power while driving.")

		rv.current_fuel = 20.0
		rv.current_power = 10.0
		rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
		_expect(rv.current_power < 10.0, "Idle step should slowly consume power while parked.")

		rv.current_fuel = 5.0
		rv.current_power = 0.0
		_expect(not rv.has_usable_power(), "has_usable_power should be false at zero power.")
		rv.current_power = 0.5
		_expect(rv.has_usable_power(0.25), "has_usable_power should be true when power exceeds requested amount.")

	rv.free()

func _test_generator_behavior() -> void:
	var script: Script = load("res://equipment/generator.gd")
	_expect(script != null, "Generator script res://equipment/generator.gd should exist.")
	if script == null:
		return

	var generator: Node = script.new()
	_expect(generator.has_method("generate_power"), "Generator should expose generate_power(rv, delta).")

	var rv := Chassis.new()
	rv.max_fuel = 100.0
	rv.max_power = 100.0
	rv.current_fuel = 10.0
	rv.current_power = 0.0

	if generator.has_method("generate_power") and rv.has_method("consume_fuel") and rv.has_method("add_power"):
		generator.generate_power(rv, 1.0)
		_expect(rv.current_power > 0.0, "Generator should add power to RV.")
		_expect(rv.current_fuel < 10.0, "Generator should consume fuel while generating power.")

		rv.current_fuel = 10.0
		rv.current_power = 99.5
		generator.generate_power(rv, 1.0)
		_expect(rv.current_power <= rv.max_power, "Generator should not overfill RV power beyond max.")
		_expect(rv.current_fuel > 9.3, "Near-full charge should not consume a full fuel tick.")

	generator.free()
	rv.free()

func _test_equipment_power_usage() -> void:
	var rv := Chassis.new()
	rv.add_to_group("rv")
	rv.max_power = 100.0
	rv.current_power = 5.0

	var equip := Equipment.new()
	rv.add_child(equip)

	_expect(equip.has_method("consume_rv_power"), "Equipment should expose consume_rv_power(amount).")

	if equip.has_method("consume_rv_power"):
		_expect(equip.consume_rv_power(1.5), "consume_rv_power should succeed when RV has enough power.")
		_expect(_approx(rv.current_power, 3.5), "consume_rv_power should decrease RV power.")
		_expect(not equip.consume_rv_power(4.0), "consume_rv_power should fail when RV power is insufficient.")

	equip.free()
	rv.free()

func _test_gas_can_states() -> void:
	var rv := Chassis.new()
	rv.max_fuel = 100.0
	rv.current_fuel = 10.0

	var player := FakeRefuelPlayer.new()
	rv.refuel_from_player(player)

	_expect(player.consumed_active, "Refueling with a full gas can should consume the active item.")
	_expect(rv.current_fuel > 10.0, "Refueling with a full gas can should increase fuel.")
	_expect(player.added_items.size() == 1, "Refueling should return an empty gas can item.")
	if player.added_items.size() == 1:
		_expect(player.added_items[0]["name"] == "Gasoline Can (Empty)", "Returned item after refuel should be an empty gas can.")

	var rv2 := Chassis.new()
	rv2.max_fuel = 100.0
	rv2.current_fuel = 10.0

	var empty_player := FakeRefuelPlayer.new()
	empty_player.active_item_name = "Gasoline Can (Empty)"
	rv2.refuel_from_player(empty_player)

	_expect(not empty_player.consumed_active, "Empty gas can should not be consumed as refuel source.")
	_expect(_approx(rv2.current_fuel, 10.0), "Empty gas can should not change RV fuel.")

	player.free()
	empty_player.free()
	rv.free()
	rv2.free()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _approx(value: float, expected: float, epsilon: float = 0.0001) -> bool:
	return absf(value - expected) <= epsilon

func _finish() -> void:
	if failures.is_empty():
		print("PASS: energy system tests")
		quit(0)
		return

	push_error("FAIL: energy system tests")
	for failure in failures:
		push_error(" - " + failure)
	quit(1)
