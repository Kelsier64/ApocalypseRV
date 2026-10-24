extends "res://tests/support/orientation_journey.gd"
## Complete the same native workshop transactions, then drive through the real
## sensor exit. Only negative clearance probes reposition actors temporarily.

func initial_state() -> bool:
	var scenes := {
		"scrap_a": "res://props/scavenge_loot/copper_wire_spool.tscn",
		"scrap_b": "res://props/scavenge_loot/broken_shortwave_radio.tscn",
		"scrap_c": "res://props/scavenge_loot/salvaged_motor.tscn",
		"scrap_d": "res://props/scavenge_loot/medical_tin.tscn",
		"scrap_e": "res://props/scavenge_loot/industrial_valve.tscn",
		"scrap_f": "res://props/scavenge_loot/enamel_kettle.tscn",
		"scrap_g": "res://props/scrap.tscn",
		"scrap_h": "res://props/scrap.tscn"}
	var prefix: String = str(run_owner.shelter.get_meta("poi_id")) + ":recovery:"
	var checkpoint: Node = root.get_node("Checkpoint")
	var guide: Dictionary = tutorial.capture(false)
	var total_metal := 0
	for role in scenes:
		var item: Item = workshop.item(role)
		if not check(item != null, "Original tutorial stock retains " + role): return false
		check(item.scene_file_path == scenes[role], "Tutorial role selects its authored loot scene: " + role)
		check(item.persistent_id == prefix + role and workshop.targets[role] == item.persistent_id, "Tutorial loot retains the existing role identity: " + role)
		check(item.is_large == (role == "scrap_c"), "Tutorial size matches each loot Item: " + role)
		check(item.scrap_yields == {ItemNames.METAL_PARTS: Vector2(3, 3)}, "Tutorial overrides decorative loot yields with its fixed three-metal supply: " + role)
		total_metal += int(item.scrap_yields[ItemNames.METAL_PARTS].x)
		var record := WorldActorSnapshot.capture(item)
		check(checkpoint._orientation_items_error({"actors": [record]}, guide).is_empty(), "Checkpoint accepts the mapped tutorial loot scene: " + role)
		record.scene = scenes.scrap_b if role == "scrap_a" else scenes.scrap_a
		check(checkpoint._orientation_items_error({"actors": [record]}, guide) == "workshop.targets." + role, "Checkpoint rejects a different loot type under the same tutorial role identity: " + role)
	check(total_metal == 24, "All eight tutorial scrap Items retain twenty-four guaranteed metal")
	# Existing current-version checkpoints can still own the former Scrap scene.
	# Repopulation must honor identity rather than replacing it with the new art.
	var original: Item = workshop.item("scrap_f")
	var saved := WorldActorSnapshot.capture(original)
	saved.scene = "res://props/scrap.tscn"
	saved.name = "Scrap Metal"
	saved.large = false
	check(WorldActorSnapshot.validation_error(saved, "saved_tutorial_scrap").is_empty(), "The previous tutorial Scrap scene remains a valid checkpoint actor")
	check(checkpoint._orientation_items_error({"actors": [saved]}, guide).is_empty(), "Checkpoint still accepts the previous Scrap scene under its saved tutorial role identity")
	var container := original.get_parent() as Node3D
	original.free()
	var restored := WorldActorSnapshot.restore(saved, container) as Item
	var count := container.get_child_count()
	OpeningSiteContent._spawn_orientation_workshop(run_owner.shelter, container)
	check(container.get_child_count() == count and workshop.item("scrap_f") == restored, "Populating the workshop cannot duplicate stock already owned by a saved role identity")
	check(restored.scene_file_path == saved.scene and restored.capture_item_state() == saved.state and restored.get_meta("orientation_role") == "scrap_f", "Existing saved tutorial Scrap retains its scene, state and role")
	if not failures.is_empty(): return false
	return await super.initial_state()

func driving_check() -> bool:
	check(not tutorial.departure_authorized and not run_owner.gate.is_open(), "Workshop completion alone does not open the exit")
	tutorial._tick_departure()
	check(not tutorial.departure_authorized, "A player on foot cannot trigger the vehicle sensor")
	var hatch: Node = vehicle.get_node("EngineBay/Hatch")
	hatch.requested_open = true
	check(tutorial.departure_block_reason().is_empty(), "The guide does not turn cover advice into a departure lock")
	hatch.requested_open = false
	if not await super.driving_check(): return false
	check(tutorial.departure_authorized and run_owner.gate.target == 1.0, "Native forward wheel motion in the original RV triggers the advance sensor")
	check(run_owner.phase == "preparing" and not world.get_node("WorldClock").running, "Opening the automatic gate keeps the safe preparation world")
	return failures.is_empty()

