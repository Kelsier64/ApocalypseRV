extends SceneTree
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)
func obstacle(world: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	world.add_child(body)
	return body
func run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	obstacle(world, Vector3(0, -0.1, 0), Vector3(100, 0.2, 100))
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	shell.position.y = 0.95
	world.add_child(shell)
	var rv: Chassis = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(20, 0, 0)
	world.add_child(player)
	player.set_physics_process(false)
	for i in range(3): await physics_frame
	var hatch := rv.engine_bay.get_node("Hatch")
	check(hatch.interact(player).contains("打開中") and not rv.engine_bay.hatch_open, "Service hatch starts motion without granting engine access")
	check(VehicleSnapshot.capture(rv).is_empty(), "Moving hatch cannot be saved")
	for i in range(10): await physics_frame
	var block := obstacle(world, rv.engine_bay.to_global(hatch.CLOSED.lerp(hatch.OPEN, 0.75)), Vector3(0.25, 0.25, 0.25))
	for i in range(80): await physics_frame
	check(not hatch.moving and not hatch.stable() and not rv.engine_bay.hatch_open, "New obstacle stops hatch at an intermediate pose and keeps engine locked")
	check(VehicleSnapshot.capture(rv).is_empty(), "Blocked hatch also refuses saving")
	block.free()
	await physics_frame
	hatch.interact(player)
	for i in range(80): await physics_frame
	check(hatch.stable() and not hatch.opened, "Stopped hatch can reverse to closed")
	hatch.interact(player)
	for i in range(80): await physics_frame
	check(hatch.opened and rv.engine_bay.hatch_open, "Full opening grants engine service")
	hatch.interact(player)
	for i in range(80): await physics_frame
	var ramp: RearRamp = rv.rear_ramp
	rv.get_node("RearDoor").restore_angles([-deg_to_rad(100), deg_to_rad(100)])
	await physics_frame
	var started := ramp.interact(player)
	check(ramp.moving, "Ramp begins animation: " + started)
	for i in range(25): await physics_frame
	block = obstacle(world, ramp.to_global(Vector3(0, 1.0, 2.1)), Vector3(0.4, 0.5, 0.4))
	for i in range(200): await physics_frame
	check(not ramp.moving and ramp.progress > 0 and ramp.progress < 1 and rv.drive_blocked(), "Mid-animation obstacle leaves ramp safely stopped and driving locked")
	check(VehicleSnapshot.capture(rv).is_empty(), "Partly folded ramp refuses saving")
	block.free()
	await physics_frame
	ramp.interact(player)
	for i in range(200): await physics_frame
	check(ramp.stable() and ramp.progress == 0 and not rv.drive_blocked(), "Blocked ramp reverses and fully stows")
	# Independent light loads, supply loss, equipment availability, and old saves.
	rv.interior_requested = {"cabin": false, "work": false, "service": false}
	rv.current_power = 50
	rv.energy.step(rv, 0, 1)
	var baseline := rv.energy.load_rate
	rv.interior_requested.cabin = true
	rv.energy.step(rv, 0, 1)
	check(rv.interior_powered.cabin and is_equal_approx(rv.energy.load_rate - baseline, rv.cabin_light_draw * 2), "Two cabin strips incur exactly their centralized load")
	rv.interior_requested.work = true
	rv.interior_requested.service = true
	hatch.set_open(true)
	rv.energy.step(rv, 0, 1)
	check(rv.interior_powered.work and rv.interior_powered.service and is_equal_approx(rv.energy.load_rate - baseline, rv.cabin_light_draw * 2 + rv.work_light_draw + rv.service_light_draw), "Work and service light loads are included once")
	rv.get_node("CraftingStation").enabled = false
	rv.energy.step(rv, 0, 1)
	check(not rv.interior_powered.work and rv.interior_powered.cabin, "Disabled workstation stops its own illumination and load")
	rv.current_power = 0
	rv.energy.step(rv, 0, 1)
	check(not rv.interior_powered.values().has(true), "No hidden light supply when battery empties")
	rv.current_power = 50
	rv.energy.step(rv, 0, 1)
	check(rv.interior_powered.cabin and rv.interior_powered.service, "Restored supply obeys saved switch requests")
	rv.instrument_brightness = 0.2
	rv.vibration_strength = 0.0
	var saved := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(saved), "Lighting settings are valid optional v3 state")
	check(await VehicleSnapshot.apply(rv, saved), "Lighting settings round trip")
	check(rv.instrument_brightness == 0.2 and rv.vibration_strength == 0.0 and rv.interior_requested.service, "Switches, dimmer and vibration restored exactly")
	var bad := saved.duplicate(true)
	bad.comfort.brightness = NAN
	check(not VehicleSnapshot.validate(bad), "Invalid lighting settings rejected before restore")
	saved.erase("comfort")
	check(await VehicleSnapshot.apply(rv, saved), "Existing v3 saves without comfort settings still load")
	check(rv.interior_requested.cabin and not rv.interior_requested.work and rv.instrument_brightness == 0.65, "Legacy save defaults are explicit")
	# Playback follows real engine success/failure; vibration never moves physics.
	var sound := rv.get_node("Audio")
	var before := rv.transform
	rv.get_engine().health = 0
	var cue_count: int = sound.cue_counts.get("start", 0)
	check(not rv.set_engine_running(true), "Failed engine does not start")
	sound._process(0.1)
	check(not sound.engine_player.playing and sound.cue_counts.get("start", 0) == cue_count, "Failed start never plays success or loop")
	rv.get_engine().health = 450
	rv.set_engine_running(true)
	sound._process(0.1)
	check(sound.engine_player.playing, "Running engine has one persistent loop")
	rv.vibration_strength = 1
	sound._process(0.1)
	check(rv.transform == before, "Visual vibration leaves body transform unchanged")
	rv.vibration_strength = 0
	sound._process(0.1)
	check(rv.engine_bay.get_node("EngineVisual").position == sound.engine_rest, "Zero vibration restores exact visual pose")
	rv.current_fuel = 0
	rv.energy.step(rv, 0, 1)
	sound._process(0.1)
	check(not sound.engine_player.playing, "Fuel exhaustion stops engine audio")
	var station: CraftingStation = rv.get_node("CraftingStation")
	station.enabled = true
	rv.current_power = 50
	block = obstacle(world, station.spawn_marker.global_position + Vector3.UP * 0.5, Vector3(1.2, 1.2, 1.2))
	await physics_frame
	check(not station.spawn_item("res://props/gas_can.tscn") and rv.current_power == 50, "Occupied output still rejects production without consuming power")
	block.free()
	await physics_frame
	check(station.spawn_item("res://props/gas_can.tscn"), "Tall can clears the production RV's preinstalled tablet")
	world.queue_free()
	await process_frame
	for failure in failures: push_error("FAIL: " + failure)
	if failures.is_empty(): print("PASS: safe machinery motion, power/accounting, comfort snapshots and engine feedback")
	quit(0 if failures.is_empty() else 1)
