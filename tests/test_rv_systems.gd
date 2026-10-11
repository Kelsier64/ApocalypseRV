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
	var device: Item = rv.get_node("Scrapper")
	device.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), rv)
	await physics_frame
	expect(rv.get_equipment().has(device) and not rv.has_node("Generator"), "Installed devices register while charging is intrinsic to the RV")
	expect(rv.energy.charging_enabled and not rv.energy.charging and rv.energy.fuel_reserve == 5.0 and rv.energy.recharge_below == 0.8, "Intrinsic charging starts with explicit defaults")
	check_unlimited_resources(rv)
	rv.current_power = 50.0
	var fuel := rv.current_fuel
	rv.step_energy_system(1.0, 0.0, 0.0, 1.0)
	expect(is_equal_approx(rv.current_fuel, fuel) and rv.current_power < 50.0 and not rv.energy.charging and rv.energy.generated_rate == 0.0, "Engine off: throttle cannot create charge or burn fuel")
	rv.set_engine_running(true)
	rv.current_power = 50.0
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	expect(rv.current_power > 50.0 and rv.current_fuel < fuel and rv.energy.charging and is_equal_approx(rv.energy.generated_rate, 1.8), "Stationary engine burns fuel and charges battery without generator equipment")
	rv.energy.charging_enabled = false
	var before := rv.current_power
	rv.step_energy_system(1.0, 0.0, 0.0, 1.0)
	expect(rv.current_power < before and not rv.energy.charging and rv.energy.generated_rate == 0.0, "Disabled intrinsic charging leaves engine running without electricity generation")
	rv.energy.charging_enabled = true
	device.prepare_pickup()
	before = rv.current_power
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	expect(rv.current_power > before, "Moving portable equipment does not stop intrinsic charging")
	device.confirm_placement(Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), rv)
	rv.energy.charging = false
	rv.current_power = 90.0
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	expect(not rv.energy.charging and rv.energy.generated_rate == 0.0, "Battery above restart threshold remains paused")
	rv.current_power = 80.0
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	expect(rv.energy.charging and rv.energy.generated_rate > 0.0, "Battery at restart threshold begins charging")
	rv.current_power = 90.0
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	expect(rv.energy.charging and rv.current_power > 90.0, "Active charging continues above its restart threshold")
	rv.current_power = rv.max_power
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	expect(not rv.energy.charging and rv.energy.generated_rate == 0.0 and rv.current_power <= rv.max_power, "Full battery stops charging without overflow")
	rv.current_power = 20.0
	rv.current_fuel = rv.energy.fuel_reserve + rv.fuel_idle_burn_per_second
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	expect(rv.energy.generated_rate == 0.0 and is_equal_approx(rv.current_fuel, rv.energy.fuel_reserve) and rv.energy.engine_running, "Reserve pauses charging while ordinary engine idling remains paid")
	rv.current_fuel = rv.energy.fuel_reserve + rv.fuel_idle_burn_per_second + 0.3
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	expect(is_equal_approx(rv.energy.generated_rate, 0.9) and is_equal_approx(rv.current_fuel, rv.energy.fuel_reserve), "Charging uses the final fuel above reserve proportionally")
	var installed_battery := rv.energy.battery
	rv.energy.battery = null
	rv.current_fuel = 80.0
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	expect(rv.current_power == 0.0 and rv.energy.generated_rate == 0.0 and not rv.energy.charging and rv.current_fuel < 80.0, "Missing battery cannot store intrinsic power while engine fuel still burns")
	rv.energy.battery = installed_battery
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
	var tablet_ui: Node = tablet.ui_instance
	expect(tablet_ui.charging_toggle.button_pressed and tablet_ui.charging_threshold.value == 80.0 and tablet_ui.charging_reserve.value == 5.0, "Tablet displays the RV's charging defaults")
	rv.max_fuel = 160.0
	rv.energy.fuel_reserve = 150.0
	tablet_ui.on_open()
	expect(tablet_ui.charging_reserve.value == 150.0, "Tablet supports saved reserve settings on a larger fuel tank")
	rv.max_fuel = 100.0
	rv.energy.fuel_reserve = 5.0
	tablet_ui.on_open()
	expect(rv.energy.fuel_reserve == 5.0 and tablet_ui.charging_reserve.value == 5.0, "Refreshing a tablet with a smaller fuel capacity cannot overwrite the RV reserve")
	tablet_ui.charging_toggle.button_pressed = false
	tablet_ui.charging_threshold.value = 65.0
	tablet_ui.charging_reserve.value = 17.0
	expect(not rv.energy.charging_enabled and not rv.energy.charging and rv.energy.recharge_below == 0.65 and rv.energy.fuel_reserve == 17.0, "Tablet controls update intrinsic charging settings on the connected RV")
	expect(VehicleSnapshot.capture(rv).charging == {"enabled": false, "charging": false, "fuel_reserve": 17.0, "recharge_below": 0.65}, "Tablet charging choices enter the vehicle save payload")
	tablet_ui.charging_toggle.button_pressed = true
	tablet_ui.charging_threshold.value = 80.0
	tablet_ui.charging_reserve.value = 5.0
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
	expect(not PlacementRules.valid_target(device, scrap) and not PlacementRules.valid_target(device, player), "Props and actors reject placement")
	var loose: Item = load("res://equipment/scrapper.tscn").instantiate()
	world.add_child(loose)
	loose.freeze = false
	loose.collision_mask = 3
	expect(not loose.can_operate() and not loose.freeze and loose.collision_mask == 3, "Loose device retains physics and does not operate")
	var support: RVStructurePanel = rv.get_node("RoofMiddle")
	device.set_mount_support(support)
	support.take_damage(1000.0)
	await process_frame
	await process_frame
	expect(device.get_connected_rv() == null and not device.freeze, "Destroyed support detaches dependent equipment")
	rv.take_damage(1000.0)
	rv.set_driving_state(true)
	expect(rv.is_player_driving and not rv.set_engine_running(true), "Failed engine retains controls but rejects engine restart")
	rv._physics_process(1.0 / 60.0)
	expect(rv.engine_force == 0.0, "Failed engine cannot apply propulsion")
	rv.engine_bay.repair_health(450.0)
	rv.get_node("DriverSeat").interact_hold(player)
	expect(player.seated_in != null, "Engine repair permits restarting without disabling seating")
	check_charging_snapshot(rv)
	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: RV engine, batteries, production and lifecycle")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func check_unlimited_resources(rv: Chassis) -> void:
	expect(not rv.unlimited_materials and not rv.unlimited_fuel, "Production RV defaults to finite resources")
	var stock := rv.get_all_items()
	var fuel := rv.current_fuel
	var power := rv.current_power
	rv.unlimited_materials = true
	rv.unlimited_fuel = true
	var costs := {ItemNames.METAL_PARTS: 10000, ItemNames.UNREFINED_FUEL: 10000}
	for index in range(10):
		expect(rv.has_materials(costs) and rv.deduct_materials(costs), "Unlimited materials permit repeated unaffordable crafting and construction")
	expect(rv.get_all_items() == stock, "Unlimited material use preserves real stock")
	expect(rv.deposit_materials(costs, true) and rv.get_all_items() == stock, "Cancelling free work does not manufacture refunded stock")
	expect(not rv.deduct_materials({ItemNames.METAL_PARTS: -1}) and not rv.has_materials({ItemNames.METAL_PARTS: 1.5}), "Unlimited mode still rejects invalid material costs")
	expect(rv.consume_fuel(10000.0) and rv.current_fuel == fuel, "Unlimited fuel accepts costs exceeding the tank without draining it")
	expect(not rv.consume_fuel(-1.0) and not rv.consume_fuel(INF) and not rv.consume_fuel(NAN), "Unlimited mode still rejects invalid fuel costs")
	rv.current_power = 20.0
	expect(rv.set_engine_running(true), "Demo fuel permits engine start")
	for index in range(120):
		rv.step_energy_system(1.0, 0.0, 0.0, 1.0)
	expect(rv.energy.engine_running and rv.current_fuel == fuel and rv.current_power > 20.0, "Driving and generator charging continue without burning fuel")
	rv.set_engine_running(false)
	rv.current_power = power
	rv.unlimited_materials = false
	rv.unlimited_fuel = false
	expect(not rv.has_materials(costs) and not rv.consume_fuel(10000.0), "Finite resource limits resume when demo policy is disabled")

