extends SceneTree
## Retry uses actual full-world staging; ownership fixtures exercise every ledger.
const WAIT = preload("res://tests/support/test_wait.gd")
const SAVE_PATH := "res://.godot/test-orientation-recovery.save"
var failures: Array[String] = []
var world: Node3D
var checkpoint: Node
var course: Node
var player: Node
var vehicle: Chassis

func _init() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> bool:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)
	return ok

func bind_world() -> void:
	course = world.get_node("StartRun/Tutorial")
	player = world.get_node("Player")
	vehicle = course.designated_rv()

func settled() -> bool:
	return await WAIT.generator_idle(self, world.get_node("WorldGenerator")) and await WAIT.retired_candidates(self, checkpoint)

func entrance() -> bool:
	return await WAIT.until(self, func(): return not course.entry_snapshot.is_empty(), 12000, true)

func run() -> void:
	checkpoint = root.get_node("Checkpoint")
	world = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.profile = generator.profile.duplicate()
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	generator.world_seed = 42
	root.add_child(world)
	current_scene = world
	if not check(await world.wait_for_play() and await settled(), "Production orientation world becomes ready"):
		await finish(); return
	bind_world()
	if not check(await entrance(), "Reception captures a stable full-world entrance"):
		await finish(); return
	var initial: Dictionary = course.entry_snapshot.duplicate(true)
	check(initial.start_state.tutorial.version == 4 and not initial.start_state.tutorial.has("entry_snapshot"), "Entrance uses v4 without recursive retry snapshots")
	check(not course.capture(false).has("entry_snapshot") and course.capture().entry_snapshot == initial, "Controller include_retry persists an independent entrance")
	check(checkpoint.write_checkpoint(SAVE_PATH, initial), "Separate manual-save fixture writes")
	var manual_before := FileAccess.get_file_as_bytes(SAVE_PATH)
	var terminal: TrainingTerminal = course.designated_terminal()
	var identity := terminal.persistent_id
	terminal.interact_hold(player)
	terminal.start_boot()
	terminal.advance_boot(2.0)
	terminal._close_ui()
	vehicle.current_fuel = 8.0
	vehicle.storage.items["Metal Parts"] = 13
	vehicle.get_node("StructureSlots").panel("left_0").set_health(20.0)
	player.current_player_health = 55.0
	check(course.entry_snapshot == initial, "Partial boot and mutable fuel/material/body changes retain original entrance")
	var rejected := initial.duplicate(true)
	rejected.version = -1
	course.entry_snapshot = rejected
	var original_world := world
	check(not await course.restart_stage() and current_scene == original_world and is_instance_valid(original_world), "Failed retry retains the exact current world")
	check(vehicle.current_fuel == 8.0 and player.current_player_health == 55.0, "Failed retry retains current gameplay state")
	course.entry_snapshot = initial.duplicate(true)
	if not check(await course.restart_stage(), "Valid retry transaction restores the reception entrance"):
		await finish(); return
	world = current_scene
	if not check(await settled(), "Replacement world finishes staging and retirement"):
		await finish(); return
	bind_world()
	terminal = course.designated_terminal()
	check(terminal != null and terminal.persistent_id == identity and not terminal.boot_state().boot_started and terminal.boot_state().boot_elapsed == 0.0, "Retry restores the same terminal with original boot state")
	check(vehicle.current_fuel == 0.0 and vehicle.get_item_count("Metal Parts") == 0 and player.current_player_health == initial.player.health, "Retry restores fuel, material inventory and player health")
	var initial_wall := 0.0
	for panel: Dictionary in initial.vehicles[0].structures:
		if panel.slot == "left_0": initial_wall = panel.health
	check(is_equal_approx(vehicle.get_node("StructureSlots").panel("left_0").current_health, initial_wall), "Retry restores the original damaged wall")
	check(FileAccess.get_file_as_bytes(SAVE_PATH) == manual_before, "Successful and failed retries preserve the manual-save bytes")
	# Native boot and original-dock pickup create the next room's real entrance.
	terminal.interact_hold(player)
	terminal.start_boot()
	terminal.advance_boot(6.0)
	terminal._close_ui()
	terminal.pickup(player)
	await process_frame
	if not check(await WAIT.until(self, func(): return world.get_node("StartRun").save_block_reason().is_empty(), 12000, true), "Inner gate settles after original pickup"):
		await finish(); return
	player.global_position = world.get_node("StartRun").shelter.to_global(Vector3(0, 0, -20))
	if not check(await WAIT.until(self, func(): return course.flags.workshop_entered, 3000, true) and await entrance(), "Entering workshop captures its first stable boundary"):
		await finish(); return
	var first_workshop: Dictionary = course.entry_snapshot.duplicate(true)
	check(first_workshop.start_state.tutorial.stage == 2 and first_workshop.start_state.tutorial.workshop.step == 1, "Reception entrance is replaced only when room boundary advances")
	# A harmless inventory reader remains open at the entrance. Manual F6 must
	# reject UI while the internal retry capture can preserve this exact boundary.
	course.set_physics_process(false)
	course.recovery.restore({})
	var reader: Node = player.read_held_terminal()
	if check(reader != null, "Actual owned inventory terminal opens its reader"):
		check(checkpoint.capture_world(world).is_empty(), "Manual saves retain normal UI restrictions")
		course.recovery.tick(0.6)
		check(not course.entry_snapshot.is_empty(), "Internal entrance captures safely with the owned tutorial reader open")
		reader._close_ui()
	# Independent optional references may finish before the next safe capture.
	# Preserve their settled guide boundary instead of disabling recovery.
	course.recovery.restore({})
	course.recovery._observe_progress()
	var evidence: Dictionary = course.workshop.capture()
	course.workshop.flags.scrapper_placed = true
	course.workshop.placed_ids.append(course.workshop.targets.scrapper)
	course.progress_changed.emit()
	course.recovery.tick(0.6)
	check(not course.entry_snapshot.is_empty() and course.entry_snapshot.start_state.tutorial.workshop.flags.scrapper_placed, "Out-of-order reference progress retains a safe guide recovery point")
	course.workshop.restore(evidence)
	course.recovery.restore(first_workshop)
	await ownership_checks(identity)
	await finish()

