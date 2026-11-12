extends SceneTree
const InstrumentCluster := preload("res://rv/instrument_cluster.gd")
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

func check_engine_rpm(rv: Chassis) -> void:
	var fuel_before := rv.current_fuel
	var power_before := rv.current_power
	var previous_gear := rv.gear
	var previous_handbrake := rv.handbrake
	check(rv.engine_rpm() == 0.0, "Stopped engine reads zero RPM")
	check(rv.set_engine_running(true) and rv.engine_rpm() == Chassis.ENGINE_IDLE_RPM, "Running engine idles with the pedal released")
	rv.allow_test_controls = true
	rv.set_gear(0)
	rv.set_handbrake(false)
	rv.control_override = {"throttle": 1.0}
	rv._physics_process(rv.throttle_apply_seconds)
	check(is_equal_approx(rv.engine_rpm(), Chassis.ENGINE_MAX_RPM) and rv.engine_force == 0.0, "Neutral revs without driving the wheels")
	rv.control_override.clear()
	rv._physics_process(rv.throttle_release_seconds)
	rv.set_handbrake(true)
	rv.set_gear(1)
	rv.control_override = {"throttle": 1.0}
	rv._physics_process(rv.throttle_apply_seconds)
	check(is_equal_approx(rv.engine_rpm(), Chassis.ENGINE_MAX_RPM) and rv.engine_force == 0.0, "Parking brake allows free revs in gear without driving the wheels")
	rv.control_override.clear()
	rv._physics_process(rv.throttle_release_seconds)
	rv.set_handbrake(false)
	rv.linear_velocity = -rv.global_basis.z * 5.0
	var first_gear_rpm := rv.engine_rpm()
	rv.set_gear(2)
	check(first_gear_rpm > rv.engine_rpm() and rv.engine_rpm() > Chassis.ENGINE_IDLE_RPM, "Upshifting at the same road speed lowers RPM")
	rv.linear_velocity = Vector3.ZERO
	check(rv.engine_rpm() == Chassis.ENGINE_IDLE_RPM, "Running engine idles at rest in gear")
	rv.set_gear(-1)
	rv.linear_velocity = rv.global_basis.z * 5.0
	check(is_equal_approx(rv.engine_rpm(), first_gear_rpm), "Reverse raises RPM as the RV backs up")
	rv.current_fuel = 0.0
	check(rv.engine_rpm() == 0.0, "Empty tank reads zero RPM")
	rv.current_fuel = fuel_before
	var engine := rv.get_engine()
	var health_before := engine.health
	engine.health = 0.0
	check(rv.engine_rpm() == 0.0, "Broken engine reads zero RPM")
	engine.health = health_before
	rv.set_engine_running(false)
	check(rv.engine_rpm() == 0.0, "Moving RV reads zero RPM after engine shutdown")
	rv.linear_velocity = Vector3.ZERO
	rv.set_gear(previous_gear)
	rv.set_handbrake(previous_handbrake)
	rv.allow_test_controls = false
	rv.current_fuel = fuel_before
	rv.current_power = power_before

## Index of the one gear position that outshines the others, or -1 when none does.
func lit_gear(cluster: InstrumentCluster) -> int:
	var energies: Array[float] = []
	for material in cluster.gear_lamps:
		energies.append(material.emission_energy_multiplier)
	var brightest: float = energies.max()
	if brightest <= 0.0 or energies.count(brightest) != 1:
		return -1
	return energies.find(brightest)

## Long enough for the damped needles to reach their targets.
func settle_instruments(cluster: InstrumentCluster, rv: Chassis) -> void:
	cluster.update_instruments(rv, 10.0)

func check_unpowered_instruments(cluster: InstrumentCluster, reason: String) -> void:
	check(lit_gear(cluster) == -1, reason + " extinguishes the gear quadrant")
	check(is_equal_approx(cluster.battery_needle.rotation.z, InstrumentCluster.level_rotation(0.0)), reason + " drops the charge gauge to empty")
	check(cluster.charge_material.emission_energy_multiplier == 0.0, reason + " extinguishes the charging indicator")
	for id in VehicleStatus.IDS:
		check(cluster.warning_lamps[id].emission_energy_multiplier == 0.0, reason + " extinguishes the " + id + " lamp")

