extends SceneTree
## Real v10 checkpoint transactions, compatibility, staging and rear wreck geometry.
const WAIT = preload("res://tests/support/test_wait.gd")
const PRESSURE = preload("res://world/deviation_pressure.gd")
const REAR = preload("res://world/starting_shelter/rear_wreck_layout.gd")
const SAVE_PATH := "res://.godot/test-deviation-pressure-checkpoint.save"
var failures: Array[String] = []
var staging_expected: Dictionary = {}
var staging_frames := 0

func _init() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func settle(world: Node) -> bool:
	return await WAIT.generator_idle(self, world.get_node("WorldGenerator")) and await WAIT.retired_candidates(self, root.get_node("Checkpoint"))

func freeze_fixture(world: Node) -> void:
	world.get_node("WorldGenerator").set_process(false)
	world.get_node("Player").set_physics_process(false)
	world.get_node("DeviationPressure").set_physics_process(false)
	world.get_node("WorldClock").running = false
	for actor in get_nodes_in_group(Groups.MONSTERS):
		if WorldEntities.same_world(world, actor): actor.process_mode = Node.PROCESS_MODE_DISABLED
	for rv in get_nodes_in_group(Groups.CHASSIS):
		if WorldEntities.same_world(world, rv):
			rv.freeze = true
			rv.set_physics_process(false)

func observe_staging() -> void:
	if staging_expected.is_empty(): return
	for viewport in root.get_node("Checkpoint").get_children():
		if not viewport is SubViewport: continue
		for candidate in viewport.get_children():
			var director := candidate.get_node_or_null("DeviationPressure")
			if director == null or not director.is_node_ready(): continue
			staging_frames += 1
			check(director.capture() == staging_expected, "Candidate director does not advance, emit waves or change RNG during staging")

func count_monsters(world: Node) -> int:
	return get_nodes_in_group(Groups.MONSTERS).filter(func(actor): return WorldEntities.same_world(world, actor) and not actor.is_queued_for_deletion()).size()

