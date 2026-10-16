extends SceneTree
## Real v1 load upgrades supplies once while preserving the original retry boundary.
const WAIT = preload("res://tests/support/test_wait.gd")
const SAVE_PATH := "res://.godot/test-training-migration.save"
const STOCK := {"battery": "res://props/battery.tscn", "scrapper": "res://equipment/scrapper.tscn", "workbench": "res://equipment/crafting_station.tscn", "scrap_a": "res://props/scrap.tscn", "scrap_b": "res://props/scrap.tscn", "barrel": "res://props/oil_barrel.tscn"}

class ReadOnlyFiles extends CheckpointFiles:
	var writes := 0
	func write(_path: String, _data: Dictionary) -> Dictionary:
		writes += 1
		return {"ok": false, "code": "write", "error": ERR_UNAUTHORIZED}

var failures: Array[String] = []
var world: Node3D
var checkpoint: Node
var tutorial: TutorialController
var workshop: TutorialWorkshop
var source_bytes: PackedByteArray
var files := ReadOnlyFiles.new()

func _init() -> void:
	_run.call_deferred()

func check(okay: bool, detail: String) -> bool:
	if not okay:
		failures.append(detail)
		push_error("FAIL: " + detail)
	return okay

func _bind_and_pin() -> void:
	tutorial = world.get_node("StartRun/Tutorial")
	workshop = tutorial.workshop
	# Keep the loaded physical state stationary while the real controller runs
	# its deferred migration. None of the workshop progress flags are assigned.
	var vehicle := tutorial.designated_rv()
	vehicle.freeze = true
	vehicle.set_physics_process(false)
	world.get_node("Player").set_physics_process(false)

func _settle() -> bool:
	return await WAIT.generator_idle(self, world.get_node("WorldGenerator"), 30000) and await WAIT.retired_candidates(self, checkpoint, 30000) and await WAIT.until(self, func(): return workshop.prepared() and not tutorial.entry_snapshot.is_empty() and tutorial.entry_snapshot.start_state.tutorial.version == 3, 10000, true)