func ownership_checks(identity: String) -> void:
	var record: Dictionary = player.inventory.items[0].duplicate(true)
	var portable: Dictionary = record.state.training_terminal.duplicate(true)
	# Test each saved ownership container independently, retaining one live owner.
	var generator: Node = world.get_node("WorldGenerator")
	generator.dormant_items[9999] = []
	for container in [vehicle.stored_items, generator.dormant_items[9999]]:
		container.append(record.duplicate(true))
		course.recovery.unlock_manual("completed")
		var saved: Dictionary = container[-1].state.training_terminal
		check(saved.version == 2 and saved.manual_unlocked and saved.completion == "completed", "Stored and dormant owners unlock without downgrading portable format")
		for key in ["boot_started", "boot_elapsed", "initialized", "internal_charge", "dock_locked"]:
			check(saved[key] == portable[key], "Unlock preserves portable " + key)
		container.pop_back()
	generator.dormant_items.erase(9999)
	var manager: Node = world.get_node("PoiInstances")
	manager.saved_instances["recovery-fixture"] = {"actors": [{"state": record.state.duplicate(true)}]}
	course.recovery.unlock_manual("completed")
	check(manager.saved_instances["recovery-fixture"].actors[0].state.training_terminal.manual_unlocked, "Dormant POI actor records unlock recursively")
	manager.saved_instances.erase("recovery-fixture")
	# Held presentations and the inventory record are both updated before an
	# equip/held-state sync can restore the old locked value.
	var held: Node = player.held_item_node
	check(player.inventory.items[0].state.id == identity and player.inventory.items[0].state.training_terminal.manual_unlocked, "Original inventory owner unlocks")
	if held is TrainingTerminal: check(held.manual_unlocked and held.persistent_id == identity, "Held original presentation unlocks")
	# Lost terminal still leaves controller/Esc recovery available; skip grants
	# no fuel, material or equipment and changes no completed workshop evidence.
	player.inventory.items.clear()
	player.refresh_inventory()
	var fuel := vehicle.current_fuel
	var materials := vehicle.get_all_items()
	var lesson: Dictionary = course.workshop.capture()
	check(course.can_skip() and course.can_restart(), "Esc recovery remains available after losing the terminal")
	check(course.skip_tutorial() and course.status == "skipped" and course.inner_gate_unlocked(), "Skip records skipped and opens the inner gate")
	check(vehicle.current_fuel == fuel and vehicle.get_all_items() == materials and player.inventory.items.is_empty() and course.workshop.capture() == lesson, "Skip supplies no equipment, fuel, materials or invented lesson credit")
	check(course.entry_snapshot.is_empty() and not course.can_restart() and not course.can_skip(), "Skipped course releases entrance and closes recovery actions")
	# An unbooted live v2 dock also becomes a usable manual without inventing
	# initialization or consuming internal charge.
	var live: TrainingTerminal = load("res://equipment/training_terminal.tscn").instantiate()
	live.configure_portable_terminal()
	live.persistent_id = identity
	world.get_node("WorldEntities").add_child(live)
	var boot := live.boot_state().duplicate(true)
	course.recovery.unlock_manual("skipped")
	var expected := boot.duplicate(true)
	expected.manual_unlocked = true
	expected.completion = "skipped"
	check(live.boot_state() == expected and not live._dock_locked(), "Skip releases the original unbooted dock while preserving boot/charge")
	live.ui_instance.on_open()
	check(not live.ui_instance._boot.visible and live.ui_instance.current_page == "manual", "Unlocked unbooted terminal presents its manual immediately")
	live.queue_free()
	await process_frame

func finish() -> void:
	if is_instance_valid(world): world.queue_free()
	await process_frame
	if FileAccess.file_exists(SAVE_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("PASS: orientation stable recovery, failed staging, manual-save preservation and portable ownership" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
