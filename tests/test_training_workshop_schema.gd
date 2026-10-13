extends SceneTree
## Tutorial v1 compatibility and strict v2 workshop references, independent of live Items.
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _workshop() -> Dictionary:
	return {
		"version": 1,
		"targets": {"battery": "training-battery", "original_battery": "rv-battery", "socket": "rv-socket", "tablet": "rv-tablet", "scrapper": "training-scrapper", "workbench": "training-workbench", "scrap_a": "scrap-a", "scrap_b": "scrap-b", "barrel": "training-barrel"},
		"flags": {"battery": false, "overview": false, "energy": false, "equipment": false, "lights_off": false, "lights_on": false, "cancelled": false, "scrapper_placed": false, "workbench_placed": false, "remounted": false},
		"placed_ids": [], "unmounted_ids": [], "recycled_ids": [], "output_ids": [], "gasoline_id": ""
	}

func _tutorial(version: int = 2) -> Dictionary:
	var state := {"version": version, "stage": 1, "status": "active", "terminal_id": "terminal", "rv_id": "rv", "flashlight_id": "flashlight", "flags": {"viewed": false, "flashlight": false, "marker_index": 0, "reversed": false, "parked": false}}
	if version == 2: state["workshop"] = _workshop()
	return state

func _run() -> void:
	var fresh := _tutorial()
	check(CheckpointSchema.tutorial_error(fresh).is_empty(), "Fresh v2 stage-one workshop is valid")
	for stage in range(2, 8):
		var progress := fresh.duplicate(true)
		progress.stage = stage
		for key in progress.workshop.flags: progress.workshop.flags[key] = true
		progress.workshop.placed_ids = ["training-scrapper", "training-workbench"]
		progress.workshop.unmounted_ids = ["training-workbench", "training-scrapper"]
		progress.workshop.recycled_ids = ["scrap-a", "scrap-b", "training-barrel"]
		progress.workshop.output_ids = ["crafted-gasoline", "crafted-cabin-light"]
		progress.workshop.gasoline_id = "crafted-gasoline"
		check(CheckpointSchema.tutorial_error(progress).is_empty(), "Stage %d retains full workshop progress without requiring live target Items" % stage)
	for status in ["active", "completed", "skipped"]:
		var state := fresh.duplicate(true)
		state.status = status
		check(CheckpointSchema.tutorial_error(state).is_empty(), "V2 accepts explicit status: " + status)
	for stage in [1, 2]:
		var legacy := _tutorial(1)
		legacy.stage = stage
		check(CheckpointSchema.tutorial_error(legacy).is_empty(), "Original v1 stage %d remains valid without workshop" % stage)
	var old_with_workshop := _tutorial(1)
	old_with_workshop["workshop"] = _workshop()
	check(not CheckpointSchema.tutorial_error(old_with_workshop).is_empty(), "V1 cannot silently contain v2 workshop data")
	var old_later_stage := _tutorial(1)
	old_later_stage.stage = 3
	check(CheckpointSchema.tutorial_error(old_later_stage) == "stage", "V1 retains its original two-stage bound")
	var unknown := _tutorial(3)
	check(CheckpointSchema.tutorial_error(unknown) == "version", "Unknown tutorial v3 is rejected")
	var missing := fresh.duplicate(true)
	missing.erase("workshop")
	check(not CheckpointSchema.tutorial_error(missing).is_empty(), "V2 requires complete workshop state")
	for kind in ["type", "missing", "unknown", "version_type", "version", "target_type", "target_missing", "target_unknown", "target_empty", "target_id_type", "flags_type", "flags_missing", "flags_unknown", "flag_type", "placed_unknown", "unmounted_unknown", "recycled_unknown", "output_target", "gasoline_type", "gasoline_unknown"]:
		var bad := _workshop()
		match kind:
			"type":
				check(not CheckpointSchema.workshop_error([]).is_empty(), "Reject non-dictionary workshop")
				continue
			"missing": bad.erase("gasoline_id")
			"unknown": bad["unknown"] = false
			"version_type": bad.version = 1.0
			"version": bad.version = 2
			"target_type": bad.targets = []
			"target_missing": bad.targets.erase("socket")
			"target_unknown": bad.targets["unknown"] = "other"
			"target_empty": bad.targets.battery = ""
			"target_id_type": bad.targets.battery = 9
			"flags_type": bad.flags = []
			"flags_missing": bad.flags.erase("battery")
			"flags_unknown": bad.flags["unknown"] = false
			"flag_type": bad.flags.cancelled = 1
			"placed_unknown": bad.placed_ids = ["other-equipment"]
			"unmounted_unknown": bad.unmounted_ids = ["other-equipment"]
			"recycled_unknown": bad.recycled_ids = ["other-scrap"]
			"output_target": bad.output_ids = [bad.targets.battery]
			"gasoline_type": bad.gasoline_id = 0
			"gasoline_unknown": bad.gasoline_id = "unrecorded-gasoline"
		check(not CheckpointSchema.workshop_error(bad).is_empty(), "Reject malformed workshop: " + kind)
	for field in ["placed_ids", "unmounted_ids", "recycled_ids", "output_ids"]:
		for kind in ["type", "empty", "id_type", "duplicate", "overflow"]:
			var bad := _workshop()
			var identity := "new-output" if field == "output_ids" else ("scrap-a" if field == "recycled_ids" else "training-scrapper")
			match kind:
				"type": bad[field] = {}
				"empty": bad[field] = [""]
				"id_type": bad[field] = [10]
				"duplicate": bad[field] = [identity, identity]
				"overflow":
					var maximum := 64 if field == "output_ids" else (3 if field == "recycled_ids" else 2)
					for index in range(maximum + 1): bad[field].append("output-%d" % index)
			check(not CheckpointSchema.workshop_error(bad).is_empty(), "Reject %s %s" % [field, kind])
	var maximum_outputs := _workshop()
	for index in range(64): maximum_outputs.output_ids.append("output-%d" % index)
	maximum_outputs.gasoline_id = "output-63"
	check(CheckpointSchema.workshop_error(maximum_outputs).is_empty(), "Bounded output ledger supports 64 products and a recorded gasoline reference")
	var existing_output := fresh.duplicate(true)
	existing_output.workshop.output_ids = [existing_output.flashlight_id]
	check(not CheckpointSchema.tutorial_error(existing_output).is_empty(), "Existing tutorial target cannot become a workshop product")
	if failures.is_empty(): print("PASS: tutorial workshop schema and v1 compatibility")
	quit(0 if failures.is_empty() else 1)
