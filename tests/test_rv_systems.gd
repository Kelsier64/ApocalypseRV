extends SceneTree

var failures: Array[String] = []
var world: Node3D

func _init() -> void:
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var rv: Chassis = load("res://rv/new_rv.tscn").instantiate().get_node("Chassis")
	var shell := rv.get_parent()
	world.add_child(shell)
	rv.freeze = true
	rv.set_physics_process(false)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.position = Vector3(20, 1, 0)
	player.set_physics_process(false)
	var generator: Item = rv.get_node("Generator")
	generator.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), rv)
	await physics_frame
	expect(rv.get_equipment().has(generator), "Installed generator registers with this RV")
	rv.current_power = 50.0
	var fuel := rv.current_fuel
	rv.step_energy_system(1.0, 0.0, 0.0, 1.0)
	expect(is_equal_approx(rv.current_fuel, fuel) and rv.current_power < 50.0, "Engine off: throttle cannot create charge or burn fuel")
	rv.set_engine_running(true)
	rv.current_power = 50.0
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	expect(rv.current_power > 50.0 and rv.current_fuel < fuel, "Stationary engine burns fuel and charges battery")
	generator.set_enabled(false)
	var before := rv.current_power
	rv.step_energy_system(1.0, 0.0, 0.0, 1.0)
	expect(rv.current_power < before, "No enabled generator: engine does not provide hidden charge")
	generator.set_enabled(true)
	generator.prepare_pickup()
	before = rv.current_power
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	expect(rv.current_power < before, "Generator cannot run in placement preview")
	generator.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), rv)
	var battery: Item = load("res://props/battery.tscn").instantiate()
	world.add_child(battery)
	battery.battery.charge = 23.0
	var battery_id: String = battery.battery.id
	expect(player.add_prop_item(battery, "res://props/battery.tscn"), "Battery pickup")
	battery.queue_free()
	rv.current_power = 61.0
	var old_id := rv.energy.battery.id
	expect(rv.exchange_battery(player), "Battery exchange succeeds")
	expect(rv.current_power == 23.0 and rv.energy.battery.id == battery_id, "Installed battery preserves identity and charge")
	expect(player.inventory.active_item().state.battery.charge == 61.0 and player.inventory.active_item().state.battery.id == old_id, "Old battery returns to the same inventory slot")
	for index in range(5):
		player.add_item(ItemNames.WHEEL, false, "res://props/wheel.tscn")
	expect(not rv.remove_battery_to_player(player) and rv.current_power == 23.0, "Full inventory removal preserves battery")
	expect(rv.exchange_battery(player) and rv.current_power == 61.0, "Full inventory allows atomic slot exchange")
	# Production placement leaves room for the real output collider below the roof.
	var station: CraftingStation = rv.get_node("CraftingStation")
	rv.add_item(ItemNames.METAL_PARTS, 10)
	rv.add_item(ItemNames.UNREFINED_FUEL, 10)
	rv.current_power = 0.1
	expect(not station.request_craft("gasoline") and rv.get_item_count(ItemNames.METAL_PARTS) == 10, "Insufficient complete craft fee cannot debit materials")
	rv.current_power = 20.0
	expect(not station.spawn_item("res://props/missing.tscn", {ItemNames.METAL_PARTS: 2}) and rv.current_power == 20.0, "Invalid output does not debit power")
	expect(station.request_craft("gasoline"), "Valid production request reserves materials")
	station.cancel_jobs()
	expect(rv.get_item_count(ItemNames.METAL_PARTS) == 10, "Cancelled work refunds reserved materials")
	expect(station.request_craft("gasoline"), "Queue production again")
	station.step_work(2.0)
	expect(station.jobs.is_empty(), "Production completes and emits an item")
	expect(rv.get_item_count(ItemNames.METAL_PARTS) == 8 and is_equal_approx(rv.current_power, 19.4), "Production charges exactly once")
	var tablet: Item = load("res://equipment/tablet_screen.tscn").instantiate()
	rv.add_child(tablet)
	tablet.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(1, 1, 2)), rv)
	tablet.interact_hold(player)
	expect(player.in_ui_mode, "Tablet opens")
	tablet.take_damage(1000.0)
	expect(player.in_ui_mode and not tablet.is_destroyed, "Immune tablet remains usable after damage")
	tablet.detach_from_support()
	expect(not player.in_ui_mode, "Losing tablet support releases player UI mode")
	var scrapper: Item = load("res://equipment/scrapper.tscn").instantiate()
	rv.add_child(scrapper)
	scrapper.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0, 1, -2)), rv)
	var scrap: Item = load("res://props/scrap.tscn").instantiate()
	world.add_child(scrap)
	scrap.global_position = scrapper.global_position + Vector3.UP
	var original_mask := scrap.collision_mask
	scrapper.recycle_prop(scrap)
	expect(scrap.freeze and scrap.processing_owner == scrapper, "Scrapper owns and freezes accepted input")
	scrapper.take_damage(1000.0)
	expect(not scrap.freeze and scrap.processing_owner == null and scrap.collision_mask == original_mask, "Destroyed scrapper releases original physics")
	expect(not PlacementRules.valid_target(generator, scrap) and not PlacementRules.valid_target(generator, player), "Props and actors reject placement")
	var loose: Item = load("res://equipment/generator.tscn").instantiate()
	world.add_child(loose)
	loose.freeze = false
	loose.collision_mask = 3
	expect(not loose.can_operate() and not loose.freeze and loose.collision_mask == 3, "Loose device retains physics and does not operate")
	var support: RVStructurePanel = rv.get_node("RoofMiddle")
	generator.set_mount_support(support)
	support.take_damage(1000.0)
	await process_frame
	await process_frame
	expect(generator.get_connected_rv() == null and not generator.freeze, "Destroyed support detaches dependent equipment")
	rv.take_damage(1000.0)
	rv.set_driving_state(true)
	expect(rv.is_player_driving and not rv.set_engine_running(true), "Failed engine retains controls but rejects engine restart")
	rv._physics_process(1.0 / 60.0)
	expect(rv.engine_force == 0.0, "Failed engine cannot apply propulsion")
	rv.engine_bay.repair_health(450.0)
	rv.get_node("DriverSeat").interact_hold(player)
	expect(player.seated_in != null, "Engine repair permits restarting without disabling seating")
	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: RV engine, batteries, production and lifecycle")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