func run() -> void:
	var checkpoint: Node = root.get_node("Checkpoint")
	var world: Node3D = load("res://world/main_world.tscn").instantiate()
	var generator: Node = world.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = generator.profile.duplicate()
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 1
	root.add_child(world)
	current_scene = world
	if not await world.wait_for_play() or not await settle(world):
		check(false, "Pressure checkpoint production fixture becomes ready")
		quit(1)
		return
	freeze_fixture(world)
	check(checkpoint.save_world(world, SAVE_PATH), "Fresh v10 pressure checkpoint writes")
	var initial: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	if initial.is_empty(): world.free(); quit(1); return
	check(initial.version == 5 and initial.generation_version == 10, "Checkpoint format stays v5 and generation stays v10")
	check(initial.has_all(["route_pressure", "rear_wreck_layout", "weather", "generated_giant_segments"]), "Save includes pressure and rear geometry beside existing weather and giant ledger")
	for record in ["route_pressure", "rear_wreck_layout"]:
		for malformed in [null, "invalid", {"version": 999}]:
			var bad := initial.duplicate(true)
			bad[record] = malformed
			check(checkpoint.validation_error(bad) == record, "Malformed present %s is rejected rather than discarded" % record)
			check(checkpoint.write_checkpoint(SAVE_PATH + ".invalid", bad), "Malformed fixture reaches the real read boundary")
			check(checkpoint.read_checkpoint(SAVE_PATH + ".invalid").is_empty() and checkpoint.last_error.field == record, "Read rejects malformed %s before preparing a world" % record)
	var floating := initial.duplicate(true)
	floating.rear_wreck_layout.placements[0].transform.origin.y += 2.0
	check(checkpoint.validation_error(floating) == "rear_wreck_layout", "Finite but unsupported saved wreck transform is rejected")
	floating = initial.duplicate(true)
	floating.rear_wreck_layout.walkway[3].y += 2.0
	check(checkpoint.validation_error(floating) == "rear_wreck_layout", "Saved walkway height must match deterministic ground")
	for version in [7, 8, 9]:
		var old_generation := initial.duplicate(true)
		old_generation.generation_version = version
		old_generation.profile.generation_version = version
		old_generation.route_pressure = "ignored legacy field"
		old_generation.rear_wreck_layout = "ignored legacy field"
		check(checkpoint.validation_error(old_generation).is_empty(), "v%d does not interpret v10 extension records" % version)
	# An old v10 checkpoint may stand inside the former solid rear car pile.
	# Its restored player/RV/items must reserve their actual collision footprints
	# before the replacement wreck plan is built in the candidate world.
	var legacy := initial.duplicate(true)
	legacy.erase("route_pressure")
	legacy.erase("rear_wreck_layout")
	legacy.player.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 20))
	var old_supported_id := ""
	for actor: Dictionary in legacy.actors:
		if actor.scene != "res://props/flashlight.tscn": continue
		actor.transform.origin = Vector3(8, 3, 20)
		actor.fixed = true
		actor.support = {"kind": "static", "path": "WorldGenerator/Band_-1/Roadblock/Collision"}
		old_supported_id = actor.state.id
		break
	check(not old_supported_id.is_empty(), "Migration fixture includes Item mounted on removed old rear support")
	check(checkpoint.validation_error(legacy).is_empty(), "Old v10 missing both optional fields remains valid")
	check(checkpoint.write_checkpoint(SAVE_PATH + ".legacy", legacy), "Old v10 fixture writes")
	if not await checkpoint.load_world(world, SAVE_PATH + ".legacy"):
		check(false, "Old v10 checkpoint loads through production transaction")
		world.free(); quit(1); return
	world = current_scene
	freeze_fixture(world)
	if not await settle(world):
		check(false, "Old v10 replacement terrain settles")
		world.free(); quit(1); return
	generator = world.get_node("WorldGenerator")
	check(world.get_node("Player").global_transform.is_equal_approx(legacy.player.transform), "Old v10 restore preserves player near former car bodies")
	check(not generator.rear_wreck_layout.is_empty() and REAR.valid_state(generator.rear_wreck_layout), "Old v10 plans and retains valid replacement wreck geometry")
	check_rear_collision_clear(world, legacy)
	var detached := false
	for actor in WorldEntities.get_container(world).get_children():
		if actor is Item and actor.persistent_id == old_supported_id:
			detached = not actor.is_fixed and actor.mount_support == null
	check(detached, "Old rear Item loses missing support without rebinding to relocated wreck")
	var director: Node = world.get_node("DeviationPressure")
	world.get_node("StartRun").restore({"version": 1, "phase": "sealed"})
	director._physics_process(0.0)
	check(PRESSURE.valid_state(director.capture()) and director.state.initialized, "Missing pressure initializes after actual restored placement")
	var actual := RoutePressureSample.sample(generator.field, legacy.player.transform.origin)
	check(is_equal_approx(director.state.highwater, maxf(actual.progress, 45.0)) and is_equal_approx(director.state.origin, 45.0), "Old v10 route origin is 45 m and highwater comes from actual saved placement")
	check(checkpoint.save_world(world, SAVE_PATH), "Migrated v10 state can be saved")
	var migrated: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	check(migrated.weather == legacy.weather and migrated.generated_giant_segments == legacy.generated_giant_segments, "Migration preserves natural weather and giant generation ledger")
	await test_rear_persistence(world, migrated)
	world = current_scene
	await test_controller_guards(world)
	await test_event_roundtrip(world)
	world = current_scene
	world.free()
	await process_frame
	if failures.is_empty(): print("PASS: v10 optional checkpoint migration, pressure state, staging and rear wreck persistence")
	quit(0 if failures.is_empty() else 1)

func test_rear_persistence(world: Node3D, saved: Dictionary) -> void:
	var generator: Node = world.get_node("WorldGenerator")
	for entry in generator.active_chunks.duplicate():
		if entry.index == -1: generator.retire_band(entry)
	await process_frame
	check(root.get_node("Checkpoint").save_world(world, SAVE_PATH), "Checkpoint saves with rear chunk unloaded")
	var unloaded: Dictionary = root.get_node("Checkpoint").read_checkpoint(SAVE_PATH)
	check(unloaded.get("rear_wreck_layout") == saved.rear_wreck_layout, "Unloading rear chunk retains its exact placement plan")
	if not await root.get_node("Checkpoint").load_world(world, SAVE_PATH):
		check(false, "Checkpoint with unloaded rear chunk reloads")
		return
	world = current_scene
	freeze_fixture(world)
	generator = world.get_node("WorldGenerator")
	await generator._spawn_band(-1, true)
	check(await settle(world), "Revisited rear chunk finishes navigation")
	check(generator.rear_wreck_layout == saved.rear_wreck_layout, "Reload and revisit rebuild rear wrecks without rerolling placement")

