extends SceneTree
## Strict service progress and tutorial v3, independent of live actor ownership.
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func _service(configured := false) -> Dictionary:
	return {"version": 1, "configured": configured, "wall_slot": "left_0", "wheel_slot": 0, "engine_id": "engine" if configured else "", "wheel_id": "wheel" if configured else "", "spare_id": "spare" if configured else "", "kit_id": "kit" if configured else "", "fuel_port_id": "fuel-port" if configured else "", "flags": {"wall": false, "engine": false, "removed": false, "wheel": false, "refueled": false, "departure": false}, "fuel_can_id": "", "empty_can_id": "", "fuel_amount": 0.0}

func _tutorial() -> Dictionary:
	return {"version": 3, "stage": 1, "status": "active", "terminal_id": "terminal", "rv_id": "rv", "flashlight_id": "flashlight", "flags": {"viewed": false, "flashlight": false, "marker_index": 0, "reversed": false, "parked": false}, "workshop": {"version": 1, "targets": {"battery": "battery", "original_battery": "original-battery", "socket": "socket", "tablet": "tablet", "scrapper": "scrapper", "workbench": "workbench", "scrap_a": "scrap-a", "scrap_b": "scrap-b", "barrel": "barrel"}, "flags": {"battery": false, "overview": false, "energy": false, "equipment": false, "lights_off": false, "lights_on": false, "cancelled": false, "scrapper_placed": false, "workbench_placed": false, "remounted": false}, "placed_ids": [], "unmounted_ids": [], "recycled_ids": [], "output_ids": [], "gasoline_id": ""}, "service": _service()}

func _run() -> void:
	for stage in range(1, 10):
		var state := _tutorial()
		state.stage = stage
		check(CheckpointSchema.tutorial_error(state).is_empty(), "V3 accepts stage %d before service configuration" % stage)
		state.status = "skipped"
		check(CheckpointSchema.tutorial_error(state).is_empty(), "V3 permits skip at stage %d without retry entry" % stage)
	for field in ["service", "workshop"]:
		var missing := _tutorial()
		missing.erase(field)
		check(not CheckpointSchema.tutorial_error(missing).is_empty(), "V3 requires " + field)
	for stage in [0, 10]:
		var state := _tutorial()
		state.stage = stage
		check(CheckpointSchema.tutorial_error(state) == "stage", "V3 rejects out-of-range stage %d" % stage)
	var old_v2 := _tutorial()
	old_v2.version = 2
	old_v2.erase("service")
	old_v2.stage = 7
	check(CheckpointSchema.tutorial_error(old_v2).is_empty(), "V2 retains stage seven without service")
	old_v2.stage = 8
	check(CheckpointSchema.tutorial_error(old_v2) == "stage", "V2 retains its historical stage bound")
	old_v2.stage = 7
	old_v2["service"] = _service()
	check(CheckpointSchema.tutorial_error(old_v2) == "fields", "V2 cannot silently acquire v3 service data")
	check(CheckpointSchema.service_error(_service()).is_empty(), "Blank service is valid")
	check(CheckpointSchema.service_error(_service(true)).is_empty(), "Configured references remain valid without live actors")
	check(not CheckpointSchema.service_error([]).is_empty(), "Service must be a dictionary")
	for kind in ["missing", "unknown", "version_missing", "version_type", "version", "configured", "wall_slot_type", "wall_slot", "wheel_slot_type", "wheel_slot", "flags_type", "flag_missing", "flag_unknown", "flag_type", "fuel_type", "fuel_nan", "fuel_infinite", "fuel_negative", "duplicate", "wheel_progress", "refuel_amount", "refuel_can", "refuel_empty"]:
		var bad := _service(true)
		match kind:
			"missing": bad.erase("fuel_amount")
			"unknown": bad["unknown"] = false
			"version_missing": bad.erase("version")
			"version_type": bad.version = 1.0
			"version": bad.version = 2
			"configured": bad.configured = 1
			"wall_slot_type": bad.wall_slot = 0
			"wall_slot": bad.wall_slot = "left_1"
			"wheel_slot_type": bad.wheel_slot = 0.0
			"wheel_slot": bad.wheel_slot = 1
			"flags_type": bad.flags = []
			"flag_missing": bad.flags.erase("wall")
			"flag_unknown": bad.flags["extra"] = false
			"flag_type": bad.flags.engine = 1
			"fuel_type": bad.fuel_amount = "1"
			"fuel_nan": bad.fuel_amount = NAN
			"fuel_infinite": bad.fuel_amount = INF
			"fuel_negative": bad.fuel_amount = -1
			"duplicate": bad.spare_id = bad.engine_id
			"wheel_progress": bad.flags.wheel = true
			"refuel_amount":
				bad.flags.refueled = true
				bad.fuel_can_id = "gasoline"
				bad.empty_can_id = "empty"
			"refuel_can":
				bad.flags.refueled = true
				bad.fuel_amount = 1
				bad.empty_can_id = "empty"
			"refuel_empty":
				bad.flags.refueled = true
				bad.fuel_amount = 1
				bad.fuel_can_id = "gasoline"
		check(not CheckpointSchema.service_error(bad).is_empty(), "Reject malformed service: " + kind)
	for field in ["engine_id", "wheel_id", "spare_id", "kit_id", "fuel_port_id", "fuel_can_id", "empty_can_id"]:
		var wrong_type := _service(true)
		wrong_type[field] = 1
		check(not CheckpointSchema.service_error(wrong_type).is_empty(), "Service requires String " + field)
		var nonblank := _service()
		nonblank[field] = "unexpected"
		check(not CheckpointSchema.service_error(nonblank).is_empty(), "Unconfigured service clears " + field)
		if field not in ["fuel_can_id", "empty_can_id"]:
			var empty := _service(true)
			empty[field] = ""
			check(not CheckpointSchema.service_error(empty).is_empty(), "Configured service requires " + field)
	for flag in _service().flags:
		var progress := _service()
		progress.flags[flag] = true
		check(not CheckpointSchema.service_error(progress).is_empty(), "Unconfigured service clears " + flag)
	var blank_fuel := _service()
	blank_fuel.fuel_amount = 1
	check(not CheckpointSchema.service_error(blank_fuel).is_empty(), "Unconfigured service clears fuel amount")
	var finished := _tutorial()
	finished.stage = 9
	finished.service = _service(true)
	for flag in finished.service.flags: finished.service.flags[flag] = true
	finished.service.fuel_can_id = "gasoline"
	finished.service.empty_can_id = "empty"
	finished.service.fuel_amount = 10
	finished.status = "completed"
	check(CheckpointSchema.tutorial_error(finished).is_empty(), "Stage-nine completion retains consumed fuel and removed-wheel progress")
	finished.service.flags.departure = false
	check(not CheckpointSchema.tutorial_error(finished).is_empty(), "Completion requires departure")
	finished.service.flags.departure = true
	finished.stage = 8
	finished.status = "active"
	check(not CheckpointSchema.tutorial_error(finished).is_empty(), "Departure cannot be credited before stage nine")
	if failures.is_empty(): print("PASS: strict tutorial v3 service schema and legacy bounds")
	quit(0 if failures.is_empty() else 1)