func check_charging_snapshot(rv: Chassis) -> void:
	rv.energy.charging_enabled = true
	rv.energy.charging = true
	rv.energy.fuel_reserve = 17.0
	rv.energy.recharge_below = 0.65
	var saved := VehicleSnapshot.capture(rv)
	expect(saved.get("charging", {}) == {"enabled": true, "charging": true, "fuel_reserve": 17.0, "recharge_below": 0.65}, "Vehicle snapshot saves charging settings and hysteresis state")
	expect(VehicleSnapshot.validate(saved) and VehicleSnapshot.apply(rv, saved), "Charging settings round trip through vehicle restoration")
	expect(rv.energy.charging_enabled and rv.energy.charging and rv.energy.fuel_reserve == 17.0 and rv.energy.recharge_below == 0.65, "Restoration preserves charging state and customized limits")
	var disabled := saved.duplicate(true)
	disabled.charging.enabled = false
	disabled.charging.charging = false
	expect(VehicleSnapshot.apply(rv, disabled) and not rv.energy.charging_enabled and not rv.energy.charging, "Disabled charging persists across restoration")
	for fault in ["enabled", "charging", "fuel_reserve", "recharge_below", "missing", "extra"]:
		var invalid := saved.duplicate(true)
		match fault:
			"enabled", "charging": invalid.charging[fault] = 1
			"fuel_reserve": invalid.charging.fuel_reserve = NAN
			"recharge_below": invalid.charging.recharge_below = 1.1
			"missing": invalid.charging.erase("enabled")
			"extra": invalid.charging["unexpected"] = true
		expect(not VehicleSnapshot.validate(invalid) and not VehicleSnapshot.apply(rv, invalid), "Malformed charging settings reject before restoration: " + fault)
		expect(not rv.energy.charging_enabled and rv.energy.fuel_reserve == 17.0, "Rejected charging snapshot leaves current settings intact: " + fault)
	saved.erase("charging")
	expect(VehicleSnapshot.validate(saved) and VehicleSnapshot.apply(rv, saved), "Existing snapshots without optional charging settings load")
	expect(rv.energy.charging_enabled and not rv.energy.charging and rv.energy.fuel_reserve == 5.0 and rv.energy.recharge_below == 0.8, "Missing charging settings restore explicit defaults")