func check_rear_collision_clear(world: Node3D, saved: Dictionary) -> void:
	var exclusions: Array[AABB] = REAR.exclusions_for_checkpoint(saved)
	var inspected := 0
	for entry in world.get_node("WorldGenerator").active_chunks:
		if entry.index != -1: continue
		for node in entry.node.find_children("*", "Node3D", true, false):
			if node.scene_file_path != "res://world/starting_shelter/reused_wreck.tscn": continue
			for collision in node.find_children("*", "CollisionShape3D", true, false):
				if collision.disabled or not collision.shape is BoxShape3D: continue
				var size: Vector3 = collision.shape.size
				var actual_body: AABB = collision.global_transform * AABB(-size * 0.5, size)
				inspected += 1
				for exclusion in exclusions:
					check(not actual_body.intersects(exclusion), "Migrated rear wreck actual body clears saved player, RV and item collision footprints")
	check(inspected > 0, "Migration checks real car collision bodies rather than decorative origins")

func test_controller_guards(world: Node3D) -> void:
	var director: DeviationPressure = world.get_node("DeviationPressure")
	var generator: Node = world.get_node("WorldGenerator")
	var player = world.get_node("Player")
	var start: StartRun = world.get_node("StartRun")
	director.state.initialize(500.0, 45.0)
	director.state.advance(11.0, {"progress": 200.0, "forest_offset": 0.0, "exempt": false, "progress_valid": true})
	var saved := director.capture()
	var count := count_monsters(world)
	start.restore({"version": 1, "phase": "preparing"})
	director._physics_process(40.0)
	check(director.capture() == saved, "Preparation freezes event and spawn clocks")
	start.restore({"version": 1, "phase": "sealed"})
	world.play_ready = false
	director._physics_process(40.0)
	world.play_ready = true
	check(director.capture() == saved, "Readiness gate freezes encounter")
	generator.restoring_entities = true
	director._physics_process(40.0)
	generator.restoring_entities = false
	check(director.capture() == saved, "Entity restore gate freezes encounter")
	player.is_player_dead = true
	director._physics_process(40.0)
	player.is_player_dead = false
	check(director.capture() == saved, "Death freezes encounter")
	var captor := Node3D.new()
	world.add_child(captor)
	player.grab_control.captor = captor
	director._physics_process(40.0)
	player.grab_control.captor = null
	captor.free()
	check(director.capture() == saved, "Grab ownership freezes encounter")
	world.get_node("PoiInstances").busy = true
	director._physics_process(40.0)
	world.get_node("PoiInstances").busy = false
	check(director.capture() == saved and world.get_node("WorldClock").deviation_fog == 0.0, "Transition freezes event and releases outdoor fog")
	paused = true
	director.set_physics_process(true)
	for step in range(10): await process_frame
	director.set_physics_process(false)
	paused = false
	check(director.capture() == saved and count_monsters(world) == count, "Paused production controller neither advances nor creates actors")
	world.get_node("WorldClock").running = false
	director.restore(saved)
	check(world.get_node("WorldClock").deviation_fog == saved.timing.fog, "Restored fog immediately reaches clock without advancing time")