func _strip_stock(snapshot: Dictionary, targets: Dictionary) -> void:
	var identities: Array = []
	for key in STOCK: identities.append(targets[key])
	snapshot.actors = snapshot.actors.filter(func(actor): return actor.get("state", {}).get("id", "") not in identities)
	snapshot.start_state.tutorial.erase("workshop")
	snapshot.start_state.tutorial.erase("service")
	snapshot.start_state.tutorial.version = 1

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
	if not check(await world.wait_for_play() and await WAIT.generator_idle(self, generator, 30000), "Production v11 world becomes ready"):
		await finish(); return
	tutorial = world.get_node("StartRun/Tutorial")
	if not check(await WAIT.until(self, func(): return tutorial.initialized() and not tutorial.entry_snapshot.is_empty(), 30000, true), "Fresh world captures its stable tutorial entry"):
		await finish(); return
	_bind_and_pin()
	var fresh: Dictionary = checkpoint.capture_world(world)
	if not check(not fresh.is_empty(), "Fresh world provides a complete checkpoint fixture"):
		await finish(); return
	var targets: Dictionary = fresh.start_state.tutorial.workshop.targets.duplicate(true)
	var empty_workshop: Dictionary = fresh.start_state.tutorial.workshop.duplicate(true)
	var legacy := fresh.duplicate(true)
	_strip_stock(legacy, targets)
	_strip_stock(legacy.start_state.tutorial.entry_snapshot, targets)
	# These fields existed in v1. Distinct current and entry progress make a
	# mistaken recapture of the current player state visible after migration.
	legacy.start_state.tutorial.flags.viewed = true
	legacy.start_state.tutorial.flags.marker_index = 1
	legacy.player.health = 73.0
	legacy.player.stamina = 51.0
	var legacy_entry: Dictionary = legacy.start_state.tutorial.entry_snapshot.duplicate(true)
	check(legacy.actors.size() == fresh.actors.size() - 6 and legacy_entry.actors.size() == fresh.start_state.tutorial.entry_snapshot.actors.size() - 6, "Truthful v1 fixture removes exactly the six workshop supplies from both worlds")
	if not check(checkpoint.validation_error(legacy).is_empty(), "Original tutorial v1 current and independent entry validate"):
		await finish(); return
	if not check(checkpoint.write_checkpoint(SAVE_PATH, legacy), "Original manual v1 save writes before migration"):
		await finish(); return
	source_bytes = FileAccess.get_file_as_bytes(SAVE_PATH)
	var decoded: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	check(decoded == legacy, "Reading the original manual save retains v1 without implicit grants")
	checkpoint.file_operations = files
	if not check(await checkpoint.load_snapshot(world, decoded), "Actual v1 snapshot load replaces the current world"):
		await finish(); return
	world = current_scene
	_bind_and_pin()
	var applied: Dictionary = checkpoint.capture_world(world)
	var applied_preserved: bool = not applied.is_empty() and applied.player == legacy.player and _restored_vehicles_match(applied.vehicles, legacy.vehicles)
	if not applied_preserved and not applied.is_empty():
		_differences(applied.player, legacy.player, "v1.player")
		_differences(applied.vehicles, legacy.vehicles, "v1.vehicles")
	check(applied_preserved, "Transactional v1 load retains saved player and RV state before migration")
	check(not world.has_meta("checkpoint_staging") and world.play_ready, "Migration candidate enters the live ready world")
	if not check(await _settle(), "Deferred migration prepares the workshop and upgrades the old entry"):
		await finish(); return
	var upgraded: Dictionary = checkpoint.capture_world(world)
	if not check(not upgraded.is_empty() and checkpoint.validation_error(upgraded).is_empty(), "Migrated current and entry checkpoint validate"):
		await finish(); return
	check(upgraded.version == 5 and upgraded.start_state.tutorial.version == 3, "Migration upgrades only tutorial state and retains outer checkpoint v5")
	check(upgraded.start_state.phase == legacy.start_state.phase and upgraded.start_state.tutorial.stage == legacy.start_state.tutorial.stage, "Migration preserves the original preparation phase and stage")
	check(upgraded.start_state.tutorial.flags == legacy.start_state.tutorial.flags, "Migration preserves partial first-lesson progress")
	for field in ["terminal_id", "rv_id", "flashlight_id"]:
		check(upgraded.start_state.tutorial[field] == legacy.start_state.tutorial[field], "Migration preserves designated " + field)
	check(upgraded.start_state.tutorial.workshop == empty_workshop, "Migration creates stock references without granting workshop progress")
	check(upgraded.start_state.tutorial.service == fresh.start_state.tutorial.service and not upgraded.start_state.tutorial.service.configured, "Migration starts service training with blank progress and no new grants")
	var upgraded_entry: Dictionary = upgraded.start_state.tutorial.entry_snapshot
	check(upgraded_entry.start_state.tutorial.workshop.targets == targets and upgraded.start_state.tutorial.workshop.targets == targets, "Current and entry use the same deterministic designated supplies")
	check(not upgraded_entry.start_state.tutorial.has("entry_snapshot"), "Migrated entry has no stale nested retry snapshot")
	var original_boundary := upgraded_entry.duplicate(true)
	_strip_stock(original_boundary, targets)
	check(original_boundary == legacy_entry, "Adding stock preserves the precise original entry player, RV, actors, IDs and progress")
	_check_stock(upgraded, targets, "Migrated current", legacy.actors.size())
	_check_stock(upgraded_entry, targets, "Migrated entry", legacy_entry.actors.size())
	_check_manual(upgraded, legacy, "Migrated current")
	_check_manual(upgraded_entry, legacy_entry, "Migrated entry")
	if not check(await checkpoint.load_snapshot(world, upgraded), "Upgraded current checkpoint loads through the actual transaction"):
		await finish(); return
	world = current_scene
	_bind_and_pin()
	if not check(await _settle(), "Reloaded v3 world settles without migration"):
		await finish(); return
	var reloaded: Dictionary = checkpoint.capture_world(world)
	check(not reloaded.is_empty() and checkpoint.validation_error(reloaded).is_empty(), "Reloaded v3 checkpoint remains valid")
	if reloaded.is_empty(): await finish(); return
	check(reloaded.start_state.tutorial.workshop == upgraded.start_state.tutorial.workshop and tutorial.entry_snapshot == upgraded_entry, "V3 reload retains exact workshop IDs and the upgraded original entry")
	_check_stock(reloaded, targets, "Reloaded current", legacy.actors.size())
	if not check(await tutorial.restart_stage(), "Real Restart Stage loads the upgraded independent entry"):
		await finish(); return
	world = current_scene
	_bind_and_pin()
	var retried: Dictionary = checkpoint.capture_world(world)
	var retry_preserved: bool = not retried.is_empty() and retried.player == legacy_entry.player and _restored_vehicles_match(retried.vehicles, legacy_entry.vehicles)
	if not retry_preserved and not retried.is_empty():
		_differences(retried.player, legacy_entry.player, "retry.player")
		_differences(retried.vehicles, legacy_entry.vehicles, "retry.vehicles")
	check(retry_preserved, "Retry restores original entry player and RV state")
	if not check(await _settle(), "Restarted entry settles without a second stock grant"):
		await finish(); return
	retried = checkpoint.capture_world(world)
	check(not retried.is_empty() and checkpoint.validation_error(retried).is_empty(), "Restarted world and preserved entry validate")
	if retried.is_empty(): await finish(); return
	check(tutorial.flags == legacy_entry.start_state.tutorial.flags and tutorial.entry_snapshot == upgraded_entry, "Retry restores the older first-lesson progress and retains its original upgraded boundary")
	check(workshop.capture() == empty_workshop, "Retry retains deterministic targets without fabricated workshop progress")
	_check_stock(retried, targets, "Restarted current", legacy_entry.actors.size())
	_check_manual(retried, legacy_entry, "Restarted current")
	check(files.writes == 0 and FileAccess.get_file_as_bytes(SAVE_PATH) == source_bytes, "Migration, v3 reload and retry perform zero writes to the original manual save")
	await finish()