func check_instrument_cluster(rv: Chassis, world: Node3D) -> void:
	var cluster := rv.get_node("DriverSeat/CockpitVisual/InstrumentCluster") as InstrumentCluster
	var power_before := rv.current_power
	var fuel_before := rv.current_fuel
	var gear_before := rv.gear
	var charging_before := rv.energy.charging
	var generation_before := rv.energy.generated_rate
	var socket := rv.get_battery_socket()
	var battery := socket.installed_battery
	var low_charge := 0.12
	rv.current_power = rv.max_power * low_charge
	rv.current_fuel = 0.0
	rv.energy.charging = true
	rv.energy.generated_rate = 0.0
	settle_instruments(cluster, rv)
	check(is_equal_approx(cluster.battery_needle.rotation.z, InstrumentCluster.level_rotation(low_charge)), "Charge gauge needle follows the battery level")
	check(is_equal_approx(cluster.fuel_needle.rotation.z, InstrumentCluster.level_rotation(0.0)), "Empty fuel puts the needle at E")
	check(cluster.charge_material.emission_energy_multiplier == 0.0, "Charging flag alone does not light the charging indicator")
	check(is_equal_approx(cluster.rpm_needle.rotation.z, InstrumentCluster.dial_rotation(rv.engine_rpm() / InstrumentCluster.RPM_FULL_SCALE)), "Tachometer needle follows engine RPM")
	for row in VehicleStatus.read(rv):
		var lamp: StandardMaterial3D = cluster.warning_lamps[row.id]
		check((lamp.emission_energy_multiplier > 0.0) == (row.level > 0), "Cluster warning follows vehicle status for " + row.id)
		if row.level > 0:
			check(lamp.emission.is_equal_approx(InstrumentCluster.LAMP_RED), "Cluster warning lights red for " + row.id)
	rv.energy.charging = false
	rv.energy.generated_rate = 1.0
	rv.current_power = rv.max_power
	rv.current_fuel = rv.max_fuel
	for selected_gear in [-1, 0, 1, 4]:
		rv.set_gear(selected_gear)
		settle_instruments(cluster, rv)
		var glyph := "R" if selected_gear < 0 else ("N" if selected_gear == 0 else str(selected_gear))
		check(lit_gear(cluster) == InstrumentCluster.GEAR_GLYPHS.find(glyph), "Gear quadrant lights the position for %d" % selected_gear)
	check(is_equal_approx(cluster.battery_needle.rotation.z, InstrumentCluster.level_rotation(1.0)), "Full charge puts the charge needle at F")
	check(is_equal_approx(cluster.fuel_needle.rotation.z, InstrumentCluster.level_rotation(1.0)), "Full fuel puts the needle at F")
	check(cluster.charge_material.emission_energy_multiplier > 0.0, "Positive generation lights the charging indicator")
	var second_shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	second_shell.position.x = -20.0
	world.add_child(second_shell)
	var second_rv: Chassis = second_shell.get_node("Chassis")
	var second_cluster := second_rv.get_node("DriverSeat/CockpitVisual/InstrumentCluster") as InstrumentCluster
	second_rv.set_gear(0)
	second_rv.current_power = 0.0
	settle_instruments(second_cluster, second_rv)
	check(lit_gear(second_cluster) == -1 and lit_gear(cluster) == InstrumentCluster.GEAR_GLYPHS.find("4"), "Two RVs keep independent gear quadrant materials")
	check(not is_equal_approx(second_cluster.battery_needle.rotation.z, cluster.battery_needle.rotation.z), "Two RVs keep independent charge gauges")
	second_shell.free()
	rv.current_power = 0.0
	settle_instruments(cluster, rv)
	check_unpowered_instruments(cluster, "Empty battery")
	rv.current_power = rv.max_power
	socket.installed_battery = null
	settle_instruments(cluster, rv)
	check_unpowered_instruments(cluster, "Missing battery")
	socket.installed_battery = battery
	rv.current_power = power_before
	rv.current_fuel = fuel_before
	rv.set_gear(gear_before)
	rv.energy.charging = charging_before
	rv.energy.generated_rate = generation_before
	settle_instruments(cluster, rv)

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
	check(not rv.energy.charging_status().contains("Fuel reserve"), "Charging status honors unlimited fuel below reserve")
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
	check_engine_rpm(rv)
	check_instrument_cluster(rv, world)
	check(not rv.has_node("Generator"), "Charging needs no portable generator")
	for name in ["CraftingStation", "Scrapper", "TabletScreen", "ItemBox", "FuelPort", "DriverSeat"]:
		check(rv.get_node(name).can_operate(), "Default installed service: " + name)
	check(rv.stored_items.size() == 2 and rv.stored_items[0].scene_path.ends_with("engine_repair_kit.tscn"), "Starter recovery kits")
	check(rv.get_node("TabletScreen").mount_support == rv.get_node("CraftingStation"), "Tabletop tablet depends on workstation")
	var bay := rv.engine_bay
	check(rv.get_engine().health == 450 and not bay.hatch_open, "Standard engine and closed hatch at start")
	var incoming := add_engine(player, "upgraded", 257)
	var old_id := rv.get_engine().id
	check(rv.exchange_engine(player).contains("service hatch") and rv.get_engine().id == old_id, "Closed hatch rejects exchange")
	bay.get_node("Hatch").set_open(true)
	rv.set_engine_running(true)
	check(rv.exchange_engine(player).contains("Stop the engine"), "Running exchange rejected")
	rv.set_engine_running(false)
	rv.linear_velocity = Vector3.RIGHT
	check(rv.exchange_engine(player).contains("Stop the vehicle"), "Moving exchange rejected")
	rv.linear_velocity = Vector3.ZERO
	rv.handbrake = false
	check(rv.exchange_engine(player).contains("parking brake"), "Unbraked exchange rejected")
	rv.handbrake = true
	for i in range(5): player.add_item(ItemNames.WHEEL, false, "res://props/wheel.tscn")
	check(rv.exchange_engine(player).contains("Installed") and rv.get_engine().id == incoming.id and rv.get_engine().health == 257, "Full inventory exchange is atomic")
	check(player.inventory.active_item().state.engine.id == old_id, "Old engine remains in same slot")
	check(not player.inventory.select_slot(1), "Large engine prevents slot switching")
	check(rv.remove_engine(player).contains("inventory"), "Removal respects large item and capacity rules")
	player.inventory.items.clear()
	player.refresh_inventory()
	check(rv.remove_engine(player).contains("Engine removed") and rv.get_engine() == null, "Engine becomes one carried item")
	rv.take_damage(999)
	check(not rv.set_engine_running(true) and level(rv, "engine") == 3, "Empty bay cannot start")
	check(rv.store_player_item(player, 0), "Engine can enter shared warehouse")
	check(rv.take_stored_item(player, 2), "Same engine can be taken back from warehouse")
	check(rv.exchange_engine(player).contains("Installed") and rv.get_engine().health == 257, "Warehouse roundtrip keeps engine condition")
	rv.take_damage(999)
	check(rv.get_engine().health == 0 and not rv.energy.engine_running, "Engine destruction stops only drivetrain")
	var seat: Item = rv.get_node("DriverSeat")
	seat.interact_hold(player)
	check(seat.current_driver == player, "Broken engine still permits driving controls and seat access")
	player.survival.san = 0.0
	var effects: PlayerSanEffects = player.san_effects
	effects._rng.seed = 7
	player._advance_san_effects(0.0)
	effects._misdirection_duration = 2.0
	effects._misdirection_remaining = 1.5
	effects._misdirection_strength = 1.0
	effects._sway_period = 1.0
	effects._sway_phase = -PI / 2.0
	effects._side = 1.0
	Input.action_press("move_left")
	Input.action_press("move_back")
	rv._physics_process(1.0 / 60.0)
	check(rv.steering < 0.0 and rv.brake_input > 0.0, "The seated driver's hallucination reverses steering and preserves the brake command")
	Input.action_release("move_left")
	Input.action_release("move_back")
	rv.steering = 0.0
	rv._physics_process(1.0 / 60.0)
	check(rv.steering > 0.0, "A strong steering sway can pull the RV sideways while the driver leaves steering idle")
	var previous_gear := rv.gear
	var previous_handbrake := rv.handbrake
	rv.gear = 1
	rv.handbrake = false
	effects._misdirection_remaining = 0.0
	effects._misdirection_wait = 1.0
	effects._delay_wait = 0.0
	player._advance_san_effects(.01)
	effects._delay_wait = 1.0
	Input.action_press("move_forward")
	rv._physics_process(1.0 / 60.0)
	check(is_zero_approx(rv.throttle_input), "A seated driver's throttle increase waits during a delay episode")
	player._advance_san_effects(effects._delay_seconds + .01)
	rv._physics_process(1.0 / 60.0)
	check(rv.throttle_input > 0.0, "A held throttle reaches the RV after the delay")
	Input.action_press("move_back")
	rv._physics_process(.2)
	check(is_zero_approx(rv.throttle_input) and rv.brake_input > 0.0, "Service braking cuts delayed throttle while W remains held")
	Input.action_release("move_back")
	rv._physics_process(1.0 / 60.0)
	check(is_zero_approx(rv.throttle_input), "Releasing the brake does not resurrect delayed throttle")
	Input.action_release("move_forward")
	rv.gear = previous_gear
	rv.handbrake = previous_handbrake
	player.recover_san(20.0)
	rv.steering = 0.0
	rv.brake_input = 0.0
	player.survival.reset()
	seat.exit_seat()
	player.set_physics_process(false)
	check(rv.get_node("ItemBox").can_operate() and rv.current_power > 0, "Broken engine preserves warehouse and battery")
	var kit := {"id": "test-kit", "condition": 100.0}
	player.add_item("Engine Repair Kit", false, "res://props/engine_repair_kit.tscn", kit)
	var repair := RepairOperation.new()
	repair.step(player, bay, true, 1.5)
	repair.step(player, null, false, 0.1)
	check(rv.get_engine().health == 0 and player.inventory.items.size() == 1, "Interrupted kit repair consumes nothing")
	repair.step(player, bay, true, 3.0)
	check(rv.get_engine().health == 150 and player.inventory.items.is_empty(), "Kit revives broken engine once")
	rv.get_engine().health = rv.get_engine().definition().max_health
	player.add_item("Engine Repair Kit", false, "res://props/engine_repair_kit.tscn")
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
	var engine := rv.get_engine()
	var previous_health := engine.health
	rv.throttle_input = 1.0
	rv.linear_velocity = -rv.global_basis.z * 4.0
	var drive_force := {}
	for percent in [100, 60, 59, 30, 10]:
		engine.health = engine.definition().max_health * percent / 100.0
		rv._physics_process(0.016)
		drive_force[percent] = absf(rv.engine_force)
	check(drive_force[100] > 0.0 and is_equal_approx(drive_force[60], drive_force[100]), "60% engine health retains normal drive at speed")
	check(drive_force[10] > 0.0 and drive_force[10] < drive_force[30] and drive_force[30] < drive_force[59] and drive_force[59] < drive_force[60], "Drive at speed progressively falls below 60% health")
	engine.health = engine.definition().max_health * 0.6
	rv._physics_process(0.016)
	check(is_equal_approx(absf(rv.engine_force), drive_force[100]), "Restored health recovers normal drive immediately")
	engine.health = previous_health
	rv.linear_velocity = Vector3.ZERO
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
	var stored_kit: Dictionary = saved.items[0].duplicate(true)
	saved.items[0].name = "引擎維修包" # Legacy checkpoint fixture.
	check(VehicleSnapshot.validate(saved), "Current vehicle snapshot valid")
	check(VehicleSnapshot.apply(rv, saved) and rv.get_engine().id == incoming.id and rv.get_engine().health == 150, "Engine save restores identity and condition")
	check(rv.stored_items[0] == stored_kit and rv.stored_items[0].name == "Engine Repair Kit", "Legacy warehouse name becomes English without changing item state")
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