func test_event_roundtrip(world: Node3D) -> void:
	var checkpoint: Node = root.get_node("Checkpoint")
	var director: Node = world.get_node("DeviationPressure")
	director.state.initialize(500.0, 45.0)
	var danger := {"progress": 200.0, "forest_offset": 0.0, "exempt": false, "progress_valid": true}
	director.state.advance(RoutePressureState.ENTRY_SECONDS + RoutePressureState.FIRST_WAVE, danger)
	check(director.state.pending_rakers == 2, "Checkpoint fixture reaches the first real pressure wave")
	# One member has already been emitted; its physical actor and the remaining
	# retry are separate owners and both must survive a transaction exactly once.
	var raker: Node3D = load("res://enemies/raker.tscn").instantiate()
	raker.position = Vector3(60, 2, 70)
	raker.process_mode = Node.PROCESS_MODE_DISABLED
	WorldEntities.get_container(world).add_child(raker)
	director.state.resolve_raker_wave(1)
	director.rng.seed = 123456
	director.rng.randf()
	director._rng_initialized = true
	check(checkpoint.save_world(world, SAVE_PATH + ".wave"), "Partially emitted pressure wave writes")
	var wave: Dictionary = checkpoint.read_checkpoint(SAVE_PATH + ".wave")
	if wave.is_empty(): return
	var before := count_monsters(world)
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.state = wave.route_pressure.rng_state
	var expected_roll := expected_rng.randi()
	for key in ["rng_state", "rng_initialized", "timing"]:
		var malformed := wave.duplicate(true)
		malformed.route_pressure[key] = "invalid"
		check(checkpoint.validation_error(malformed) == "route_pressure", "Checkpoint validates director %s type" % key)
	staging_expected = wave.route_pressure.duplicate(true)
	staging_frames = 0
	process_frame.connect(observe_staging)
	var loaded: bool = await checkpoint.load_world(world, SAVE_PATH + ".wave")
	process_frame.disconnect(observe_staging)
	staging_expected = {}
	check(loaded, "Partial wave loads through real staging transaction")
	if not loaded: return
	world = current_scene
	freeze_fixture(world)
	check(await settle(world), "Restored pressure wave terrain settles")
	director = world.get_node("DeviationPressure")
	check(staging_frames > 0, "Regression observes the candidate director during staging")
	check(director.capture() == wave.route_pressure, "Partial wave timers, fog, highwater and RNG roundtrip exactly")
	check(director.state.pending_rakers == 1 and director.state.wave_ordinal == 1 and is_equal_approx(director.state.retry_rakers, RoutePressureState.RETRY_SECONDS), "Restore keeps only the unemitted wave member and its retry")
	check(count_monsters(world) == before, "Loading partial wave restores its emitted actor without duplicates")
	check(director.rng.randi() == expected_roll, "Restored director resumes the saved RNG stream")
	director.rng.state = wave.route_pressure.rng_state
	director._physics_process(0.0)
	check(director.capture() == wave.route_pressure and count_monsters(world) == before, "First ready tick does not restart a partially emitted wave")
	check(is_equal_approx(world.get_node("WorldClock").deviation_fog, wave.route_pressure.timing.fog), "Restored active pressure fog reaches production clock composition")
	# Recover to a genuinely fading event with its cooldown already in progress.
	var safe := {"progress": 500.0, "forest_offset": 0.0, "exempt": false, "progress_valid": true}
	director.state.advance(RoutePressureState.EXIT_SECONDS + 2.0, safe)
	check(not director.state.active and director.state.fog > 0.0 and director.state.cooldown > 0.0, "Checkpoint fixture reaches fog recovery and live cooldown")
	check(checkpoint.save_world(world, SAVE_PATH + ".cooldown"), "Fading fog and cooldown checkpoint writes")
	var cooling: Dictionary = checkpoint.read_checkpoint(SAVE_PATH + ".cooldown")
	if not await checkpoint.load_world(world, SAVE_PATH + ".cooldown"):
		check(false, "Fading fog and cooldown checkpoint reloads")
		return
	world = current_scene
	freeze_fixture(world)
	check(await settle(world), "Restored cooldown terrain settles")
	director = world.get_node("DeviationPressure")
	check(director.capture() == cooling.route_pressure, "Fade source, remaining fade and cooldown restore exactly")
	check(count_monsters(world) == before, "Recovered checkpoint preserves existing actors without a new event")
	var reference := RoutePressureState.new()
	check(reference.restore(cooling.route_pressure.timing), "Restored cooldown supplies a valid pure timing state")
	reference.advance(1.0, danger)
	director.state.advance(1.0, danger)
	check(director.state.capture() == reference.capture() and not director.state.rakers_due() and not director.state.giant_due(), "Restored cooldown resumes timing without duplicate spawns")