func completion_check() -> bool:
	var gate: ShelterGarageGate = run_owner.gate
	if not check(await WAIT.until(self, func(): return gate.is_open(), 8000, true), "Sensor opens both physical leaves before the RV reaches the doorway"): return false
	clearance_probes(gate)
	vehicle.control_override = {}
	vehicle.freeze = true
	vehicle.set_engine_running(false)
	vehicle.set_handbrake(true)
	player.seated_in.exit_seat(true)
	await frames()
	var checkpoint: Node = root.get_node("Checkpoint")
	var open_exit: Dictionary = checkpoint.capture_world(world)
	if not check(not open_exit.is_empty() and await checkpoint.load_snapshot(world, open_exit), "An authorized open exit persists through an actual checkpoint reload"): return false
	if not await rebind_world(): return false
	gate = run_owner.gate
	check(tutorial.departure_authorized and gate.is_open() and run_owner.phase == "preparing" and not world.get_node("WorldClock").running, "Restoring an open gate preserves authorization and the safe preparation world")
	var driver: Item = vehicle.get_node("DriverSeat")
	player.global_position = driver.global_position + vehicle.global_basis.z
	driver.interact_hold(player)
	if not check(player.seated_in == driver and vehicle.set_gear(1) and vehicle.set_engine_running(true), "The restored RV accepts its original driver and engine"): return false
	vehicle.set_handbrake(false)
	workshop.item("workbench").enabled = false
	vehicle.freeze = false
	player.set_physics_process(true)
	vehicle.control_override = {"throttle": 1.0}
	var origin := vehicle.global_position
	for tick in 1800:
		await physics_frame
		if run_owner.phase != "preparing": break
	vehicle.control_override = {"brake": 1.0}
	print("DEPARTURE_END: phase=", run_owner.phase, " position=", run_owner.shelter.to_local(vehicle.global_position), " velocity=", vehicle.linear_velocity, " heading=", -vehicle.global_basis.z, " reason=", tutorial.departure_block_reason(), " player=", gate.to_local(player.global_position), " driver=", vehicle.is_player_driving, " engine=", vehicle.energy.engine_running)
	if run_owner.phase == "preparing":
		var own_shapes: Array[RID] = [vehicle.get_rid(), player.get_rid()]
		for body in vehicle.find_children("*", "CollisionObject3D", true, false): own_shapes.append(body.get_rid())
		for height in [0.0, 0.5, 1.0, 2.0]:
			for side in [-1.0, 0.0, 1.0]:
				var query := PhysicsRayQueryParameters3D.create(vehicle.to_global(Vector3(side, height, -3)), vehicle.to_global(Vector3(side, height, -8)), 3, own_shapes)
				var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
				if not hit.is_empty(): print("DEPARTURE_BLOCKER: ", hit.collider.get_path(), " at=", hit.position)
		print("DEPARTURE_CONTROLS: ", vehicle.control_override, " throttle=", vehicle.throttle_input, " gear=", vehicle.gear, " handbrake=", vehicle.handbrake, " locked=", vehicle.driver_controls_locked())
		print("DEPARTURE_CONTACTS: ", vehicle.get_colliding_bodies().map(func(body): return str(body.get_path())), " force=", vehicle.engine_force, " fuel=", vehicle.current_fuel, " power=", vehicle.current_power)
		for body in vehicle.get_colliding_bodies():
			if body is Item: print("DEPARTURE_CONTACT_ITEM: scene=", body.scene_file_path, " id=", body.persistent_id, " position=", vehicle.to_local(body.global_position), " fixed=", body.is_fixed)
	if not check(run_owner.phase in ["started", "closing"] and tutorial.status == "completed", "Native wheel forces take the original RV and seated player completely out of the depot"): return false
	check(run_owner.departure_clear() and vehicle.global_position.distance_to(origin) > 0.5, "Successful completion follows actual continuous driving past the whole-vehicle boundary")
	check(world.get_node("WorldClock").running and world.get_node("WorldClock").weather_running, "Complete departure resumes time and weather")
	check(not tutorial.can_restart() and not tutorial.can_skip() and tutorial.entry_snapshot.is_empty(), "Completed departure ends tutorial recovery and releases its snapshot")
	vehicle.freeze = true
	vehicle.set_engine_running(false)
	vehicle.set_handbrake(true)
	# Introduce a real body after the closing movement starts, so the leaf sweep
	# must reopen rather than merely waiting to start its first closing attempt.
	var blocker := RigidBody3D.new()
	blocker.freeze = true
	blocker.collision_layer = 1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1, 1)
	collision.shape = box
	blocker.add_child(collision)
	world.add_child(blocker)
	blocker.global_position = gate.to_global(Vector3(-1.75, 2.5, 0))
	if not check(await WAIT.until(self, func(): return run_owner.phase == "started" and gate.target == 1.0, 5000, true), "A real obstruction in the closing sweep reopens the exit"): return false
	check(tutorial.status == "completed", "Reopening for safety never revokes completion")
	if not check(await WAIT.until(self, func(): return gate.is_open(), 5000, true), "Obstructed leaves physically return to their fully open pose"): return false
	blocker.queue_free()
	await frames()
	if not check(await WAIT.until(self, func(): return run_owner.phase == "sealed", 10000, true), "Clearing the sweep permits permanent closure"): return false
	check(not gate.is_open() and gate.stable(), "Sealed departure has stable physical collision")
	tutorial._tick_departure()
	check(gate.target == 0.0, "A sealed depot cannot reactivate the sensor")
	var seat: Node = player.seated_in
	seat.exit_seat(true)
	await frames()
	if not check(select_item(tutorial.terminal_id), "Departure preserves the same terminal and inventory owner"): return false
	var terminal_state: Dictionary = player.inventory.active_item().state.training_terminal
	check(terminal_state.version == 2 and terminal_state.initialized and terminal_state.manual_unlocked and terminal_state.completion == "completed", "Portable v2 terminal changes to the Completed field manual without losing its boot state")
	var reader: Node = player.read_held_terminal()
	if not check(reader != null, "The completed portable manual opens through the normal inventory reader"): return false
	await frames()
	check(reader.ui_instance.visible and reader.ui_instance.current_page == "manual", "The original TUI opens its searchable manual after departure")
	reader._close_ui()
	await frames()
	var saved: Dictionary = checkpoint.capture_world(world)
	check(not saved.is_empty() and saved.start_state.phase == "sealed" and saved.start_state.tutorial.status == "completed", "The final sealed course produces a valid complete checkpoint")
	print("ORIENTATION_DEPARTURE_DRIVE: distance=", vehicle.global_position.distance_to(origin), " phase=", run_owner.phase)
	if not check(await checkpoint.load_snapshot(world, saved), "Completed departure reloads through staged world replacement"): return false
	if not await rebind_world(): return false
	check(run_owner.phase == "sealed" and run_owner.gate.target == 0.0 and tutorial.status == "completed" and world.get_node("WorldClock").running, "Reload retains permanent closure and the running completed course")
	if not check(select_item(tutorial.terminal_id), "Completed reload retains one original inventory terminal"): return false
	check(player.inventory.active_item().state.training_terminal.manual_unlocked and player.inventory.active_item().state.training_terminal.completion == "completed", "Completed reload preserves the original portable manual")
	return failures.is_empty()

