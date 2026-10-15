extends SceneTree
## New-course checkpoints preserve the real terminal across static and inventory owners.
const WAIT = preload("res://tests/support/test_wait.gd")
const SAVE_PATH := "res://.godot/test-orientation-checkpoint.save"
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
	world = load("res://world/main_world.tscn").instantiate()
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
	check(starting_items.size() == 1 and starting_items[0] == terminal, "The wall terminal is the only starting Item in this site")
	check(terminal.is_fixed and terminal.get_connected_rv() == null and not terminal.has_completed_boot(), "Original terminal operates from its static dock without RV ownership")
	var initial: Dictionary = checkpoint.capture_world(world)
	if not check(not initial.is_empty() and initial.start_state.bay_gates == [false], "Initial checkpoint records one closed inner gate"):
		await finish(); return
	check(initial.version == 5 and initial.start_state.tutorial.course == "two_room_orientation", "Outer v5 retains a distinct course discriminator")
	check(not initial.start_state.tutorial.has("entry_snapshot"), "Stage one does not fabricate future retry state")
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
	terminal.interact_hold(player)
	if not check(player.in_ui_mode, "Docked terminal opens on internal power"):
		await finish(); return
	terminal.start_boot()
	terminal.advance_boot(2.0)
	terminal._close_ui()
	var partial: Dictionary = checkpoint.capture_world(world)
	if not check(not partial.is_empty(), "Partially booted terminal saves") or not await load_snapshot(partial):
		await finish(); return
	run = world.get_node("StartRun")
	course = run.get_node("Tutorial")
	terminal = course.designated_terminal()
	player = world.get_node("Player")
	check(course.terminal_id == identity and not course.flags.boot_complete, "Reload preserves identity without awarding initialization")
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
	await finish()

func finish() -> void:
	if is_instance_valid(world): world.queue_free()
	await process_frame
	if FileAccess.file_exists(SAVE_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("PASS: orientation checkpoint ownership and progress" if failures.is_empty() else "FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
