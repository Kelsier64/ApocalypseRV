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
	rv.take_damage(120.0)
	var repair := RepairOperation.new()
	repair.step(player, rv, true, 1.0)
	repair.step(player, null, false, 0.1)
	check(rv.get_item_count(ItemNames.METAL_PARTS) == 10, "Interrupted repair costs nothing")
	repair.step(player, rv, true, 2.0)
	check(rv.current_chassis_health == 390.0 and rv.get_item_count(ItemNames.METAL_PARTS) == 8, "Repair commits material cost and health together")
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