func clearance_probes(gate: ShelterGarageGate) -> void:
	# Probe geometry before the checkpoint reload. Recreating the vehicle then
	# clears wheel contact caches; the positive driving run never teleports it.
	vehicle.freeze = true
	var parked := vehicle.global_transform
	var player_pose := player.global_transform
	player.global_position = gate.to_global(Vector3(0, 1, 9))
	vehicle.global_transform = gate.global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 1.8, 12))
	check(not run_owner.departure_clear(), "A partly exited RV cannot finish the tutorial")
	vehicle.global_position = gate.to_global(Vector3(0, 1.8, 35))
	var machine: Item = workshop.item("workbench")
	var machine_pose := machine.transform
	machine.position = Vector3(0, 1.5, 30)
	check(not run_owner.vehicle_clear(vehicle), "Protruding fixed equipment must also clear the complete exit")
	machine.transform = machine_pose
	machine.enabled = false
	check(tutorial.departure_block_reason().is_empty(), "Disabled optional equipment cannot block final departure clearance")
	machine.enabled = true
	player.global_position = gate.to_global(Vector3(0, 1, 0))
	check(run_owner.vehicle_clear(vehicle) and not run_owner.departure_clear(), "The player must leave too, even after every RV collision has cleared")
	vehicle.global_transform = parked
	player.global_transform = player_pose

func rebind_world() -> bool:
	world = current_scene
	if not check(await world.wait_for_play() and await WAIT.generator_idle(self, world.get_node("WorldGenerator")) and await WAIT.retired_candidates(self, root.get_node("Checkpoint")), "Restored departure world settles"): return false
	run_owner = world.get_node("StartRun")
	tutorial = run_owner.get_node("Tutorial")
	workshop = tutorial.workshop
	vehicle = tutorial.designated_rv()
	player = world.get_node("Player")
	vehicle.allow_test_controls = true
	vehicle.freeze = true
	vehicle.set_physics_process(true)
	player.set_physics_process(false)
	return true
