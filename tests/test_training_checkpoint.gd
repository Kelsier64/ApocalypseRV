extends SceneTree
## Real v11 retry capture, strict nested schema, and transactional replacement.
const WAIT = preload("res://tests/support/test_wait.gd")
const SAVE_PATH := "res://.godot/test-training-checkpoint.save"
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func settle(world: Node) -> bool:
	for index in range(90): await physics_frame
	return await WAIT.generator_idle(self, world.get_node("WorldGenerator")) and await WAIT.retired_candidates(self, root.get_node("Checkpoint"))

func _run() -> void:
	var checkpoint: Node = root.get_node("Checkpoint")
	var world: Node3D = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = generator.profile.duplicate()
	generator.profile.generation_version = 11
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	root.add_child(world)
	current_scene = world
	if not await world.wait_for_play() or not await settle(world):
		check(false, "Production training world becomes ready")
		quit(1)
		return
	var controller: Node = world.get_node("StartRun/Tutorial")
	if not await WAIT.until(self, func(): return not controller.entry_snapshot.is_empty(), 15000, true):
		check(false, "Settled training world captures a stage entry")
		quit(1)
		return
	var entry: Dictionary = checkpoint.capture_world(world, false)
	check(not entry.is_empty(), "World capture returns valid in-memory data")
	if entry.is_empty(): quit(1); return
	check(not entry.start_state.tutorial.has("entry_snapshot"), "Retry capture excludes nested entry snapshots")
	var saved: Dictionary = checkpoint.capture_world(world)
	check(saved.start_state.tutorial.has("entry_snapshot"), "Normal capture includes stage retry data")
	check(checkpoint.validation_error(saved).is_empty(), "Live and entry worlds may independently own the same Item IDs")
	check(saved.start_state.tutorial.entry_snapshot.start_state.tutorial.stage == 1, "Entry records its explicit tutorial stage")
	_test_schema(checkpoint, saved)
	var old_player: Node = world.get_node("Player")
	var old_vehicle: Node = controller.designated_rv()
	var old_pose: Transform3D = old_player.global_transform
	var old_time: Dictionary = world.get_node("WorldClock").capture()
	var malformed := saved.duplicate(true)
	malformed.start_state.tutorial.entry_snapshot.player.transform.origin.x = NAN
	check(not await checkpoint.load_snapshot(world, malformed), "Malformed retry snapshot is rejected before preparation")
	check(current_scene == world and old_player.global_transform == old_pose and checkpoint.pending.is_empty(), "Malformed data leaves live world and pending state intact")
	checkpoint.vehicle_applier = func(_rv: Node3D, _state: Dictionary) -> bool: return false
	check(not await checkpoint.load_snapshot(world, entry), "Vehicle application failure rejects an in-memory retry")
	check(current_scene == world and is_instance_valid(old_vehicle) and old_player.global_transform == old_pose, "Failed retry retains original actors and player pose")
	check(world.process_mode != Node.PROCESS_MODE_DISABLED and not checkpoint.loading, "Failed retry restores live processing and clears busy state")
	check(world.get_node("WorldClock").capture() == old_time, "Failed retry does not advance the old world clock")
	checkpoint.vehicle_applier = VehicleSnapshot.apply
	checkpoint.world_timeout_ms = 0
	check(not await checkpoint.load_snapshot(world, entry), "In-memory retry respects the preparation deadline")
	check(current_scene == world and not checkpoint.loading, "Preparation timeout retains the current world")
	checkpoint.world_timeout_ms = 60000
	check(await WAIT.retired_candidates(self, checkpoint), "Failed candidates retire before the next transaction")
	var progressed := saved.duplicate(true)
	progressed.start_state.tutorial.flags.viewed = true
	progressed.start_state.tutorial.flags.marker_index = 1
	check(checkpoint.write_checkpoint(SAVE_PATH, progressed), "Progress fixture writes a normal checkpoint")
	var bytes := FileAccess.get_file_as_bytes(SAVE_PATH)
	check(checkpoint.read_checkpoint(SAVE_PATH) == progressed, "Disk round trip retains nested retry data without migration")
	if not await checkpoint.load_snapshot(world, progressed):
		check(false, "Valid progress snapshot replaces the current world")
		quit(1)
		return
	world = current_scene
	if not await settle(world):
		check(false, "Restored training world settles")
		quit(1)
		return
	controller = world.get_node("StartRun/Tutorial")
	check(controller.capture().flags == progressed.start_state.tutorial.flags, "Checkpoint restores tutorial flags without retroactive progress")
	check(controller.capture().entry_snapshot == progressed.start_state.tutorial.entry_snapshot, "Full checkpoint preserves its independent retry snapshot")
	var run: Node = world.get_node("StartRun")
	check(run.capture().bay_gates == progressed.start_state.bay_gates, "Checkpoint preserves all stable bay gate states")
	for index in range(8):
		check(run.shelter.get_node("Gates").get_child(index).is_open() == progressed.start_state.bay_gates[index], "Restored gate matches saved physical pose")
	var terminal: Item = controller.designated_terminal()
	check(terminal != null and terminal.capture_item_state().training_terminal == _terminal_state(progressed, controller.terminal_id), "Checkpoint preserves designated terminal manual state and ID")
	check(terminal != null and terminal.get("manual_unlocked") == false and terminal.get("completion") == "locked", "Restored stage-one terminal keeps the manual locked")
	check(FileAccess.get_file_as_bytes(SAVE_PATH) == bytes, "In-memory loading never rewrites the source checkpoint")
	if terminal != null: terminal.queue_free()
	await process_frame
	check(controller.designated_terminal() == null, "Removed designated terminal is unavailable in the current world")
	check(controller.can_restart(), "Restart Stage remains available after losing the designated terminal")
	var menu: Node = world.get_node("Player/SettingsMenu")
	await _tap(KEY_ESCAPE)
	check(menu.visible and world.get_node("Player").settings_open, "Actual Escape input opens the player settings menu")
	check(menu._restart_stage.visible and not menu._restart_stage.disabled, "Lost-terminal world still presents an enabled Restart Stage button")
	menu._restart_stage.grab_focus()
	await _tap(KEY_ENTER)
	check(menu._modal_kind == "restart_stage" and menu._modal.visible, "Actual button activation presents the restart confirmation")
	var previous_world_id := world.get_instance_id()
	menu._modal_accept.grab_focus()
	await _tap(KEY_ENTER)
	if not await WAIT.until(self, func(): return current_scene.get_instance_id() != previous_world_id or (not checkpoint.loading and not checkpoint.last_error.is_empty())):
		check(false, "Confirmed Restart Stage finishes its replacement transaction")
		quit(1)
		return
	if current_scene.get_instance_id() == previous_world_id:
		check(false, "Confirmed Restart Stage applies the captured entry transaction")
		quit(1)
		return
	world = current_scene
	if not await settle(world):
		check(false, "Restarted training world settles")
		quit(1)
		return
	controller = world.get_node("StartRun/Tutorial")
	check(controller.capture().flags == saved.start_state.tutorial.entry_snapshot.start_state.tutorial.flags, "Restart Stage resets only to its recorded entry progress")
	check(controller.entry_snapshot == saved.start_state.tutorial.entry_snapshot, "Restart Stage immediately retains the exact original entry for subsequent retries")
	check(controller.capture().terminal_id == saved.start_state.tutorial.terminal_id, "Restart Stage retains the designated terminal identity")
	terminal = controller.designated_terminal()
	check(terminal != null and terminal.persistent_id == saved.start_state.tutorial.terminal_id, "Restart Stage restores the lost designated terminal with its original ID")
	check(terminal != null and terminal.get("manual_unlocked") == false and terminal.get("completion") == "locked", "Restart Stage restores the original locked terminal manual state")
	check(not world.get_node("Player").settings_open, "Restart confirmation closes the settings input gate before world replacement")
	check(FileAccess.get_file_as_bytes(SAVE_PATH) == bytes, "Restart Stage does not rewrite a disk save")
	check(await WAIT.retired_candidates(self, checkpoint), "Successful transaction releases staging viewports")
	world.get_node("WorldGenerator").set_process(false)
	check(await WAIT.generator_idle(self, world.get_node("WorldGenerator")), "Final world generation becomes idle")
	check(await WAIT.navigation_bakes_finished(self, world), "Final navigation work retires cleanly")
	world.free()
	if failures.is_empty(): print("PASS: training checkpoint capture, strict retry schema, rollback and Restart Stage")
	quit(0 if failures.is_empty() else 1)

