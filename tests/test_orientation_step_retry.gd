extends "res://tests/test_orientation_workshop_journey.gd"
## Every entrance is reached by the inherited native workshop transactions.
const MANUAL_PATH := "res://.godot/test-orientation-step-retry.save"
var checkpoint: Node
var manual_bytes: PackedByteArray
var retried_steps: Array[int] = []

func reception() -> bool:
	checkpoint = root.get_node("Checkpoint")
	if not await super.reception(): return false
	workshop = tutorial.workshop
	return await step_ready(1)

func step_ready(expected: int) -> bool:
	if not await super.step_ready(expected): return false
	if not check(await WAIT.until(self, func() -> bool:
		var entry: Dictionary = tutorial.entry_snapshot
		return not entry.is_empty() and entry.start_state.tutorial.stage == 2 and entry.start_state.tutorial.workshop.step == expected,
		12000, true), "Step %d captures its own stable entrance" % expected): return false
	var entry: Dictionary = tutorial.entry_snapshot.duplicate(true)
	check(not entry.start_state.tutorial.has("entry_snapshot"), "Step %d entrance contains no recursive retry" % expected)
	_close_owned_ui()
	await frames()
	var current: Dictionary = checkpoint.capture_world(world)
	if not check(not current.is_empty() and current.start_state.tutorial.entry_snapshot == entry, "Current step %d checkpoint retains independent entrance" % expected): return false
	if manual_bytes.is_empty():
		if not check(checkpoint.write_checkpoint(MANUAL_PATH, current), "Independent manual checkpoint writes once"): return false
		manual_bytes = FileAccess.get_file_as_bytes(MANUAL_PATH)
	# First reload the mutable current save, then use the persisted entrance.
	# This catches retries that only work before the first ordinary save/load.
	if not check(await checkpoint.load_snapshot(world, current), "Current step %d checkpoint resumes" % expected): return false
	if not await _rebind_fixture(): return false
	if not check(tutorial.entry_snapshot == entry and workshop.step == expected and tutorial.can_restart(), "Resumed step %d retains its original retry owner" % expected): return false
	if not check(await tutorial.restart_stage(), "Step %d restores its full-world entrance transaction" % expected): return false
	if not await _rebind_fixture(): return false
	check(workshop.capture() == entry.start_state.tutorial.workshop and tutorial.flags == entry.start_state.tutorial.flags, "Step %d retry restores exactly its entrance evidence" % expected)
	check(tutorial.terminal_id == entry.start_state.tutorial.terminal_id and vehicle.persistent_id == entry.start_state.tutorial.rv_id, "Step %d retry retains original terminal and RV identities" % expected)
	var original: Dictionary = {}
	for saved: Dictionary in entry.vehicles:
		if saved.id == vehicle.persistent_id: original = saved
	if not check(not original.is_empty(), "Step %d snapshot includes its original vehicle" % expected): return false
	check(vehicle.get_all_items() == original.materials and is_equal_approx(vehicle.current_fuel, original.fuel), "Step %d retry preserves exact entrance material and fuel balances" % expected)
	check(vehicle.get_node("StructureSlots").snapshot() == original.structures, "Step %d retry restores entrance wall health" % expected)
	for index in 4:
		check(vehicle.wheel_ids[index] == original.wheels[index].id and is_equal_approx(vehicle.wheel_health[index], original.wheels[index].health), "Step %d retry restores wheel %d identity and health" % [expected, index])
	check(player.inventory.items == entry.player.items and player.current_player_health == entry.player.health, "Step %d retry restores inventory ownership and player health" % expected)
	check(FileAccess.get_file_as_bytes(MANUAL_PATH) == manual_bytes, "Step %d current-load and retry leave manual checkpoint unchanged" % expected)
	retried_steps.append(expected)
	return failures.is_empty()

func _close_owned_ui() -> void:
	for item in get_nodes_in_group(Groups.ITEMS):
		if world.is_ancestor_of(item) and item.has_method("_close_ui") and item.get("current_user") == player:
			item._close_ui()
	for child in player.get_children():
		if child.get_script() == load("res://equipment/training_terminal_reader.gd"): child._close_ui()

func _rebind_fixture() -> bool:
	world = current_scene
	if not check(await world.wait_for_play() and await WAIT.generator_idle(self, world.get_node("WorldGenerator")) and await WAIT.retired_candidates(self, checkpoint), "Resumed production world settles before continuing native journey"): return false
	run_owner = world.get_node("StartRun")
	tutorial = run_owner.get_node("Tutorial")
	workshop = tutorial.workshop
	vehicle = tutorial.designated_rv()
	player = world.get_node("Player")
	vehicle.freeze = true
	vehicle.set_physics_process(false)
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.set_handbrake(true)
	vehicle.set_engine_running(false)
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	return true

func completion_check() -> bool:
	check(retried_steps == [1, 2, 3, 4, 5, 6], "All six workshop steps resume current saves and restore their own entrances")
	return await super.completion_check()

func finish() -> void:
	if FileAccess.file_exists(MANUAL_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(MANUAL_PATH))
	await super.finish()
