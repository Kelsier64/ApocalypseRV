extends SceneTree
## Actual legacy completion loads preserve old contracts without newer grants.
const WAIT = preload("res://tests/support/test_wait.gd")
const STOCK := ["battery", "scrapper", "workbench", "scrap_a", "scrap_b", "barrel"]

class SourceGuard extends CheckpointFiles:
	var source_path := ""
	var source_writes := 0
	var writes := 0
	func write(path: String, data: Dictionary) -> Dictionary:
		writes += 1
		if path == source_path:
			source_writes += 1
			return {"ok": false, "code": "write", "error": ERR_UNAUTHORIZED}
		return super.write(path, data)

var failures: Array[String] = []
var world: Node3D
var checkpoint: Node

func _init() -> void:
	_run.call_deferred()

func check(okay: bool, detail: String) -> bool:
	if not okay:
		failures.append(detail)
		push_error("FAIL: " + detail)
	return okay

func _pin() -> void:
	var tutorial: TutorialController = world.get_node("StartRun/Tutorial")
	var vehicle := tutorial.designated_rv()
	if vehicle != null:
		vehicle.freeze = true
		vehicle.set_physics_process(false)
	world.get_node("Player").set_physics_process(false)

func _settle() -> bool:
	return await WAIT.generator_idle(self, world.get_node("WorldGenerator"), 30000) and await WAIT.retired_candidates(self, checkpoint, 30000) and await WAIT.until(self, func(): return world.get_node("StartRun").save_block_reason().is_empty(), 10000, true)

func _old_state(snapshot: Dictionary, version: int, targets: Dictionary) -> void:
	var state: Dictionary = snapshot.start_state.tutorial
	state.version = version
	state.erase("service")
	if version == 1:
		state.erase("workshop")
		var identities: Array = []
		for key in STOCK: identities.append(targets[key])
		snapshot.actors = snapshot.actors.filter(func(actor): return actor.get("state", {}).get("id", "") not in identities)

func _actor_ids(snapshot: Dictionary) -> Array:
	var identities: Array = []
	for actor in snapshot.actors: identities.append(actor.get("state", {}).get("id", ""))
	identities.sort()
	return identities

func _terminal_state(snapshot: Dictionary, identity: String) -> Dictionary:
	for vehicle in snapshot.vehicles:
		for actor in vehicle.mounted_items:
			if actor.state.id == identity: return actor.state.get("training_terminal", {})
	return {}

func _preserved(actual: Dictionary, original: Dictionary, label: String) -> void:
	if not check(not actual.is_empty(), label + " captures a complete world"): return
	check(checkpoint.validation_error(actual).is_empty(), label + " validates current world and independent legacy entry")
	var state: Dictionary = actual.start_state.tutorial
	var old: Dictionary = original.start_state.tutorial
	for field in ["version", "stage", "status", "terminal_id", "rv_id", "flashlight_id", "flags"]:
		check(state[field] == old[field], label + " preserves " + field)
	check(not state.has("service"), label + " fabricates no service progress or departure proof")
	check(state.entry_snapshot == old.entry_snapshot, label + " preserves the exact old active entry without new manual flags")
	check(_actor_ids(actual) == _actor_ids(original), label + " grants no workshop or service actors")
	check(state.has("workshop") == (old.version == 2), label + " retains only the source version's workshop contract")
	if old.version == 2: check(state.workshop == old.workshop, label + " preserves exact old workshop references and progress")
	var owned := actual.duplicate()
	owned.erase("start_state")
	check(ItemState.unique_ids(owned, {}), label + " preserves unique ordinary Item ownership")
	check(_terminal_state(actual, old.terminal_id) == {"version": 1, "manual_unlocked": true, "completion": "completed"}, label + " unlocks the original terminal's manual as completed")
	var tutorial: TutorialController = world.get_node("StartRun/Tutorial")
	check(not tutorial.service.configured and CheckpointSchema.service_error(tutorial.service.capture()).is_empty(), label + " retains blank service IDs, flags and fuel evidence without newer faults")
	check(world.get_node("StartRun").phase == "preparing", label + " preserves the saved preparation phase")

