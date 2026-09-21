extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(okay: bool, message: String) -> void:
	if not okay: failures.append(message)
func _run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(12, 1, 0)
	await physics_frame
	check_simplified_load(rv, player)
	check(not rv.add_item(ItemNames.METAL_PARTS, -1) and not rv.deduct_materials({ItemNames.METAL_PARTS: -2}), "Negative material transactions rejected")
	rv.add_item(ItemNames.METAL_PARTS, 10)
	var rack: Equipment = rv.get_node("ItemBox")
	rack.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(12, 1, 2)), world)
	rv.update_storage_capacity()
	check(rv.storage.capacity == 300 and rv.get_item_count(ItemNames.METAL_PARTS) == 10, "Removing item box preserves chassis material capacity")
	check(rv.add_item(ItemNames.METAL_PARTS, 1), "Material deposits do not require a box")
	rv.deduct_materials({ItemNames.METAL_PARTS: 1})
	rack.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(-0.9, 0.8, 4.5)), rv)
	var tank: Equipment = rv.get_node("FuelPort")
	rv.current_fuel = 31.0
	tank.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(12, 1, 4)), world)
	check(rv.current_fuel == 31.0 and rv.set_engine_running(true), "Detached fuel port leaves fuel and engine available")
	rv.set_engine_running(false)
	tank.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0.9, 0.8, 4.5)), rv)
	check(rv.current_fuel == 31.0 and rv.max_fuel == 100.0, "Reinstalled fuel port does not add fuel or capacity")
	tank.take_damage(120.0 - 1.0)
	var repair := RepairOperation.new()
	repair.step(player, tank, true, 1.0)
	repair.step(player, null, false, 0.1)
	check(rv.get_item_count(ItemNames.METAL_PARTS) == 10, "Interrupted repair costs nothing")
	repair.step(player, tank, true, 2.0)
	check(tank.current_health == 61.0 and rv.get_item_count(ItemNames.METAL_PARTS) == 8, "Repair commits material cost and health together")
	rv.energy.battery = null
	check(rv.current_power == 0.0 and rv.max_power == 0.0 and not rv.consume_power(0.1), "No battery means no hidden power")
	check(rv.set_engine_running(true), "Manual ignition permits recovery without battery")
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	check(rv.current_power == 0.0 and rv.current_fuel < 31.0, "No battery: idling burns fuel without storing electricity")
	rv.set_engine_running(false)
	rv.energy.battery = BatteryState.new()
	rv.energy.battery.charge = 12.0
	check(rv.remove_wheel_to_world(0), "Targeted wheel removal")
	var found: Prop
	for item in WorldEntities.get_container(world).get_children():
		if item is Prop and item.item_name == ItemNames.WHEEL: found = item
	found.condition = 27.0
	player.add_prop_item(found, found.scene_file_path)
	found.queue_free()
	check(rv.install_wheel_from_player(player, 0) and rv.wheel_health[0] == 27.0, "Wheel condition survives removal and installation")
	rv.update_load()
	var mass_before := rv.mass
	tank.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(12, 1, 4)), world)
	rv.update_load()
	check(is_equal_approx(mass_before - rv.mass, tank.mass), "Detached module removes exactly its installed weight")
	tank.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0.9, 0.8, 4.5)), rv)
	var snapshot := VehicleSnapshot.capture(rv)
	snapshot.equipment[0].support = snapshot.equipment[0].id
	check(not VehicleSnapshot.validate(snapshot), "Cyclic supports rejected before restore")
	var gen: Equipment = load("res://equipment/generator.tscn").instantiate()
	rv.add_child(gen)
	gen.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)), rv)
	rv.current_power = 0.0
	rv.current_fuel = 80.0
	rv.set_engine_running(true)
	for tick in range(60): rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	check(rv.current_power > 80.0 and rv.current_fuel < 80.0, "Empty battery recovers through paid stationary generation")
	rv.set_engine_running(false)
	for tick in range(1200): rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	check(rv.current_power == 0.0, "Twenty-minute stopped simulation exhausts battery without going negative")
	check(rv.energy.generated_rate == 0.0, "Engine-off long stop never generates")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: RV capacity, repairs, wheel state, load and long-stop energy")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check_simplified_load(rv: Chassis, player: Node3D) -> void:
	rv.update_load()
	var initial_mass := rv.mass
	var initial_center := rv.center_of_mass
	var initial_pose := rv.transform
	for i in range(120):
		rv.transform = Transform3D(Basis(Vector3.UP, i * 0.07), Vector3(5000 + i * 0.5, 2, -5000 - i))
		rv.update_load()
		check(rv.center_of_mass == initial_center, "Driving far from origin does not rewrite unchanged center of mass")
	rv.transform = initial_pose
	var socket: BatterySocket = rv.get_battery_socket()
	var original_battery := socket.installed_battery
	var large_battery := BatteryState.new({"capacity": 200.0, "charge": 175.0, "weight": 30.0})
	check(player.add_item(ItemNames.BATTERY, false, "res://props/battery_large.tscn", {"id": large_battery.id, "battery": large_battery.snapshot()}), "Large battery enters inventory")
	check(rv.exchange_battery(player, socket), "Large battery exchange succeeds")
	rv.update_load()
	check(is_equal_approx(rv.mass, initial_mass) and rv.center_of_mass.is_equal_approx(initial_center), "Battery capacity and weight do not affect vehicle load")
	check(rv.max_power == 200.0 and rv.current_power == 175.0 and rv.consume_power(5.0) and rv.current_power == 170.0, "Weightless battery retains capacity and paid power use")
	check(rv.remove_battery_to_player(player, socket), "Battery removal succeeds")
	rv.update_load()
	check(is_equal_approx(rv.mass, initial_mass) and rv.center_of_mass.is_equal_approx(initial_center), "Empty battery socket keeps the same vehicle load")
	check(rv.current_power == 0.0 and not rv.consume_power(1.0), "Empty socket has no hidden power")
	player.inventory.items.clear()
	player.refresh_inventory()
	socket.installed_battery = original_battery
	var initial_fuel := rv.current_fuel
	check(rv.add_item(ItemNames.METAL_PARTS, 100), "Materials enter shared storage")
	rv.current_fuel = 0.0
	rv.update_load()
	check(is_equal_approx(rv.mass, initial_mass) and rv.center_of_mass.is_equal_approx(initial_center), "Materials and fuel quantity do not affect vehicle load")
	check(rv.deduct_materials({ItemNames.METAL_PARTS: 100}), "Materials leave shared storage")
	rv.current_fuel = initial_fuel
	var engine := rv.get_engine()
	rv.engine_bay.get_node("Hatch").set_open(true)
	check(rv.remove_engine(player).contains("已取出"), "Installed engine becomes a carried item")
	var empty_mass := rv.mass
	var empty_center := rv.center_of_mass
	check(is_equal_approx(initial_mass - empty_mass, engine.definition().weight), "Removing engine removes its installed weight")
	check(not empty_center.is_equal_approx(initial_center), "Removing front engine changes center of mass")
	var stored_index := rv.stored_items.size()
	check(rv.store_player_item(player, 0), "Carried engine enters warehouse")
	rv.update_load()
	check(is_equal_approx(rv.mass, empty_mass) and rv.center_of_mass.is_equal_approx(empty_center), "Stored engine contributes no vehicle load")
	check(rv.take_stored_item(player, stored_index), "Stored engine returns to inventory")
	rv.update_load()
	check(is_equal_approx(rv.mass, empty_mass) and rv.center_of_mass.is_equal_approx(empty_center), "Taking stored engine leaves vehicle load unchanged")
	check(rv.exchange_engine(player).contains("已裝入"), "Engine reinstalls from inventory")
	check(is_equal_approx(rv.mass, initial_mass) and rv.center_of_mass.is_equal_approx(initial_center), "Reinstalling engine restores weight and center of mass")
	rv.engine_bay.get_node("Hatch").set_open(false)
	# Existing v3 saves retain positive battery weight as item physics data.
	var saved := VehicleSnapshot.capture(rv)
	for entry in saved.equipment:
		if entry.service.has("battery") and not entry.service.battery.is_empty():
			entry.service.battery.weight = 200.0
	check(VehicleSnapshot.apply(rv, saved), "Existing save with battery weight still loads")
	check(is_equal_approx(rv.mass, initial_mass) and rv.center_of_mass.is_equal_approx(initial_center), "Restored battery weight does not re-enter vehicle load")
	check(rv.energy.battery.id == original_battery.id and rv.max_power == original_battery.capacity and rv.current_power == original_battery.charge, "Restore preserves battery identity and energy")
