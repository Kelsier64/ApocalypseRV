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
	player.position = Vector3(20, 2, 0)
	player.set_physics_process(false)
	await physics_frame
	await physics_frame
	for name in ["Generator", "CraftingStation", "Scrapper", "TabletScreen", "ItemBox", "FuelPort", "DriverSeat"]:
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
	var seat: Equipment = rv.get_node("DriverSeat")
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
	rv.get_node("Generator").set_enabled(false)
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
	rv.get_node("Generator").set_enabled(true)
	rv.headlights_requested = true
	rv.current_power = 100
	rv.step_energy_system(0, 0, 0, 1)
	check(level(rv, "headlight") == 1 and rv.current_power < 99.8, "Headlights and brake lamps consume battery")
	rv.current_power = 0
	rv.step_energy_system(0, 0, 0, 1)
	check(not rv.lamps_powered and level(rv, "battery") == 3, "No power extinguishes exterior lamps")
	rv.current_power = 100
	rv.set_engine_running(true)
	rv.get_node("Generator").charging = false
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
	var saved := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(saved), "V3 engine snapshot valid")
	check(VehicleSnapshot.apply(rv, saved) and rv.get_engine().id == incoming.id and rv.get_engine().health == 150, "Engine save restores identity and condition")
	var bad := saved.duplicate(true)
	bad.engine_item.health = INF
	check(not VehicleSnapshot.validate(bad), "Nonfinite engine durability rejected")
	var duplicate := saved.duplicate(true)
	duplicate.items.append(rv.get_engine().item())
	check(not VehicleSnapshot.validate(duplicate), "Installed and stored engines cannot share an ID")
	var old := saved.duplicate(true)
	old.version = 2
	old.health = 0.0
	old.erase("engine_item")
	var upgraded := VehicleSnapshot.upgrade(old)
	check(VehicleSnapshot.validate(upgraded) and upgraded.engine_item.health == 0, "Legacy destroyed chassis becomes broken standard engine")
	check(VehicleSnapshot.upgrade(upgraded) == upgraded, "V3 migration is idempotent")
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
	var product: Prop
	for node in WorldEntities.get_container(world).get_children():
		if node is Prop and node.scene_file_path == "res://props/engine_upgraded.tscn": product = node
	check(product != null and EngineState.valid(product.capture_item_state().engine, false), "Crafted engine has valid durable state")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: default assembly, engine ownership, repair, upgrades, lights, migration and crafting")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
