extends "res://tests/test_starting_checkpoint.gd"
## Repeat the real preparation, departure and sealed save/load transactions in v11.
func generation_version() -> int:
	return 11

func prepare_fixture(world: Node) -> void:
	var run: StartRun = world.get_node("StartRun")
	# This inherited suite exercises existing stage-one saves with manual gates.
	# Controller progress and retries have their own production-world suite.
	run.get_node("Tutorial").restore({})
	check(run.shelter.get_meta("poi_definition_id") == &"tutorial_shelter", "v11 production binds the tutorial building")
	check(not run._status.visible, "v11 has no legacy preparation instruction HUD")
	var gates := run.shelter.get_node("Gates")
	for index in range(0, 8, 2): gates.get_child(index).move_to(true)
	check(not root.get_node("Checkpoint").save_world(world, SAVE_PATH), "Moving inner gates reject saving")
	check(await WAIT.until(self, func(): return run.save_block_reason().is_empty(), 10000, true), "Inner gate opening settles")
	var captured := run.capture()
	check(captured.bay_gates == [true, false, true, false, true, false, true, false], "Capture records all eight stable inner gates")
	# Reconstruct only the physical site: StartRun must reapply cached states.
	var replacement: Node3D = load("res://world/tutorial_shelter/tutorial_shelter.tscn").instantiate()
	var parent := run.shelter.get_parent()
	var pose := run.shelter.transform
	run.shelter.free()
	replacement.transform = pose
	parent.add_child(replacement)
	run.bind_shelter(replacement, run.shelter_site)
	check(run.capture().bay_gates == captured.bay_gates, "Site reconstruction retains inner gates")
	var checkpoint := root.get_node("Checkpoint")
	check(checkpoint.save_world(world, SAVE_PATH), "Stable tutorial entry writes")
	var data: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	for invalid in [[], [true], [0, false, true, false, true, false, true, false], "open"]:
		var bad := data.duplicate(true)
		bad.start_state.bay_gates = invalid
		check(checkpoint.validation_error(bad) == "start_state.bay_gates", "Malformed inner gate state rejected")
	data.start_state.erase("bay_gates")
	check(checkpoint.validation_error(data).is_empty(), "Missing optional stage-one gate state remains compatible")

func check_gate_state(world: Node, prepared: Dictionary) -> void:
	var run: StartRun = world.get_node("StartRun")
	check(run.capture().bay_gates == prepared.start_state.bay_gates, "Full v11 checkpoint restores all eight inner gates")
	for index in range(8):
		check(run.shelter.get_node("Gates").get_child(index).is_open() == bool(prepared.start_state.bay_gates[index]), "Restored gate has the saved physical pose")
