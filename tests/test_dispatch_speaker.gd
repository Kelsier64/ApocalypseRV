extends SceneTree

class TestCoverage extends DeviationPressure:
	var strength := 1.0
	var sampled_point := Vector3.INF

	func signal_strength_at(point: Vector3) -> float:
		sampled_point = point
		return strength

class TestGenerator extends Node:
	var field := WorldField.new(42, WorldProfile.new())

var failures: Array[String] = []
var world := Node3D.new()
var coverage := TestCoverage.new()

func _init() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	check_coverage()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	coverage.name = "DeviationPressure"
	world.add_child(coverage)
	coverage.set_physics_process(false)
	check_world_sample()
	var recipe := RecipeCatalog.find("dispatch_speaker")
	check(recipe != null and recipe.scene_path == DispatchSpeaker.SCENE, "Fabricator produces the registered speaker")
	check(SaveSceneCatalog.resolve(DispatchSpeaker.SCENE, "item") != null, "Checkpoint catalog accepts speaker")
	for shell_scene: PackedScene in [preload("res://rv/starter_rv.tscn"), preload("res://rv/new_rv.tscn")]:
		var shell := shell_scene.instantiate()
		world.add_child(shell)
		var rv := shell.get_node("Chassis") as Chassis
		rv.freeze = true
		rv.set_physics_process(false)
		await process_frame
		await physics_frame
		var speaker := rv.get_node("DispatchSpeaker") as DispatchSpeaker
		var count := rv.get_equipment().filter(func(device): return device is DispatchSpeaker).size()
		check(count == 1 and speaker.mount_support == rv.get_node("WallFront"), "Both RV presets mount one receiver on their front panel")
		if shell_scene.resource_path.ends_with("new_rv.tscn"):
			check_device(rv, speaker)
			rv.get_node("WallFront").take_damage(rv.get_node("WallFront").max_health)
			await process_frame
			check(not speaker.powered and not speaker.speaker.playing and not speaker.is_fixed, "Destroying the supporting wall drops and silences the receiver")
		else:
			speaker.step_work(0.1)
			speaker.receive()
			speaker.take_damage(speaker.max_health)
			check(not speaker.powered and not speaker.speaker.playing and not speaker.replying, "Zero health interrupts playback")
			speaker.key_handset()
			check(not speaker.replying, "A broken handset cannot answer")
		shell.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: dispatch speaker coverage, power, mounting, controls, audio and removal")
	quit(0 if failures.is_empty() else 1)

func check_coverage() -> void:
	var state := RoutePressureState.new()
	state.initialize(500.0, 0.0)
	var sample := {"progress": state.highwater - state.BACKTRACK_SAFE, "forest_offset": state.FOREST_SAFE, "exempt": false}
	check(state.signal_strength(sample) == 1.0, "Full strength at both safe boundaries")
	for fraction: float in [0.25, 0.5, 0.75, 1.0]:
		sample.progress = state.highwater - lerpf(state.BACKTRACK_SAFE, state.BACKTRACK_START, fraction)
		sample.forest_offset = lerpf(state.FOREST_SAFE, state.FOREST_START, fraction * 0.5)
		check(is_equal_approx(state.signal_strength(sample), 1.0 - fraction), "Backtracking is the weaker axis")
		sample.progress = state.highwater
		check(is_equal_approx(state.signal_strength(sample), 1.0 - fraction * 0.5), "Forest margin reduces reception independently")
	sample.forest_offset = state.FOREST_START + 1.0
	check(state.signal_strength(sample) == 0.0, "No signal beyond the forest threshold")
	sample.exempt = true
	check(state.signal_strength(sample) == 1.0, "Exempt locations retain full reception")

func check_world_sample() -> void:
	var generator := TestGenerator.new()
	generator.name = "WorldGenerator"
	world.add_child(generator)
	var actual := DeviationPressure.new()
	world.add_child(actual)
	actual.set_physics_process(false)
	var road := generator.field.road_frame(520.0)
	actual.state.initialize(520.0, 0.0)
	check(is_equal_approx(actual.signal_strength_at(road.origin), 1.0), "Generated road has strong reception")
	var far := road.origin + road.basis.x * actual.state.FOREST_START * 2.0
	check(is_zero_approx(actual.signal_strength_at(far)), "Receiver samples the forest in the generated world")
	actual.free()
	generator.free()