func _run() -> void:
	checkpoint = root.get_node("Checkpoint")
	world = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = generator.profile.duplicate()
	generator.profile.generation_version = 11
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	root.add_child(world)
	current_scene = world
	if not check(await world.wait_for_play() and await _settle(), "Fresh production tutorial world becomes ready"):
		await finish(); return
	var tutorial: TutorialController = world.get_node("StartRun/Tutorial")
	if not check(await WAIT.until(self, func(): return tutorial.initialized() and not tutorial.entry_snapshot.is_empty(), 15000, true), "Fresh production world records its independent entry"):
		await finish(); return
	_pin()
	var fresh: Dictionary = checkpoint.capture_world(world)
	if not check(not fresh.is_empty(), "Fresh production world provides a real checkpoint fixture"):
		await finish(); return
	var targets: Dictionary = fresh.start_state.tutorial.workshop.targets.duplicate(true)
	for version in [1, 2]:
		var legacy := fresh.duplicate(true)
		_old_state(legacy, version, targets)
		_old_state(legacy.start_state.tutorial.entry_snapshot, version, targets)
		legacy.start_state.tutorial.status = "completed"
		legacy.start_state.tutorial.flags.viewed = true
		legacy.start_state.tutorial.flags.marker_index = 1
		check(legacy.start_state.tutorial.stage == 1 and legacy.start_state.tutorial.entry_snapshot.start_state.tutorial.status == "active", "V%d fixture truthfully retains old completion below stage nine and its active entry" % version)
		if not check(checkpoint.validation_error(legacy).is_empty(), "V%d completed legacy fixture validates" % version):
			await finish(); return
		var source_path := "res://.godot/test-training-legacy-completion-v%d-source.save" % version
		var copy_path := "res://.godot/test-training-legacy-completion-v%d-copy.save" % version
		checkpoint.file_operations = CheckpointFiles.new()
		if not check(checkpoint.write_checkpoint(source_path, legacy), "V%d original manual checkpoint writes" % version):
			await finish(); return
		var source_bytes := FileAccess.get_file_as_bytes(source_path)
		var files := SourceGuard.new()
		files.source_path = source_path
		checkpoint.file_operations = files
		var decoded: Dictionary = checkpoint.read_checkpoint(source_path)
		check(decoded == legacy, "V%d manual source reads without implicit migration" % version)
		if not check(await checkpoint.load_snapshot(world, decoded), "V%d completed source loads through the real transaction" % version):
			await finish(); return
		world = current_scene
		_pin()
		if not check(await _settle() and await WAIT.until(self, func(): return world.get_node("StartRun/Tutorial")._manual_synced, 10000, true), "V%d live legacy completion settles and unlocks its manual" % version):
			await finish(); return
		var captured: Dictionary = checkpoint.capture_world(world)
		_preserved(captured, legacy, "Loaded v%d" % version)
		check(files.writes == 0, "V%d loading and manual unlock perform no file writes" % version)
		if not check(checkpoint.save_world(world, copy_path), "V%d completed live world saves to a separate checkpoint" % version):
			await finish(); return
		var saved: Dictionary = checkpoint.read_checkpoint(copy_path)
		if not check(not saved.is_empty() and await checkpoint.load_snapshot(world, saved), "V%d recaptured checkpoint reloads through the real transaction" % version):
			await finish(); return
		world = current_scene
		_pin()
		if not check(await _settle() and await WAIT.until(self, func(): return world.get_node("StartRun/Tutorial")._manual_synced, 10000, true), "V%d repeated load settles without newer grants" % version):
			await finish(); return
		_preserved(checkpoint.capture_world(world), legacy, "Reloaded v%d" % version)
		check(files.writes == 1 and files.source_writes == 0 and FileAccess.get_file_as_bytes(source_path) == source_bytes, "V%d only the explicit separate save writes; the original manual source remains byte-for-byte unchanged" % version)
	await finish()

func finish() -> void:
	checkpoint.file_operations = CheckpointFiles.new()
	if is_instance_valid(world):
		world.get_node("WorldGenerator").set_process(false)
		await WAIT.generator_idle(self, world.get_node("WorldGenerator"), 30000)
		await WAIT.navigation_bakes_finished(self, world, 30000)
		world.free()
		await physics_frame
		await process_frame
	if failures.is_empty(): print("PASS: real legacy v1/v2 completion load, manual unlock, save and repeat load")
	quit(0 if failures.is_empty() else 1)