func _restored_vehicles_match(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size(): return false
	var normalized := actual.duplicate(true)
	for index in actual.size():
		var devices: Array = normalized[index].mounted_items
		var original: Array = expected[index].mounted_items
		if devices.size() != original.size(): return false
		for device in devices.size():
			var pose: Transform3D = devices[device].transform
			var saved_pose: Transform3D = original[device].transform
			# Restoring mounts converts local -> world -> local. At the shelter's
			# distant origin this produces ~0.000031 m single-precision roundoff.
			if pose.origin.distance_to(saved_pose.origin) > 0.0001: return false
			for axis in range(3):
				if pose.basis[axis].distance_to(saved_pose.basis[axis]) > 0.000001: return false
			devices[device].transform = saved_pose
	# Only proven mount-pose roundoff is tolerated; every other field is exact.
	return normalized == expected

func _differences(actual: Variant, expected: Variant, path: String) -> void:
	if actual == expected: return
	if actual is Dictionary and expected is Dictionary:
		for key in actual:
			if not expected.has(key): print("MIGRATION_DIFF ", path, ".", key, " unexpected")
			else: _differences(actual[key], expected[key], path + "." + str(key))
		for key in expected:
			if not actual.has(key): print("MIGRATION_DIFF ", path, ".", key, " missing")
	elif actual is Array and expected is Array:
		if actual.size() != expected.size(): print("MIGRATION_DIFF ", path, " size actual=", actual.size(), " expected=", expected.size())
		for index in mini(actual.size(), expected.size()): _differences(actual[index], expected[index], path + "[%d]" % index)
	elif actual is Transform3D and expected is Transform3D:
		print("MIGRATION_DIFF ", path, " transform origin_delta=%.12f basis_x_delta=%.12f basis_y_delta=%.12f basis_z_delta=%.12f" % [actual.origin.distance_to(expected.origin), actual.basis.x.distance_to(expected.basis.x), actual.basis.y.distance_to(expected.basis.y), actual.basis.z.distance_to(expected.basis.z)])
	else:
		print("MIGRATION_DIFF ", path, " actual=", actual, " expected=", expected)

func _check_stock(snapshot: Dictionary, targets: Dictionary, label: String, original_count: int) -> void:
	check(snapshot.actors.size() == original_count + 6, label + " contains exactly six added actors and retains all original stock")
	var owners := snapshot.duplicate()
	owners.erase("start_state")
	check(ItemState.unique_ids(owners, {}), label + " preserves unique Item ownership independently of retry references")
	var designated: Dictionary = {}
	for key in STOCK:
		var identity: String = targets[key]
		check(not designated.has(identity), label + " supply identities are mutually unique: " + key)
		designated[identity] = true
		var found: Array = snapshot.actors.filter(func(actor): return actor.get("state", {}).get("id", "") == identity)
		if not check(found.size() == 1, label + " owns exactly one " + key): continue
		var actor: Dictionary = found[0]
		check(actor.scene == STOCK[key] and actor.kind == "item" and not actor.fixed and WorldActorSnapshot.validation_error(actor, "stock").is_empty(), label + " restores the correct ordinary " + key + " scene and state")
		if key == "battery": check(actor.state.battery.id == identity and actor.state.battery.charge == 60.0, label + " reserve battery retains its marked ID and usable charge")
		if key in ["scrap_a", "scrap_b"]: check(actor.state.scrap_yields == {"Metal Parts": Vector2(3, 3)}, label + " scrap retains deterministic materials")
		if key == "barrel": check(actor.state.scrap_yields == {"Metal Parts": Vector2(2, 2), "Unrefined Fuel": Vector2(10, 10)}, label + " barrel retains deterministic recipe supplies")

func _check_manual(snapshot: Dictionary, original: Dictionary, label: String) -> void:
	var terminal_id: String = original.start_state.tutorial.terminal_id
	for vehicle: Dictionary in snapshot.vehicles:
		for actor: Dictionary in vehicle.mounted_items:
			if actor.state.id == terminal_id:
				check(actor.state.training_terminal == {"version": 1, "manual_unlocked": false, "completion": "locked"}, label + " keeps the designated manual locked")
				return
	check(false, label + " retains the designated manual Item")

func finish() -> void:
	checkpoint.file_operations = CheckpointFiles.new()
	check(await WAIT.retired_candidates(self, checkpoint, 30000), "Checkpoint staging viewports retire before teardown")
	if is_instance_valid(world):
		world.get_node("WorldGenerator").set_process(false)
		check(await WAIT.generator_idle(self, world.get_node("WorldGenerator"), 30000), "World generation finishes before teardown")
		check(await WAIT.navigation_bakes_finished(self, world, 30000), "Navigation bakes finish before teardown")
		world.queue_free()
		# Delete at the frame boundary, then let native physics/navigation/render
		# disposal commands drain before shutting down the SceneTree servers.
		for tick in 4:
			await physics_frame
			await process_frame
	if failures.is_empty(): print("PASS: real v1 tutorial migration, exact original entry and one-time stock grants")
	quit(0 if failures.is_empty() else 1)