func _tap(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	await process_frame
	await process_frame

func _terminal_state(data: Dictionary, identity: String) -> Dictionary:
	for vehicle in data.vehicles:
		for actor in vehicle.mounted_items:
			if actor.state.id == identity: return actor.state.get("training_terminal", {})
	return {}

func _configured_service() -> Dictionary:
	return {"version": 1, "configured": true, "wall_slot": "left_0", "wheel_slot": 0, "engine_id": "service-engine", "wheel_id": "service-wheel", "spare_id": "service-spare", "kit_id": "service-kit", "fuel_port_id": "service-port", "flags": {"wall": false, "engine": false, "removed": false, "wheel": false, "refueled": false, "departure": false}, "fuel_can_id": "", "empty_can_id": "", "fuel_amount": 0.0}

func _test_schema(checkpoint: Node, saved: Dictionary) -> void:
	for kind in ["version", "stage", "status", "empty_id", "id_type", "flag_type", "flag_missing", "marker_range", "unknown_field", "entry_type", "nested", "entry_stage", "entry_identity", "entry_version", "entry_workshop_target", "service_missing", "entry_service_configured", "duplicate"]:
		var bad := saved.duplicate(true)
		var tutorial: Dictionary = bad.start_state.tutorial
		match kind:
			"version": tutorial.version = 4
			"stage": tutorial.stage = 10
			"status": tutorial.status = "unknown"
			"empty_id": tutorial.rv_id = ""
			"id_type": tutorial.terminal_id = 12
			"flag_type": tutorial.flags.viewed = 1
			"flag_missing": tutorial.flags.erase("parked")
			"marker_range": tutorial.flags.marker_index = 3
			"unknown_field": tutorial["unknown"] = false
			"entry_type": tutorial.entry_snapshot = []
			"nested": tutorial.entry_snapshot.start_state.tutorial["entry_snapshot"] = tutorial.entry_snapshot.duplicate(true)
			"entry_stage": tutorial.entry_snapshot.start_state.tutorial.stage = 2
			"entry_identity": tutorial.entry_snapshot.start_state.tutorial.terminal_id = "other-terminal"
			"entry_version":
				var old_entry: Dictionary = tutorial.entry_snapshot.start_state.tutorial
				old_entry.version = 1
				old_entry.erase("workshop")
				old_entry.erase("service")
			"entry_workshop_target": tutorial.entry_snapshot.start_state.tutorial.workshop.targets.battery = "other-battery"
			"service_missing": tutorial.erase("service")
			"entry_service_configured": tutorial.entry_snapshot.start_state.tutorial.service = _configured_service()
			"duplicate":
				var items: Array = tutorial.entry_snapshot.actors.filter(func(actor): return actor.kind == "item")
				check(not items.is_empty(), "Retry fixture contains real Item actors")
				if not items.is_empty(): tutorial.entry_snapshot.actors.append(items[0].duplicate(true))
		check(not checkpoint.validation_error(bad).is_empty(), "Reject malformed tutorial or entry snapshot: " + kind)
	var legacy := saved.duplicate(true)
	legacy.start_state.tutorial.version = 1
	legacy.start_state.tutorial.erase("workshop")
	legacy.start_state.tutorial.erase("service")
	legacy.start_state.tutorial.entry_snapshot.start_state.tutorial.version = 1
	legacy.start_state.tutorial.entry_snapshot.start_state.tutorial.erase("workshop")
	legacy.start_state.tutorial.entry_snapshot.start_state.tutorial.erase("service")
	check(checkpoint.validation_error(legacy).is_empty(), "Original tutorial v1 retains its independent retry snapshot")
	var legacy_stage_two := legacy.duplicate(true)
	legacy_stage_two.start_state.tutorial.stage = 2
	legacy_stage_two.start_state.tutorial.entry_snapshot.start_state.tutorial.stage = 2
	check(checkpoint.validation_error(legacy_stage_two).is_empty(), "Original tutorial v1 accepts its historical stage-two entry")
	legacy.start_state.erase("tutorial")
	check(checkpoint.validation_error(legacy).is_empty(), "Existing v11 stage-one save remains valid without tutorial progress")
	for status in ["active", "skipped"]:
		var valid := saved.duplicate(true)
		valid.start_state.tutorial.status = status
		check(checkpoint.validation_error(valid).is_empty(), "Explicit tutorial status remains valid: " + status)
	var next_stage := saved.duplicate(true)
	next_stage.start_state.tutorial.stage = 2
	next_stage.start_state.tutorial.entry_snapshot.start_state.tutorial.stage = 2
	check(checkpoint.validation_error(next_stage).is_empty(), "Stage-two battery training can persist its own explicit entry snapshot")
	var service_stage := saved.duplicate(true)
	service_stage.start_state.tutorial.stage = 7
	service_stage.start_state.tutorial.service = _configured_service()
	service_stage.start_state.tutorial.entry_snapshot.start_state.tutorial.stage = 7
	service_stage.start_state.tutorial.entry_snapshot.start_state.tutorial.service = _configured_service()
	service_stage.start_state.tutorial.service.flags.wall = true
	check(checkpoint.validation_error(service_stage).is_empty(), "Service entry permits later progress and references consumed or lost actors")
	for field in ["engine_id", "wheel_id", "spare_id", "kit_id", "fuel_port_id"]:
		var mismatch := service_stage.duplicate(true)
		mismatch.start_state.tutorial.entry_snapshot.start_state.tutorial.service[field] = "different-" + field
		check(not checkpoint.validation_error(mismatch).is_empty(), "Service entry retains immutable " + field)
	var complete := service_stage.duplicate(true)
	complete.start_state.tutorial.stage = 9
	complete.start_state.tutorial.entry_snapshot.start_state.tutorial.stage = 9
	complete.start_state.tutorial.status = "completed"
	complete.start_state.tutorial.service.flags.departure = true
	check(checkpoint.validation_error(complete).is_empty(), "Completed v3 tutorial records stage-nine departure and its active entry")
	var old_v2 := saved.duplicate(true)
	old_v2.start_state.tutorial.version = 2
	old_v2.start_state.tutorial.erase("service")
	old_v2.start_state.tutorial.stage = 7
	old_v2.start_state.tutorial.entry_snapshot.start_state.tutorial.version = 2
	old_v2.start_state.tutorial.entry_snapshot.start_state.tutorial.erase("service")
	old_v2.start_state.tutorial.entry_snapshot.start_state.tutorial.stage = 7
	check(checkpoint.validation_error(old_v2).is_empty(), "V2 retains its original stage-seven entry")
	old_v2.start_state.tutorial.stage = 8
	old_v2.start_state.tutorial.entry_snapshot.start_state.tutorial.stage = 8
	check(not checkpoint.validation_error(old_v2).is_empty(), "V2 cannot contain the new stage-eight lesson")
	for version in [7, 8, 9, 10]:
		var old := legacy.duplicate(true)
		old.generation_version = version
		old.profile.generation_version = version
		old.profile.terrain_half_width = 450.0
		old.start_state.erase("bay_gates")
		# A synthetic earlier profile cannot retain terrain-specific v11 wreck
		# placement. Real v10 round trips are covered by their production suite.
		old.erase("rear_wreck_layout")
		var field: String = checkpoint.validation_error(old)
		check(field.is_empty(), "Historical shelter generation remains valid: v%d (%s)" % [version, field])
