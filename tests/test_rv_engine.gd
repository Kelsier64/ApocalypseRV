extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)
func add_engine(player: Node, model: String, hp: float) -> EngineState:
	var engine := EngineState.new({"model": model, "health": hp})
	var item := engine.item()
	check(player.add_item(item.name, true, item.scene_path, item.state), "Engine enters inventory")
	return engine
func level(rv: Node, id: String) -> int:
	for row in VehicleStatus.read(rv):
		if row.id == id: return row.level
	return -1

func check_session_energy(rv: Chassis) -> void:
	var fuel_before := rv.current_fuel
	var power_before := rv.current_power
	var service_before: bool = rv.interior_requested.service
	rv.interior_requested.service = true
	var engine := rv.get_engine()
	var socket := rv.get_battery_socket()
	var cell := socket.installed_battery
	var tablet: Item = rv.get_node("TabletScreen")
	rv.current_fuel = 0.0
	rv.current_power = 0.0
	rv.unlimited_fuel = true
	check(rv.set_engine_running(true) and level(rv, "fuel") == 0, "Unlimited fuel starts an empty tank and clears fuel warning")
	rv.step_energy_system(1.0, 0.0, 0.0, 1.0)
	check(rv.energy.engine_running and rv.current_fuel == 0.0 and rv.current_power > 0.0 and rv.energy.generated_rate > 0.0, "Unlimited fuel covers idle, drive and charging below reserve without filling fuel")
	check(not rv.energy.charging_status().contains("保留油量"), "Charging status honors unlimited fuel below reserve")
	rv.set_engine_running(false)
	rv.engine_bay.installed_engine = null
	check(not rv.set_engine_running(true) and level(rv, "engine") == 3, "Unlimited fuel still requires an installed engine")
	rv.engine_bay.installed_engine = engine
	var health_before := engine.health
	engine.health = 0.0
	check(not rv.set_engine_running(true) and level(rv, "engine") == 3, "Unlimited fuel still rejects a broken engine")
	engine.health = health_before
	rv.set_engine_running(true)
	rv.unlimited_fuel = false
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	check(not rv.energy.engine_running and not rv.set_engine_running(true) and level(rv, "fuel") == 3, "Disabling unlimited fuel restores empty-tank shutdown and startup rejection")
	rv.current_fuel = 25.0
	rv.energy.charging_enabled = false
	rv.set_engine_running(true)
	rv.step_energy_system(1.0, 0.0, 0.0, 1.0)
	check(rv.current_fuel < 25.0, "Disabling unlimited fuel restores finite fuel burn")
	rv.set_engine_running(false)
	rv.unlimited_power = true
	rv.current_power = 0.0
	check(rv.has_usable_power(20.0) and rv.energy.consume_power(20.0) and rv.consume_power(30.0) and rv.current_power == 0.0, "Unlimited power covers both direct and chassis draws without filling charge")
	check(tablet.consume_rv_power(tablet.power_cost_per_open) and rv.current_power == 0.0, "Unlimited power covers the terminal opening fee at zero charge")
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	check(rv.lamps_powered and rv.interior_powered.cabin and rv.interior_powered.service and rv.current_power == 0.0 and level(rv, "battery") == 0, "Unlimited power covers standby and exterior, cabin and service lighting at zero charge")
	tablet.enabled = false
	check(not tablet.consume_rv_power(1.0), "Unlimited power cannot run disabled equipment")
	tablet.enabled = true
	var tablet_health := tablet.current_health
	tablet.current_health = 0.0
	check(not tablet.consume_rv_power(1.0), "Unlimited power cannot run broken equipment")
	tablet.current_health = tablet_health
	var front: Item = rv.get_node("CabinLightFront")
	var rear: Item = rv.get_node("CabinLightRear")
	front.enabled = false
	rear.enabled = false
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	check(not rv.interior_powered.cabin, "Unlimited power does not enable disabled cabin fixtures")
	front.enabled = true
	rear.enabled = true
	socket.installed_battery = null
	check(not rv.has_usable_power() and not rv.energy.consume_power(1.0) and level(rv, "battery") == 3, "Unlimited power still requires an installed battery")
	socket.installed_battery = cell
	socket.enabled = false
	check(not rv.has_usable_power() and not rv.consume_power(1.0) and level(rv, "battery") == 3, "Unlimited power still requires an enabled battery socket")
	socket.enabled = true
	var socket_health := socket.current_health
	socket.current_health = 0.0
	check(not rv.has_usable_power() and not rv.consume_power(1.0) and level(rv, "battery") == 3, "Unlimited power still rejects a broken battery socket")
	socket.current_health = socket_health
	cell.condition = 0.0
	check(not rv.has_usable_power() and not rv.consume_power(1.0) and level(rv, "battery") == 3, "Unlimited power still rejects a broken battery")
	cell.condition = 100.0
	rv.unlimited_fuel = true
	for amount in [-1.0, NAN, INF]:
		check(not rv.consume_fuel(amount) and not rv.consume_power(amount) and not rv.energy.consume_power(amount) and not rv.has_usable_power(amount), "Unlimited policies reject invalid resource costs: " + str(amount))
	check(rv.current_power == 0.0 and is_finite(rv.current_fuel), "Rejected costs preserve finite stored resources")
	rv.unlimited_fuel = false
	rv.unlimited_power = false
	check(not rv.has_usable_power() and not tablet.consume_rv_power(1.0), "Disabling unlimited power restores empty-battery rejection")
	rv.step_energy_system(0.0, 0.0, 0.0, 1.0)
	check(not rv.lamps_powered and not rv.interior_powered.cabin and not rv.interior_powered.service and level(rv, "battery") == 3, "Disabling unlimited power extinguishes empty-battery lighting")
	rv.current_power = 12.0
	check(rv.consume_power(3.0) and rv.current_power == 9.0, "Disabling unlimited power restores finite battery consumption")
	rv.current_fuel = fuel_before
	rv.current_power = power_before
	rv.interior_requested.service = service_before
	rv.energy.charging_enabled = true

