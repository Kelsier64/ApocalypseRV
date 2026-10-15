extends "res://tests/test_orientation_workshop_journey.gd"
## A physical external push tests the independent vehicle sensor without
## restoring any workshop faults or fabricating successful guide transactions.

func run() -> void:
	world = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.profile = generator.profile.duplicate()
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	generator.world_seed = 42
	root.add_child(world)
	current_scene = world
	if not check(await world.wait_for_play() and await WAIT.generator_idle(self, generator), "Optional exit world becomes ready"):
		await finish(); return
	run_owner = world.get_node("StartRun")
	tutorial = run_owner.get_node("Tutorial")
	vehicle = tutorial.designated_rv()
	player = world.get_node("Player")
	vehicle.freeze = true
	vehicle.set_physics_process(false)
	player.set_physics_process(false)
	if not await reception(): await finish(); return
	workshop = tutorial.workshop
	var untouched: Dictionary = workshop.capture()
	check(workshop.step == 1 and workshop.placed_ids.is_empty() and workshop.recycled_ids.is_empty() and workshop.output_ids.is_empty(), "No optional workshop task was completed")
	check(vehicle.get_engine().health == 0.0 and vehicle.current_power == 0.0 and vehicle.current_fuel == 0.0 and vehicle.wheel_health[0] == 0.0 and vehicle.get_node("StructureSlots").panel("roof_1").is_destroyed, "All initial faults remain in place")
	check(tutorial.departure_block_reason().is_empty(), "Unfinished tasks and broken equipment never lock the sensor")
	if not await parked_sensor_check(): await finish(); return
	vehicle.set_handbrake(false)
	vehicle.freeze = false
	vehicle.set_physics_process(true)
	var heading: Vector3 = run_owner.gate.global_basis.z.normalized()
	vehicle.apply_central_impulse(heading * vehicle.mass * 2.0)
	if not check(await WAIT.until(self, func(): return tutorial.departure_authorized, 5000, true), "Actual rigid-body movement opens the sensor without engine, battery, fuel or task receipts"):
		await finish(); return
	vehicle.freeze = true
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	if not check(await WAIT.until(self, func(): return run_owner.gate.is_open(), 8000, true), "The uncompleted guide still permits the physical gate to open"):
		await finish(); return
	check(workshop.capture() == untouched and run_owner.phase == "preparing", "Opening adds no invented task credit and retains preparation")
	var checkpoint: Node = root.get_node("Checkpoint")
	var saved: Dictionary = checkpoint.capture_world(world)
	check(not saved.is_empty() and saved.start_state.tutorial.workshop.step == 1 and saved.start_state.tutorial.departure_started, "An open gate with no optional receipts can be saved")
	# Clearance geometry is tested separately from the physical push above; the
	# full powered wheel-drive journey is test_orientation_departure.
	vehicle.global_position = run_owner.gate.to_global(Vector3(0, 1.8, 35))
	run_owner._physics_process(0.3)
	check(run_owner.phase == "preparing", "The player must leave too, even when every task is optional")
	player.global_position = run_owner.gate.to_global(Vector3(0, 1, 12))
	run_owner._physics_process(0.3)
	check(run_owner.phase in ["started", "closing"] and tutorial.status == "completed" and world.get_node("WorldClock").running, "Complete clearance starts the journey without completing any optional reference")
	check(workshop.capture() == untouched, "Departure preserves the truthful unfinished guide ledger")
	check(select_item(tutorial.terminal_id) and player.inventory.active_item().state.training_terminal.manual_unlocked, "Departure unlocks the same manual even with every reference unfinished")
	check(not checkpoint.capture_world(world).is_empty() or not run_owner.save_block_reason().is_empty(), "Incomplete-guide completion remains serializable once the gate settles")
	journey_completed = failures.is_empty()
	print("ORIENTATION_OPTIONAL_EXIT: native push/sensor; separate player/whole-vehicle clearance probes; no guide receipts")
	await finish()

func parked_sensor_check() -> bool:
	vehicle.set_handbrake(true)
	vehicle.freeze = false
	vehicle.set_physics_process(true)
	var origin := vehicle.global_position
	var heading: Vector3 = run_owner.gate.global_basis.z.normalized()
	var peak_speed := 0.0
	var max_travel := 0.0
	for tick in 240:
		await physics_frame
		peak_speed = maxf(peak_speed, vehicle.linear_velocity.dot(heading))
		max_travel = maxf(max_travel, absf((vehicle.global_position - origin).dot(heading)))
		if tutorial.departure_authorized: break
	print("PARKED_SENSOR: peak_forward_speed=", peak_speed, " max_forward_travel=", max_travel, " authorized=", tutorial.departure_authorized)
	return check(not tutorial.departure_authorized and run_owner.gate.target == 0.0, "Suspension settling with no driver input keeps the exit closed")