func check_device(rv: Chassis, unit: DispatchSpeaker) -> void:
	rv.unlimited_power = false
	rv.current_power = rv.max_power
	unit.step_work(1.0)
	check(unit.get_status() == "Receiving" and unit.schedule.time_left > 0, "Powered unit schedules the first signal")
	check(unit.power_draw < rv.cabin_light_draw, "Receiver draws less power than one cabin light")
	check(unit.level_db.x < unit.level_db.y and unit.level_db.y < unit.level_db.z, "Three rising volume levels")
	var mic := unit.get_node("HandsetCollision") as CollisionShape3D
	var mic_point := mic.global_position
	check(unit.aims_at_handset(mic_point) and not unit.aims_at_handset(unit.global_position), "Panel and handset have separate aim targets")
	var query := PhysicsRayQueryParameters3D.create(mic_point + unit.global_basis.z, mic_point)
	var hit := unit.get_world_3d().direct_space_state.intersect_ray(query)
	check(hit.get("collider") == unit and unit.aims_at_handset(hit.position), "A real front-facing ray reaches the handset")
	unit.use_panel(unit.global_position)
	check(unit.level == 2, "The default medium position advances to high")
	unit.receive()
	unit.cycle_volume()
	var charge := rv.current_power
	unit.step_work(1.0)
	check(not unit.enabled and unit.schedule.is_stopped() and not unit.speaker.playing and charge == rv.current_power, "Off stops sound, timer and draw")
	unit.use_panel(mic_point)
	check(not unit.replying, "Switched-off unit only clicks")
	unit.cycle_volume()
	check(unit.enabled and unit.level == 0, "Off advances to low")
	unit.cycle_volume()
	rv.current_power = 0
	unit.step_work(1.0)
	unit.key_handset()
	check(not unit.powered and not unit.replying and unit.get_status().begins_with("No power"), "Flat battery prevents reception and local reply")
	rv.current_power = rv.max_power
	charge = rv.current_power
	unit.step_work(1.0)
	check(unit.enabled and unit.level == 1 and is_equal_approx(charge - rv.current_power, unit.power_draw), "Refill preserves volume and resumes metered draw")
	var encounter_rng := coverage.rng.state
	seed(472)
	var expected := randi()
	seed(472)
	unit.receive()
	check(unit.speaker.playing and unit.speaker.stream in unit.schedule.transmissions, "Plays a real scheduled clip")
	coverage.strength = 0.0
	unit._sample()
	unit._process(unit.fade_seconds)
	unit.receive()
	check(not unit.speaker.playing and not unit.schedule.is_stopped() and unit.noise.playing, "Lost signal fades to static and skips the next transmission")
	check(coverage.sampled_point.is_equal_approx(unit.global_position), "Coverage queries the mounted receiver's position")
	coverage.strength = 1.0
	unit._sample()
	unit.receive()
	unit.use_panel(mic_point)
	var first := unit.speaker.stream
	check(unit.replying and first in unit.replies, "Handset interrupts the broadcast with a local voice")
	unit.key_handset()
	check(unit.speaker.stream == first, "Busy handset leaves current reply alone")
	unit.speaker.stop()
	unit.speaker.finished.emit()
	coverage.strength = 0.0
	unit._sample()
	unit.key_handset()
	check(unit.replying and unit.speaker.stream != first, "Distinct alternating local answer works without coverage")
	check(randi() == expected and coverage.rng.state == encounter_rng, "Receiver audio and sampling preserve gameplay RNG")
	unit.detach_from_support()
	check(not unit.powered and unit.schedule.is_stopped() and not unit.speaker.playing and not unit.noise.playing, "Detaching silences every playback layer")
	unit.confirm_placement(unit.global_transform, rv, rv.get_node("WallFront"))
	unit.step_work(0.1)
	unit.key_handset()
	check(unit.replying, "Reattaching restores service")
	unit.cycle_volume()
	var saved := unit.capture_item_state()
	unit.restore_item_state(saved)
	check(unit.enabled and unit.level == 1, "Restoring a powered speaker resets the volume to medium")
	unit.step_work(0.1)
	unit.key_handset()
