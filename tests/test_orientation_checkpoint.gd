extends SceneTree
## New-course checkpoints preserve the real terminal across static and inventory owners.
const WAIT = preload("res://tests/support/test_wait.gd")
const SAVE_PATH := "res://.godot/test-orientation-checkpoint.save"
const LEGACY_TARGETS := ["scrapper", "workbench", "scrap_a", "scrap_b", "barrel", "spare", "socket", "tablet", "fuel_port", "wall_a", "wall_b", "wheel_slot", "original_wheel"]
const NEW_FLAGS := ["battery_exchanged", "engine_repaired", "roof_rebuilt"]
var failures: Array[String] = []
var world: Node3D
var checkpoint: Node

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> bool:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)
	return ok

func settle() -> bool:
	for index in range(90): await physics_frame
	return await WAIT.generator_idle(self, world.get_node("WorldGenerator")) and await WAIT.retired_candidates(self, checkpoint)

func load_snapshot(snapshot: Dictionary) -> bool:
	if not check(await checkpoint.load_snapshot(world, snapshot), "Validated v12 snapshot replaces the current world"): return false
	world = current_scene
	return check(await settle(), "Replacement terrain, navigation and actor retirement settle")

func _run() -> void:
	checkpoint = root.get_node("Checkpoint")
	world = load("res://tests/orientation_playground.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.profile = generator.profile.duplicate()
	check(generator.profile.generation_version == 12, "Production starts the separate v12 course")
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	generator.world_seed = 42
	root.add_child(world)
	current_scene = world
	if not check(await world.wait_for_play() and await settle(), "Two-room world becomes ready"):
		await finish(); return
	var run: StartRun = world.get_node("StartRun")
	var course: Node = run.get_node("Tutorial")
	if not check(course.initialized() and run.shelter_site.definition_id == "orientation_shelter", "New world binds its own building and course"):
		await finish(); return
	var identity: String = course.terminal_id
	var terminal: TrainingTerminal = course.designated_terminal()
	var player: Node3D = world.get_node("Player")
	check(run.shelter.to_local(player.global_position).z < -26.0, "Player starts in reception")
	check(run.shelter.to_local(world.get_node("NewRv/Chassis").global_position).z > -26.0, "RV starts behind the dividing wall")
	check(player.inventory.items.is_empty(), "Reception player starts with an empty inventory")
	var navigation := world.get_world_3d().navigation_map
	var approach: Vector3 = run.shelter.to_global(Vector3(0, 0, -35))
	var workshop: Vector3 = run.shelter.to_global(Vector3(0, 0, -15))
	var nav_start := NavigationServer3D.map_get_closest_point(navigation, approach)
	var nav_end := NavigationServer3D.map_get_closest_point(navigation, workshop)
	var path := NavigationServer3D.map_get_path(navigation, nav_start, nav_end, true)
	check(nav_start.distance_to(approach) < 1.5 and nav_end.distance_to(workshop) < 1.5 and path.size() >= 2 and path[-1].distance_to(nav_end) < 0.1, "Both floors and the movable inner doorway retain connected navigation")
	var pinned: Array = generator.protected_bands(player.global_position)
	for band in range(floori(-run.shelter_site.bounds.end.z / 150.0) - 1, floori(-run.shelter_site.bounds.position.z / 150.0) + 2):
		check(band in pinned, "Reception retains all depot streaming bands")
	var starting_items := world.get_node("WorldEntities").get_children().filter(func(actor): return actor is Item and run.shelter_site.bounds.has_point(actor.global_position))
	var reception_items := starting_items.filter(func(actor): return run.shelter.to_local(actor.global_position).z < -26.0)
	check(reception_items.size() == 1 and reception_items[0] == terminal, "The wall terminal is the only Item in reception")
	check(starting_items.size() == 17, "Workshop provides sixteen designated portable supplies plus the reception terminal")
	check(terminal.is_fixed and terminal.get_connected_rv() == null and not terminal.has_completed_boot(), "Original terminal operates from its static dock without RV ownership")
	var initial: Dictionary = checkpoint.capture_world(world)
	if not check(not initial.is_empty() and initial.start_state.bay_gates == [false], "Initial checkpoint records one closed inner gate"):
		await finish(); return
	check(initial.version == 5 and initial.start_state.tutorial.course == "two_room_orientation", "Outer v5 retains a distinct course discriminator")
	var initial_workshop: Dictionary = initial.start_state.tutorial.workshop
	check(initial.start_state.tutorial.version == 4 and initial_workshop.version == 2 and initial_workshop.configured and not initial_workshop.migration_pending, "Current course v4 and workshop v2 save one-time workshop configuration")
	check(initial.start_state.tutorial.departure_started == false, "Fresh course has not authorized departure")
	var targets: Dictionary = initial_workshop.targets
	var original_index := 0
	for index in range(initial.vehicles.size()):
		if initial.vehicles[index].id == course.rv_id: original_index = index
	check(initial.start_state.tutorial.rv_id == initial.vehicles[original_index].id and targets.original_wheel == initial.vehicles[original_index].wheels[targets.wheel_slot].id, "Course retains the original RV and left-front wheel identities")
	check(initial.vehicles[original_index].fuel == 0.0 and initial.vehicles[original_index].wheels[targets.wheel_slot].health == 0.0, "Fresh workshop starts with zero fuel and the designated puncture")
	var vehicle: Chassis = course.designated_rv()
	var slots: RVStructureSlots = vehicle.get_node("StructureSlots")
	check(targets.size() == 26 and vehicle.get_engine().id == targets.engine and vehicle.get_battery_socket().installed_battery.id == targets.original_battery, "Fresh workshop records all twenty-six targets including installed service identities")
	check(vehicle.get_engine().health == 0.0 and vehicle.get_battery_socket().installed_battery.charge == 0.0 and slots.panel("roof_1").is_destroyed, "New engine, installed battery and roof faults remain after readiness without a power floor")
	if initial.start_state.tutorial.has("entry_snapshot"):
		check(initial.start_state.tutorial.entry_snapshot.start_state.tutorial.stage == 1 and not initial.start_state.tutorial.entry_snapshot.start_state.tutorial.has("entry_snapshot"), "Reception retry captures its own boundary without nesting")
	var wrong := initial.duplicate(true)
	wrong.start_state.bay_gates = [false, false, false, false, false, false, false, false]
	check(checkpoint.validation_error(wrong) == "start_state.bay_gates", "v12 rejects the legacy eight-gate layout")
	wrong = initial.duplicate(true)
	wrong.generation_version = 11
	wrong.profile.generation_version = 11
	wrong.erase("rear_wreck_layout")
	wrong.start_state.bay_gates = [false, false, false, false, false, false, false, false]
	check(checkpoint.validation_error(wrong) == "start_state.tutorial.generation_version", "v11 cannot load the v12 course")
	wrong = initial.duplicate(true)
	wrong.start_state.erase("tutorial")
	check(checkpoint.validation_error(wrong) == "start_state.tutorial", "v12 requires its own lesson state")
	wrong = initial.duplicate(true)
	for actor: Dictionary in wrong.actors:
		if actor.get("state", {}).get("id") == targets.spare: actor.scene = "res://props/scrap.tscn"
	check(checkpoint.validation_error(wrong) == "start_state.tutorial.workshop.targets.spare", "A designated spare cannot silently change Item type")
	wrong = initial.duplicate(true)
	for actor: Dictionary in wrong.actors:
		if actor.get("state", {}).get("id") == targets.spare:
			wrong.player.items.append({"name": "Duplicate spare", "is_large": true, "scene_path": actor.scene, "state": actor.state.duplicate(true)})
	check(checkpoint.validation_error(wrong) == "item.id.duplicate", "Course references do not exempt duplicate inventory and world Item owners")
	for role in ["battery", "engine_kit_a", "engine_kit_b", "scrap_h", "barrel_b"]:
		wrong = initial.duplicate(true)
		# Another valid owner's identity tests role typing without creating an
		# invalid engine/battery Item payload that fails at an earlier boundary.
		wrong.start_state.tutorial.erase("entry_snapshot")
		wrong.start_state.tutorial.workshop.targets[role] = "wrong-role-" + role
		for actor: Dictionary in wrong.actors:
			if actor.get("state", {}).get("id") == targets.spare: actor.state.id = "wrong-role-" + role
		check(checkpoint.validation_error(wrong) == "start_state.tutorial.workshop.targets." + role, "New workshop role retains its saved Item type: " + role)
	for role in ["engine", "original_battery"]:
		wrong = initial.duplicate(true)
		wrong.start_state.tutorial.erase("entry_snapshot")
		var changed_id: String = "wrong-installed-role-" + role
		wrong.start_state.tutorial.workshop.targets[role] = changed_id
		if role == "engine":
			for device: Dictionary in wrong.vehicles[original_index].mounted_items:
				if device.scene == "res://rv/battery_socket.tscn": device.state.service.battery.id = changed_id
		else:
			wrong.vehicles[original_index].engine_item.id = changed_id
		check(checkpoint.validation_error(wrong) == "start_state.tutorial.workshop.targets." + role, "Installed service references retain their saved owner type: " + role)
	vehicle.get_engine().health = 123.0
	vehicle.get_battery_socket().installed_battery.charge = 40.0
	slots.replace_panel("roof_1", "rv_ceiling", 75.0)
	var repaired: Dictionary = checkpoint.capture_world(world)
	if not check(not repaired.is_empty(), "Fresh engine, battery and rebuilt-roof changes capture") or not await load_snapshot(repaired):
		await finish(); return
	course = world.get_node("StartRun/Tutorial")
	vehicle = course.designated_rv()
	slots = vehicle.get_node("StructureSlots")
	check(vehicle.get_engine().health == 123.0 and absf(vehicle.get_battery_socket().installed_battery.charge - 40.0) < 0.5 and slots.panel("roof_1").current_health == 75.0, "Reload preserves current engine, charge and rebuilt roof without reapplying fresh faults")
	check(course.workshop.targets == targets, "Reload preserves all original and supply identities")
	if not await check_configured_legacy(repaired):
		await finish(); return
	# Stage-one saves contain no workshop supplies. The explicit course migration
	# adds them and configures faults once, retaining original vehicle identity.
	var legacy := initial.duplicate(true)
	legacy.start_state.tutorial.version = 1
	legacy.start_state.tutorial.erase("rv_id")
	legacy.start_state.tutorial.erase("workshop")
	legacy.start_state.tutorial.erase("departure_started")
	legacy.start_state.tutorial.erase("entry_snapshot")
	var supplied: Array = []
	for role in ["scrapper", "workbench", "scrap_a", "scrap_b", "barrel", "spare", "battery", "engine_kit_a", "engine_kit_b", "scrap_c", "scrap_d", "scrap_e", "scrap_f", "scrap_g", "scrap_h", "barrel_b"]: supplied.append(targets[role])
	legacy.actors = legacy.actors.filter(func(actor): return actor.get("state", {}).get("id", "") not in supplied)
	legacy.vehicles[original_index].fuel = 4.5
	legacy.vehicles[original_index].wheels[targets.wheel_slot].health = 100.0
	for panel: Dictionary in legacy.vehicles[original_index].structures:
		if panel.slot == targets.wall_a: panel.health = RVStructureSlots.definition_for(panel.type).health
		if panel.slot == targets.wall_b: panel.health = 25.0
	check(checkpoint.validation_error(legacy).is_empty(), "Historical v1 reception state remains loadable")
	if not await load_snapshot(legacy):
		await finish(); return
	check(legacy.start_state.tutorial.version == 1 and not legacy.start_state.tutorial.has("workshop"), "Migration leaves the caller's historical save unchanged")
	run = world.get_node("StartRun")
	course = run.get_node("Tutorial")
	terminal = course.designated_terminal()
	player = world.get_node("Player")
	vehicle = course.designated_rv()
	if not check(vehicle != null, "Historical course rebinds its original restored RV"):
		await finish(); return
	slots = vehicle.get_node("StructureSlots")
	check(course.workshop.configured and not course.workshop.migration_pending and course.workshop.targets.original_wheel == targets.original_wheel, "Legacy migration binds the same original wheel exactly once")
	check(is_equal_approx(vehicle.current_fuel, 4.5) and vehicle.wheel_health[targets.wheel_slot] == 0.0, "Migration retains saved fuel and applies the designated puncture")
	check(slots.panel(targets.wall_a).current_health == slots.panel(targets.wall_a).max_health - 60.0 and slots.panel(targets.wall_b).current_health == 25.0, "Migration clamps healthy walls to damage targets without adding damage to an already damaged wall")
	# Simulate persistent vehicle changes independently of tutorial credit.
	slots.panel(targets.wall_a).set_health(75.0)
	slots.panel(targets.wall_b).set_health(80.0)
	vehicle.wheel_health[targets.wheel_slot] = 55.0
	vehicle.current_fuel = 3.25
	vehicle.inventory["Metal Parts"] = 3
	terminal.interact_hold(player)
	if not check(player.in_ui_mode, "Docked terminal opens on internal power"):
		await finish(); return
	terminal.start_boot()
	terminal.advance_boot(2.0)
	check(checkpoint.capture_world(world).is_empty(), "Manual save still rejects an open lesson interface")
	check(not checkpoint.capture_world(world, false, true).is_empty(), "Internal retry can capture a stable owned lesson interface")
	player.set_settings_open(true)
	check(checkpoint.capture_world(world, false, true).is_empty(), "Internal UI capture cannot bypass the settings menu")
	player.set_settings_open(false)
	terminal._close_ui()
	var partial: Dictionary = checkpoint.capture_world(world)
	if not check(not partial.is_empty(), "Partially booted terminal saves"):
		await finish(); return
	check(checkpoint.validation_error(partial).is_empty(), "Current partially booted workshop state remains loadable")
	if not await load_snapshot(partial):
		await finish(); return
	run = world.get_node("StartRun")
	course = run.get_node("Tutorial")
	terminal = course.designated_terminal()
	player = world.get_node("Player")
	check(course.terminal_id == identity and not course.flags.boot_complete, "Reload preserves identity without awarding initialization")
	vehicle = course.designated_rv()
	slots = vehicle.get_node("StructureSlots")
	check(slots.panel(targets.wall_a).current_health == 75.0 and slots.panel(targets.wall_b).current_health == 80.0 and absf(vehicle.wheel_health[targets.wheel_slot] - 55.0) < 0.1, "Configured reload preserves current repairs without reapplying original faults (walls=%s/%s, tire=%s)" % [slots.panel(targets.wall_a).current_health, slots.panel(targets.wall_b).current_health, vehicle.wheel_health[targets.wheel_slot]])
	check(is_equal_approx(vehicle.current_fuel, 3.25) and vehicle.inventory.get("Metal Parts") == 3, "Configured reload retains current fuel and materials")
	var restored_supplies: Array = world.get_node("WorldEntities").get_children().filter(func(actor): return actor is Item and actor.persistent_id in supplied)
	check(restored_supplies.size() == 16 and course.workshop.capture() == partial.start_state.tutorial.workshop, "Reload preserves workshop evidence and supplies without reissuing Items")
	check(terminal.boot_state().boot_started and terminal.boot_state().boot_elapsed >= 2.0 and terminal.boot_state().boot_elapsed < 6.0, "Reload preserves Enter and partial boot progress")
	check(terminal.is_fixed and terminal.mount_support == run.shelter.get_node("Collision/TerminalSupport"), "Reload restores the original static dock support")
	terminal.interact_hold(player)
	terminal.advance_boot(6.0)
	terminal._close_ui()
	check(course.flags.boot_complete and not course.flags.terminal_taken, "Completed boot alone keeps the door locked")
	terminal.pickup(player)
	check(course.flags.terminal_taken and course.terminal_in_inventory(player), "Native original-dock pickup records the exact inventory owner")
	await process_frame
	if not check(await WAIT.until(self, func(): return run.save_block_reason().is_empty(), 12000, true), "Inner door finishes opening"):
		await finish(); return
	if not check(checkpoint.save_world(world, SAVE_PATH), "Carried terminal writes a real checkpoint"):
		await finish(); return
	var carried: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	if not check(not carried.is_empty(), "Carried terminal checkpoint decodes"):
		await finish(); return
	wrong = carried.duplicate(true)
	wrong.start_state.tutorial.flags.boot_complete = false
	var retained := world
	check(not await checkpoint.load_snapshot(world, wrong) and current_scene == retained, "Invalid lesson progress retains the current live world")
	if not await load_snapshot(carried):
		await finish(); return
	course = world.get_node("StartRun/Tutorial")
	player = world.get_node("Player")
	check(course.terminal_id == identity and course.flags.boot_complete and course.flags.terminal_taken, "Reload preserves both successful actions")
	check(course.terminal_in_inventory(player) and course.designated_terminal() == null, "Carried terminal reloads with one inventory owner and no duplicate world Item")
	check(world.get_node("StartRun").capture().bay_gates == [true], "Reload keeps the original inner gate open")
	await check_recovery_checkpoint()
	await finish()

func check_configured_legacy(source: Dictionary) -> bool:
	var legacy := source.duplicate(true)
	var tutorial: Dictionary = legacy.start_state.tutorial
	tutorial.erase("entry_snapshot")
	tutorial.version = 3
	tutorial.workshop.version = 1
	for key in NEW_FLAGS: tutorial.workshop.flags.erase(key)
	var old_targets: Dictionary = tutorial.workshop.targets.duplicate(true)
	var extra_supply_ids: Array = []
	for key in old_targets:
		if key not in LEGACY_TARGETS:
			if key not in ["engine", "original_battery", "roof_slot"]: extra_supply_ids.append(old_targets[key])
			tutorial.workshop.targets.erase(key)
	legacy.actors = legacy.actors.filter(func(actor): return actor.get("state", {}).get("id", "") not in extra_supply_ids)
	var old_v2 := legacy.duplicate(true)
	old_v2.start_state.tutorial.version = 2
	old_v2.start_state.tutorial.erase("departure_started")
	check(checkpoint.validation_error(old_v2).is_empty(), "Historical course v2 with workshop v1 remains loadable")
	tutorial["entry_snapshot"] = legacy.duplicate(true)
	if not check(checkpoint.validation_error(legacy).is_empty(), "Historical course v3 and workshop v1 validate with their own retry entrance"): return false
	var unchanged := legacy.duplicate(true)
	if not await load_snapshot(legacy): return false
	check(legacy == unchanged, "Configured migration leaves the source and embedded entrance unchanged")
	var course: Node = world.get_node("StartRun/Tutorial")
	var vehicle: Chassis = course.designated_rv()
	var slots: RVStructureSlots = vehicle.get_node("StructureSlots")
	var upgraded: Dictionary = checkpoint.capture_world(world)
	if not check(not upgraded.is_empty(), "Configured historical course captures its upgraded schema"): return false
	var progress: Dictionary = upgraded.start_state.tutorial
	check(progress.version == 4 and progress.workshop.version == 2 and progress.workshop.targets.size() == 13 and progress.workshop.targets == tutorial.workshop.targets, "Configured migration upgrades schema without inventing new targets")
	check(vehicle.get_engine().health == 123.0 and absf(vehicle.get_battery_socket().installed_battery.charge - 40.0) < 0.5 and slots.panel("roof_1").current_health == 75.0, "Configured historical migration adds no engine, battery or roof faults")
	var supplied := world.get_node("WorldEntities").get_children().filter(func(actor): return actor is Item and actor.persistent_id in old_targets.values())
	check(supplied.size() == 6, "Configured historical migration keeps exactly the original six supplies")
	for key in NEW_FLAGS: check(progress.workshop.flags[key] == false, "Historical upgrade does not fabricate new service evidence: " + key)
	if not check(progress.has("entry_snapshot"), "Historical configured course retains its original retry entrance"): return false
	var entry: Dictionary = progress.entry_snapshot.start_state.tutorial
	check(entry.version == 4 and entry.workshop.version == 2 and entry.workshop.targets == tutorial.workshop.targets, "Embedded entrance upgrades to the same schema without extra targets")
	check(progress.entry_snapshot.actors.size() == unchanged.start_state.tutorial.entry_snapshot.actors.size(), "Embedded entrance migration adds no supplies")
	return true

func check_recovery_checkpoint() -> void:
	# A retry entrance and the live state are separate ownership domains even
	# when every vehicle, carried Item and dormant actor ID occurs in both.
	var saved: Dictionary = checkpoint.capture_world(world, false)
	if not check(not saved.is_empty(), "Current state can capture a standalone retry entrance"): return
	check(not saved.start_state.tutorial.has("entry_snapshot"), "include_retry=false omits the retry payload")
	check_terminal_owner_forms(saved)
	var source := saved.duplicate(true)
	saved.start_state.tutorial["entry_snapshot"] = source
	if not check(checkpoint.validation_error(saved).is_empty(), "Retry entrance validates its own IDs independently"): return
	if not check(checkpoint.write_checkpoint(SAVE_PATH, saved), "Manual checkpoint persists a retry entrance"): return
	var persisted: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	check(persisted == saved, "Disk round trip preserves the complete retry entrance")
	var wrong := saved.duplicate(true)
	wrong.start_state.tutorial.entry_snapshot.start_state.tutorial["entry_snapshot"] = source.duplicate(true)
	check(checkpoint.validation_error(wrong).contains("entry_snapshot.nested"), "Retry entrances cannot contain another retry entrance")
	wrong = saved.duplicate(true)
	wrong.start_state.tutorial.entry_snapshot.start_state.tutorial.flags.workshop_entered = true
	wrong.start_state.tutorial.entry_snapshot.start_state.tutorial.stage = 2
	check(checkpoint.validation_error(wrong) == "start_state.tutorial.entry_snapshot.tutorial.stage", "A retry cannot cross the reception/workshop boundary")
	wrong = saved.duplicate(true)
	var entry: Dictionary = wrong.start_state.tutorial.entry_snapshot
	entry.player.items.append(entry.player.items[0].duplicate(true))
	check(checkpoint.validation_error(wrong) == "start_state.tutorial.entry_snapshot.item.id.duplicate", "Duplicate Item ownership inside the entrance is rejected independently")
	var original_bytes := FileAccess.get_file_as_bytes(SAVE_PATH)
	var retained := world
	var original_applier: Callable = checkpoint.vehicle_applier
	checkpoint.vehicle_applier = func(_vehicle: Node3D, _state: Dictionary) -> bool: return false
	var applied: bool = await checkpoint.load_snapshot(world, persisted)
	checkpoint.vehicle_applier = original_applier
	check(not applied and current_scene == retained and not checkpoint.loading, "Candidate application failure retains the original live world")
	check(FileAccess.get_file_as_bytes(SAVE_PATH) == original_bytes, "Failed retry application leaves the manual checkpoint untouched")
	check(await WAIT.retired_candidates(self, checkpoint), "Failed retry candidate retires")
	if not await load_snapshot(persisted): return
	var restored: Dictionary = checkpoint.capture_world(world)
	check(not restored.is_empty() and restored.start_state.tutorial.entry_snapshot == source, "Reload preserves the original retry entrance instead of capturing progressed state")
	check_departure_state(saved)

func check_terminal_owner_forms(source: Dictionary) -> void:
	var terminal_record: Dictionary = source.player.items[0].duplicate(true)
	var terminal_state: Dictionary = terminal_record.state.training_terminal
	terminal_state.manual_unlocked = true
	terminal_state.completion = "skipped"
	for owner in ["inventory", "storage", "world", "mounted", "dormant"]:
		var form := source.duplicate(true)
		form.player.items.clear()
		var actor: Dictionary = form.actors.filter(func(record): return record.kind == "item")[0].duplicate(true)
		actor.scene = terminal_record.scene_path
		actor.state = terminal_record.state.duplicate(true)
		actor.name = terminal_record.name
		actor.large = terminal_record.is_large
		actor.fixed = owner == "mounted"
		actor.support = {"kind": "chassis", "rv": form.vehicles[0].id} if actor.fixed else {"kind": "none"}
		match owner:
			"inventory": form.player.items.append(terminal_record.duplicate(true))
			"storage": form.vehicles[0].items.append(terminal_record.duplicate(true))
			"world": form.actors.append(actor)
			"mounted": form.vehicles[0].mounted_items.append(actor)
			"dormant":
				var band: int = form.bands[0]
				if not form.dormant_items.has(band): form.dormant_items[band] = []
				form.dormant_items[band].append(actor)
		if not check(checkpoint.validation_error(form).is_empty(), "Unlocked v2 terminal validates under " + owner + " ownership"): continue
		check(checkpoint.write_checkpoint(SAVE_PATH, form) and checkpoint.read_checkpoint(SAVE_PATH) == form, "Disk round trip preserves v2 boot and manual fields under " + owner + " ownership")

func check_departure_state(source: Dictionary) -> void:
	var skipped := source.duplicate(true)
	skipped.start_state.tutorial.erase("entry_snapshot")
	skipped.start_state.tutorial.status = "skipped"
	check(checkpoint.validation_error(skipped).is_empty(), "Skipped course can remain in preparation without fabricated departure")
	skipped.start_state.tutorial.departure_started = true
	check(checkpoint.validation_error(skipped).is_empty(), "Open-exit authorization persists while preparation remains active")
	skipped.start_state.phase = "started"
	check(checkpoint.validation_error(skipped).is_empty(), "Skipped departure can enter the running phase")
	skipped.start_state.tutorial.departure_started = false
	check(checkpoint.validation_error(skipped) == "start_state.tutorial.departure_started.phase", "Running phase requires persisted exit authorization")
	var completed := source.duplicate(true)
	completed.start_state.tutorial.erase("entry_snapshot")
	completed.start_state.tutorial.stage = 2
	completed.start_state.tutorial.flags.workshop_entered = true
	completed.start_state.tutorial.status = "completed"
	completed.start_state.tutorial.departure_started = true
	# Room one is mandatory. The optional workshop guide may retain no receipts
	# when the actual vehicle is restored through other valid transactions.
	check(not CheckpointSchema.orientation_phase_error(completed.start_state).is_empty(), "Completed cannot resume the preparation phase")
	for phase in ["started", "sealed"]:
		completed.start_state.phase = phase
		check(checkpoint.validation_error(completed).is_empty(), "v4 completion retains unfinished optional workshop receipts in stable " + phase + " phase")
	var optional := completed.duplicate(true)
	optional.start_state.phase = "preparing"
	optional.start_state.tutorial.status = "active"
	check(checkpoint.validation_error(optional).is_empty(), "v4 permits departure authorization with a partially followed guide")
	var strict := optional.duplicate(true)
	strict.start_state.tutorial.version = 3
	check(checkpoint.validation_error(strict) == "start_state.tutorial.departure_started", "Historical v3 keeps its strict step-six departure contract")
	var before_reception := completed.duplicate(true)
	before_reception.start_state.tutorial.stage = 1
	before_reception.start_state.tutorial.flags.workshop_entered = false
	check(not checkpoint.validation_error(before_reception).is_empty(), "Optional workshop progress does not permit leaving before reception completion")

func finish() -> void:
	if is_instance_valid(world): world.queue_free()
	await process_frame
	if FileAccess.file_exists(SAVE_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("PASS: orientation checkpoint ownership and progress" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
