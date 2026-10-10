extends SceneTree
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)
func ticks(original_count: int) -> int:
	return ceili(original_count * Engine.physics_ticks_per_second / 60.0)
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
func hatch_geometry(hatch: Node3D, hinge: Vector3) -> bool:
	var cover: MeshInstance3D = hatch.get_node("Cover")
	var collision: CollisionShape3D = hatch.get_node("Collision")
	var mesh: BoxMesh = cover.mesh
	var size := mesh.size
	var top_rear := cover.to_global(Vector3(0, size.y * 0.5, size.z * 0.5))
	return top_rear.distance_to(hinge) < 0.0001 \
		and cover.global_basis.is_equal_approx(collision.global_basis) \
		and collision.global_position.distance_to(hatch.to_global(Vector3(0, 0, -0.03))) < 0.0001 \
		and is_equal_approx(cover.global_basis.y.length(), 1.0)
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
	var closed_pose: Transform3D = hatch.transform
	var hinge: Vector3 = hatch.to_global(Vector3(0, 0.33, 0.05))
	# A lower-edge obstacle lies on the rotation arc, clear of either endpoint.
	var arc_basis := Basis(Vector3.RIGHT, deg_to_rad(52.5))
	var arc_point := rv.engine_bay.to_global(Vector3(0, 0.28, -0.53) + arc_basis * Vector3(0, -0.61, -0.07))
	var block := obstacle(world, arc_point, Vector3.ONE * 0.08)
	await physics_frame
	check(hatch.blocker(0.0, 0.0).is_empty() and hatch.blocker(1.0, 1.0).is_empty(), "Arc obstacle clears both stable hatch poses")
	var hatch_result: String = hatch.interact(player)
	check(hatch_result.contains("被擋住") and hatch.stable() and hatch.transform == closed_pose, "Opening checks the curved swept path before moving")
	hatch.set_open(true)
	var open_pose: Transform3D = hatch.transform
	check(hatch_geometry(hatch, hinge), "Fully opened hatch keeps its top rear edge attached and collision aligned")
	var open_lower_edge := rv.engine_bay.to_local(hatch.to_global(Vector3(0, -0.33, 0.05)))
	check(open_lower_edge.y > 0.28 and open_lower_edge.z < -0.53, "Open hatch swings its lower edge upward and forward around the fixed hinge")
	hatch_result = hatch.interact(player)
	check(hatch_result.contains("被擋住") and hatch.opened and hatch.transform == open_pose, "Closing also checks the curved swept path")
	block.free()
	await physics_frame
	hatch.set_open(false)
	hatch_result = hatch.interact(player)
	check(hatch_result.contains("打開中") and not rv.engine_bay.hatch_open, "Service hatch starts motion without granting engine access: " + hatch_result)
	check(VehicleSnapshot.capture(rv).is_empty(), "Moving hatch cannot be saved")
	var attached := true
	for i in ticks(10):
		await physics_frame
		attached = attached and hatch_geometry(hatch, hinge)
	block = obstacle(world, arc_point, Vector3.ONE * 0.08)
	for i in ticks(80):
		await physics_frame
		attached = attached and hatch_geometry(hatch, hinge)
	check(attached, "Opening and obstacle stop preserve the fixed hinge and rotating collision")
	check(not hatch.moving and not hatch.stable() and not rv.engine_bay.hatch_open, "New obstacle stops hatch at an intermediate pose and keeps engine locked")
	check(VehicleSnapshot.capture(rv).is_empty(), "Blocked hatch also refuses saving")
	block.free()
	await physics_frame
	hatch.interact(player)
	for i in ticks(80): await physics_frame
	check(hatch.stable() and not hatch.opened, "Stopped hatch can reverse to closed")
	check(hatch.transform.is_equal_approx(closed_pose) and hatch_geometry(hatch, hinge), "Reversal returns the hatch to its exact attached closed pose")
	var closed_saved := VehicleSnapshot.capture(rv)
	hatch.set_open(true)
	check(await VehicleSnapshot.apply(rv, closed_saved), "Stable closed hatch snapshot restores")
	check(hatch.transform.is_equal_approx(closed_pose) and not hatch.opened and hatch_geometry(hatch, hinge), "Closed snapshot restores the panel and collision without floating")
	hatch.interact(player)
	for i in ticks(15): await physics_frame
	var interrupted_pose: Transform3D = hatch.transform
	var interrupted_progress: float = hatch.progress
	rv.linear_velocity = Vector3(0, 0, 0.6)
	await physics_frame
	check(not hatch.moving and hatch.progress == interrupted_progress and hatch.transform == interrupted_pose and not rv.engine_bay.hatch_open, "Vehicle movement interrupts opening without jumping the panel or granting access")
	check(VehicleSnapshot.capture(rv).is_empty(), "Vehicle-interrupted intermediate hatch refuses saving")
	rv.linear_velocity = Vector3.ZERO
	hatch.interact(player)
	for i in ticks(80): await physics_frame
	check(hatch.stable() and not hatch.opened and hatch.transform.is_equal_approx(closed_pose), "Vehicle-interrupted hatch reverses from its retained pose")
	hatch.interact(player)
	attached = true
	for i in ticks(80):
		await physics_frame
		attached = attached and hatch_geometry(hatch, hinge)
	check(hatch.opened and rv.engine_bay.hatch_open, "Full opening grants engine service")
	check(attached and hatch.transform.is_equal_approx(open_pose), "Resumed opening remains hinged through its full travel")
	hatch.interact(player)
	for i in ticks(80): await physics_frame
	var ramp: RearRamp = rv.rear_ramp
	rv.get_node("RearDoor").restore_angles([-deg_to_rad(100), deg_to_rad(100)])
	await physics_frame
	var started := ramp.interact(player)
	check(ramp.moving, "Ramp begins animation: " + started)
	for i in ticks(25): await physics_frame
	block = obstacle(world, ramp.to_global(Vector3(0, 1.0, 2.1)), Vector3(0.4, 0.5, 0.4))
	for i in ticks(200): await physics_frame
	check(not ramp.moving and ramp.progress > 0 and ramp.progress < 1 and rv.drive_blocked(), "Mid-animation obstacle leaves ramp safely stopped and driving locked")
	check(VehicleSnapshot.capture(rv).is_empty(), "Partly folded ramp refuses saving")
	block.free()
	await physics_frame
	ramp.interact(player)
	for i in ticks(200): await physics_frame
	check(ramp.stable() and ramp.progress == 0 and not rv.drive_blocked(), "Blocked ramp reverses and fully stows")
	# Independent light loads, supply loss, Item availability, and optional settings.
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
	check(VehicleSnapshot.validate(saved), "Lighting settings are valid optional v4 state")
	hatch.set_open(false)
	check(await VehicleSnapshot.apply(rv, saved), "Lighting settings round trip")
	check(hatch.opened and rv.engine_bay.hatch_open and hatch.transform.is_equal_approx(open_pose) and hatch_geometry(hatch, hinge), "Stable open snapshot restores the hinged panel and rotating collision")
	check(rv.instrument_brightness == 0.2 and rv.vibration_strength == 0.0 and rv.interior_requested.service, "Switches, dimmer and vibration restored exactly")
	var bad := saved.duplicate(true)
	bad.comfort.brightness = NAN
	check(not VehicleSnapshot.validate(bad), "Invalid lighting settings rejected before restore")
	saved.erase("comfort")
	check(await VehicleSnapshot.apply(rv, saved), "V4 snapshots without optional comfort settings load")
	check(rv.interior_requested.cabin and not rv.interior_requested.work and rv.instrument_brightness == 0.65, "Missing comfort settings use explicit defaults")
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