func _run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	for model in ["standard", "upgraded"]:
		var loose: Item = load("res://props/engine_" + model + ".tscn").instantiate()
		var identity := loose.persistent_id
		loose.condition = 25.0
		world.add_child(loose)
		var maximum: float = loose.engine.definition().max_health
		check(loose.persistent_id == identity and loose.engine.id == identity, "Fresh engine preserves its Item identity through initialization")
		check(is_equal_approx(loose.engine.health, maximum * 0.25) and is_equal_approx(loose.current_health, loose.engine.health), "Pre-ready condition becomes the single durable engine health")
		loose.take_damage(10.0)
		check(is_equal_approx(loose.engine.health, maximum * 0.25 - 10.0), "Generic Item damage updates engine health")
		loose.repair_health(7.0)
		check(is_equal_approx(loose.engine.health, maximum * 0.25 - 3.0), "Generic Item repair updates engine health")
		loose.engine.health = 21.0
		var record := loose.capture_item_state()
		check(record.id == record.engine.id and is_equal_approx(record.condition, 2100.0 / maximum), "Capture derives condition and identity from EngineState")
		check(ItemState.valid(loose.scene_file_path, record), "Engine Item snapshot satisfies scene and identity validation")
		record.condition = 100.0
		var restored: Item = load(loose.scene_file_path).instantiate()
		restored.restore_item_state(record)
		world.add_child(restored)
		check(restored.engine.health == 21.0 and restored.current_health == 21.0 and restored.persistent_id == identity, "Restore keeps durable engine health authoritative over derived condition")
		loose.free()
		restored.free()
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	check(not rv.unlimited_fuel and not rv.unlimited_power and not rv.unlimited_materials, "Fresh production chassis keeps finite default resource policy")
	rv.freeze = true
	rv.set_physics_process(false)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.position = Vector3(20, 2, 0)
	player.set_physics_process(false)
	await physics_frame
	await physics_frame
	check(not rv.has_node("Generator"), "Charging needs no portable generator")
	for name in ["CraftingStation", "Scrapper", "TabletScreen", "ItemBox", "FuelPort", "DriverSeat"]:
		check(rv.get_node(name).can_operate(), "Default installed service: " + name)
	check(rv.stored_items.size() == 2 and rv.stored_items[0].scene_path.ends_with("engine_repair_kit.tscn"), "Starter recovery kits")
	check(rv.get_node("TabletScreen").mount_support == rv.get_node("CraftingStation"), "Tabletop tablet depends on workstation")
	var bay := rv.engine_bay
	check(rv.get_engine().health == 450 and not bay.hatch_open, "Standard engine and closed hatch at start")
	var incoming := add_engine(player, "upgraded", 257)
	var old_id := rv.get_engine().id
	check(rv.exchange_engine(player).contains("維修蓋") and rv.get_engine().id == old_id, "Closed hatch rejects exchange")
	bay.get_node("Hatch").set_open(true)
	rv.set_engine_running(true)
	check(rv.exchange_engine(player).contains("熄火"), "Running exchange rejected")
	rv.set_engine_running(false)
	rv.linear_velocity = Vector3.RIGHT
	check(rv.exchange_engine(player).contains("停穩"), "Moving exchange rejected")
	rv.linear_velocity = Vector3.ZERO
	rv.handbrake = false
	check(rv.exchange_engine(player).contains("手煞車"), "Unbraked exchange rejected")
	rv.handbrake = true
	for i in range(5): player.add_item(ItemNames.WHEEL, false, "res://props/wheel.tscn")
	check(rv.exchange_engine(player).contains("已裝入") and rv.get_engine().id == incoming.id and rv.get_engine().health == 257, "Full inventory exchange is atomic")
	check(player.inventory.active_item().state.engine.id == old_id, "Old engine remains in same slot")
	check(not player.inventory.select_slot(1), "Large engine prevents slot switching")
	check(rv.remove_engine(player).contains("背包"), "Removal respects large item and capacity rules")
	player.inventory.items.clear()
	player.refresh_inventory()
	check(rv.remove_engine(player).contains("已取出") and rv.get_engine() == null, "Engine becomes one carried item")
	rv.take_damage(999)
	check(not rv.set_engine_running(true) and level(rv, "engine") == 3, "Empty bay cannot start")
	check(rv.store_player_item(player, 0), "Engine can enter shared warehouse")
	check(rv.take_stored_item(player, 2), "Same engine can be taken back from warehouse")
	check(rv.exchange_engine(player).contains("已裝入") and rv.get_engine().health == 257, "Warehouse roundtrip keeps engine condition")
	rv.take_damage(999)
	check(rv.get_engine().health == 0 and not rv.energy.engine_running, "Engine destruction stops only drivetrain")
	var seat: Item = rv.get_node("DriverSeat")
	seat.interact_hold(player)
	check(seat.current_driver == player, "Broken engine still permits driving controls and seat access")
	seat.exit_seat()
	player.set_physics_process(false)
	check(rv.get_node("ItemBox").can_operate() and rv.current_power > 0, "Broken engine preserves warehouse and battery")
	var kit := {"id": "test-kit", "condition": 100.0}
	player.add_item("引擎維修包", false, "res://props/engine_repair_kit.tscn", kit)
	var repair := RepairOperation.new()
	repair.step(player, bay, true, 1.5)
	repair.step(player, null, false, 0.1)
	check(rv.get_engine().health == 0 and player.inventory.items.size() == 1, "Interrupted kit repair consumes nothing")
	repair.step(player, bay, true, 3.0)
	check(rv.get_engine().health == 150 and player.inventory.items.is_empty(), "Kit revives broken engine once")
	rv.get_engine().health = rv.get_engine().definition().max_health
	player.add_item("引擎維修包", false, "res://props/engine_repair_kit.tscn")
	repair.step(player, bay, true, 3.0)
	check(player.inventory.items.size() == 1, "Full engine never consumes a repair kit")
	rv.get_engine().health = 150
	bay.hatch_open = false
	repair.step(player, bay, true, 3.0)
	check(rv.get_engine().health == 150 and player.inventory.items.size() == 1, "Closed hatch cancels repair without consumption")
	bay.hatch_open = true
	player.inventory.items.clear()
	player.refresh_inventory()
	check(rv.set_engine_running(true), "Repaired engine restarts")
	rv.handbrake = false
	rv.energy.charging_enabled = false
	rv.current_fuel = 100
	rv.step_energy_system(1.0, 0, 0, 1.0)
	var upgraded_burn := 100.0 - rv.current_fuel
	rv.get_engine().model_id = "standard"
	rv.current_fuel = 100
	rv.step_energy_system(1.0, 0, 0, 1.0)
	check(is_equal_approx(upgraded_burn / (100.0 - rv.current_fuel), 1.15), "Upgraded engine fuel cost multiplier")
	rv.allow_test_controls = true
	rv.control_override = {"throttle": 1.0}
	rv.throttle_input = 0.0
	rv._physics_process(0.016)
	var standard_force := rv.engine_force
	rv.get_engine().model_id = "upgraded"
	# Compare the same pedal phase; consecutive ramp frames have different input.
	rv.throttle_input = 0.0
	rv._physics_process(0.016)
	check(is_equal_approx(rv.engine_force / standard_force, 1.25), "Upgraded engine drive force multiplier")
	rv.control_override.clear()
	rv.set_engine_running(false)
	rv.handbrake = true
	rv.energy.charging_enabled = true
	rv.headlights_requested = true
	rv.current_power = 100
	rv.step_energy_system(0, 0, 0, 1)
	check(level(rv, "headlight") == 1 and rv.current_power < 99.8, "Headlights and brake lamps consume battery")
	rv.current_power = 0
	rv.step_energy_system(0, 0, 0, 1)
	check(not rv.lamps_powered and level(rv, "battery") == 3, "No power extinguishes exterior lamps")
	rv.current_power = 100
	rv.set_engine_running(true)
	rv.energy.charging = false
	rv.step_energy_system(0, 0, 0, 0.1)
	check(level(rv, "battery") == 0, "Charge threshold pause does not show fault")
	rv.current_fuel = 4
	rv.step_energy_system(0, 0, 0, 0.1)
	check(level(rv, "battery") == 0, "Fuel reserve pause does not show charging fault")
	rv.set_engine_running(false)
	rv.current_fuel = 14
	check(level(rv, "fuel") == 2, "Low fuel warning")
	rv.current_fuel = 0
	check(level(rv, "fuel") == 3, "Empty fuel warning")
	rv.current_fuel = 50
	check(level(rv, "door") == 3, "Open service hatch warns like a door")
	bay.get_node("Hatch").set_open(false)
	check(level(rv, "door") == 0, "Closed body clears door warning")
	bay.get_node("Hatch").set_open(true)
	check(level(rv, "brake") == 3, "Parking brake uses red P")
	rv.wheel_health[0] = 20
	check(level(rv, "tire") == 2, "Worn tire warning")
	rv.wheel_health[0] = 0
	check(level(rv, "tire") == 3, "Failed tire warning")
	rv.wheel_health[0] = 100
	rv.rear_ramp.deployed = true
	check(level(rv, "ramp") == 2, "Deployed ramp has warning")
	rv.rear_ramp.deployed = false
	rv.current_power = 100
	rv.set_gear(-1)
	rv.step_energy_system(0, 0, 0, 0.1)
	var lights := rv.get_node("VehicleLights")
	lights._process(0.0)
	check(lights.lamps["reverse1.0"].light.visible, "Reverse gear powers real reverse spotlight")
	rv.current_power = 0
	rv.step_energy_system(0, 0, 0, 0.1)
	lights._process(0.0)
	for lamp in lights.lamps.values(): check(not lamp.light.visible, "All exterior lamps extinguish without power")
	rv.current_power = 100
	check_session_energy(rv)
	var saved := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(saved), "Current vehicle snapshot valid")
	check(VehicleSnapshot.apply(rv, saved) and rv.get_engine().id == incoming.id and rv.get_engine().health == 150, "Engine save restores identity and condition")
	var bad := saved.duplicate(true)
	bad.engine_item.health = INF
	check(not VehicleSnapshot.validate(bad), "Nonfinite engine durability rejected")
	var duplicate := saved.duplicate(true)
	duplicate.items.append(rv.get_engine().item())
	check(not VehicleSnapshot.validate(duplicate), "Installed and stored engines cannot share an ID")
	rv.engine_bay.installed_engine = null
	var empty := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.apply(rv, empty) and rv.get_engine() == null, "Empty slot stays empty after loading")
	# Actual production station creates a large physical engine with preserved identity.
	rv.current_power = 100
	rv.inventory = {"Metal Parts": 50, "Electronic Scrap": 20}
	var station: CraftingStation
	for device in rv.get_equipment():
		if device is CraftingStation: station = device
	check(station.request_craft("engine_upgraded"), "Engine recipe queues")
	station.step_work(30.0)
	check(station.jobs.is_empty(), "Large engine output has actual collider clearance: " + station.last_error)
	var product: Item
	for node in WorldEntities.get_container(world).get_children():
		if node is Item and node.scene_file_path == "res://props/engine_upgraded.tscn": product = node
	check(product != null and EngineState.valid(product.capture_item_state().engine, false), "Crafted engine has valid durable state")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: default assembly, engine ownership, repair, upgrades, lights and crafting")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
