extends SceneTree
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_thresholds()
	_test_waves()
	_test_fog_and_cooldown()
	_test_physics_steps()
	_test_snapshots()
	_test_sampling()
	if failures.is_empty():
		print("PASS: route pressure thresholds, real-second timing, bounded snapshots and XZ route exemptions")
		quit(0)
	else:
		for failure in failures: push_error("FAIL: " + failure)
		quit(1)

func _sample(progress: float = 1000.0, forest: float = 0.0, exempt: bool = false, valid: bool = true) -> Dictionary:
	return {"progress": progress, "forest_offset": forest, "exempt": exempt, "progress_valid": valid}

func _state(progress: float = 1000.0) -> RoutePressureState:
	var state := RoutePressureState.new()
	state.initialize(progress, 45.0)
	return state

func _start(state: RoutePressureState, point: Dictionary = _sample(879.0)) -> void:
	state.advance(3.0, point)
	check(state.active and state.exposure == 0.0, "Entry grace starts event without preloading spawn exposure")

func _test_thresholds() -> void:
	var state := _state(0.0)
	check(state.highwater == 45.0, "Highwater is clamped to the signed starting-stop origin")
	state.advance(8.0, _sample(-75.0))
	check(not state.active, "Exactly 120m behind origin does not enter")
	state.advance(2.0, _sample(-75.01))
	check(not state.active, "Negative signed progress is preserved through entry grace")
	state.advance(0.5, _sample(-75.0))
	state.advance(2.9, _sample(-75.01))
	check(not state.active, "Non-deviation interrupts continuous entry grace")
	state.advance(0.1, _sample(-75.01))
	check(state.active and state.reason == "backtrack", "Signed backtracking starts after three continuous seconds")
	state.advance(3.0, _sample(-36.0))
	check(state.active, "81m gap is in the exit hysteresis band")
	state.advance(2.0, _sample(-35.0, 70.0))
	state.advance(1.0, _sample(-35.0, 70.01))
	state.advance(2.9, _sample(-35.0, 70.0))
	check(state.active, "Forest exit boundary also requires continuous safe samples")
	state.advance(0.1, _sample(-35.0, 70.0))
	check(not state.active and state.cooldown == 60.0, "Inclusive 80m/70m safe thresholds exit after three seconds")
	state = _state()
	state.advance(3.0, _sample(1800.0, 100.0, false, false))
	check(not state.active and state.highwater == 1000.0, "Forest threshold is strict and off-route progress cannot raise highwater")
	state.advance(3.0, _sample(1800.0, 100.01, false, false))
	check(state.active and state.reason == "forest", "Forest deviation starts independently of backtracking")
	state.advance(3.0, _sample(45.0, 400.0, true))
	check(not state.active, "Actual POI/route exemptions permit exit even far behind highwater")
	var frozen := state.capture()
	state.advance(0.0, _sample())
	state.advance(-1.0, _sample())
	state.advance(INF, _sample())
	state.advance(1.0, {})
	check(state.capture() == frozen, "Zero, invalid and missing advances preserve paused state")

func _test_waves() -> void:
	var state := _state()
	_start(state)
	state.advance(7.99, _sample(879.0))
	check(not state.rakers_due(), "No raker wave before eight exposure seconds")
	state.advance(0.01, _sample(879.0))
	check(state.rakers_due() and state.pending_rakers == 2 and state.wave_ordinal == 1, "Eight-second wave has two rakers")
	state.resolve_raker_wave(1)
	check(state.pending_rakers == 1 and not state.rakers_due(), "Partial emission retains only its unfilled quota")
	state.advance(1.99, _sample(879.0))
	check(not state.rakers_due(), "Failed/partial wave waits for two seconds")
	state.advance(0.01, _sample(879.0))
	check(state.rakers_due(), "Remaining quota retries after exactly two seconds")
	state.resolve_raker_wave(1)
	check(not state.rakers_due() and state.pending_rakers == 0, "Successful retry does not duplicate already emitted actor")
	state.advance(20.0, _sample(879.0))
	check(state.giant_due(), "Giant becomes due at thirty exposure seconds")
	state.resolve_giant(false)
	check(not state.giant_due(), "Failed giant candidate waits before retry")
	state.advance(2.0, _sample(879.0))
	check(state.giant_due(), "Giant candidate retries after two seconds")
	state.resolve_giant(true)
	check(state.giant_done and not state.giant_due(), "Success or an existing giant resolves this event once")
	state.advance(6.0, _sample(879.0))
	check(state.wave_ordinal == 2 and state.pending_rakers == 2, "Second wave is at eight plus thirty seconds")
	state.resolve_raker_wave(0)
	state.advance(30.0, _sample(879.0))
	check(state.wave_ordinal == 3 and state.pending_rakers == 2 and state.rakers_due(), "Unfilled wave expires when next wave becomes due")
	state.resolve_raker_wave(0, true)
	check(state.pending_rakers == 0 and not state.rakers_due(), "Population cap skips all remaining wave slots")
	state.advance(300.0, _sample(879.0))
	check(state.wave_ordinal == 13 and state.pending_rakers == 2, "Long advance retains only newest wave without catch-up quota")
	check(not state.giant_due(), "Later waves cannot rearm the resolved giant")

func _test_fog_and_cooldown() -> void:
	var state := _state()
	_start(state)
	state.advance(8.0, _sample(879.0))
	check(is_equal_approx(state.fog, 0.5), "Fog reaches light level after eight event seconds")
	state.advance(22.0, _sample(879.0))
	check(state.fog == 1.0, "Fog reaches maximum after thirty event seconds")
	state.advance(3.0, _sample(1000.0))
	check(not state.active and state.exposure == 0.0 and state.pending_rakers == 0 and not state.giant_done, "Safe exit resets all event exposure and quota")
	state.advance(3.0, _sample(879.0))
	check(state.active and is_equal_approx(state.fog, 0.75) and state.exposure == 0.0, "Re-entry retains the current fading fog during cooldown")
	state.advance(20.0, _sample(879.0))
	check(state.fog >= 0.75 and state.exposure == 0.0 and not state.rakers_due(), "Fog grows while cooldown freezes spawn exposure")
	state.advance(37.0, _sample(879.0))
	check(state.cooldown == 0.0 and state.exposure == 0.0, "Cooldown expiry itself cannot preload a wave")
	state.advance(8.0, _sample(879.0))
	check(state.rakers_due() and state.exposure == 8.0, "Fresh spawn exposure starts after cooldown expiry")
	state.advance(3.0, _sample(1000.0))
	state.advance(6.0, _sample(1000.0))
	check(is_equal_approx(state.fog, 0.5), "Exit fog fades linearly over twelve real seconds")
	state.advance(6.0, _sample(1000.0))
	check(state.fog == 0.0 and state.fade_remaining == 0.0, "Exit fog clears at twelve seconds")
	state = _state()
	state.advance(11.0, _sample(879.0))
	check(state.active and state.exposure == 8.0 and state.rakers_due(), "A long frame accounts only for time after entry grace")
	state.advance(5.0, _sample(1000.0))
	check(not state.active and state.cooldown == 58.0 and state.fade_remaining == 10.0, "Safe-exit frame remainder advances fade and new cooldown")

func _test_snapshots() -> void:
	check(RoutePressureState.valid_state(RoutePressureState.new().capture()), "Uninitialized default snapshot is accepted")
	var state := _state()
	_start(state)
	state.advance(30.0, _sample(879.0))
	state.resolve_raker_wave(1)
	state.resolve_giant(false)
	var snapshot := state.capture()
	var restored := RoutePressureState.new()
	check(restored.restore(snapshot) and restored.capture() == snapshot, "Active partial quotas and retries round-trip exactly")
	state.advance(2.0, _sample(879.0))
	restored.advance(2.0, _sample(879.0))
	check(restored.capture() == state.capture(), "Restored timing resumes without duplicate quota")
	for key in snapshot:
		var missing := snapshot.duplicate(true)
		missing.erase(key)
		check(not RoutePressureState.valid_state(missing), "Missing snapshot field rejected: " + key)
	for mutation in [{"fog": NAN}, {"origin": INF}, {"highwater": -100.0}, {"pending_rakers": 3},
		{"pending_rakers": 1.5}, {"wave_ordinal": 9000000000}, {"cooldown": 61.0},
		{"retry_giant": 2.01}, {"exposure": -1.0}, {"initialized": 1}, {"reason": "injected"},
		{"giant_done": true}, {"active": false}, {"fade_remaining": 1.0}, {"cooldown": 10.0}]:
		var invalid := snapshot.duplicate(true)
		invalid.merge(mutation, true)
		var before := restored.capture()
		check(not RoutePressureState.valid_state(invalid) and not restored.restore(invalid), "Invalid snapshot is rejected: " + str(mutation))
		check(restored.capture() == before, "Rejected restore leaves live state intact")
	state.advance(3.0, _sample(1000.0))
	state.advance(2.0, _sample(879.0))
	check(RoutePressureState.valid_state(state.capture()), "Fading entry-grace snapshot is valid")
	var initial := RoutePressureState.new().capture()
	initial.fog = 1.0
	check(not RoutePressureState.valid_state(initial), "Uninitialized snapshot cannot smuggle encounter state")

func _test_physics_steps() -> void:
	var state := _state()
	for step in range(180): state.advance(1.0 / 60.0, _sample(879.0))
	check(state.active, "Three seconds of 60Hz input does not delay entry by a frame")
	for step in range(480): state.advance(1.0 / 60.0, _sample(879.0))
	check(state.rakers_due(), "Eight seconds of 60Hz exposure reaches the wave boundary")
	state.resolve_raker_wave(0)
	for step in range(120): state.advance(1.0 / 60.0, _sample(879.0))
	check(state.rakers_due(), "Two seconds of 60Hz exposure reaches the retry boundary")
	for step in range(1200): state.advance(1.0 / 60.0, _sample(879.0))
	check(state.giant_due(), "Thirty seconds of 60Hz exposure reaches the giant boundary")
	state.resolve_giant(true)
	check(RoutePressureState.valid_state(state.capture()), "Boundary-rounded actor resolution produces a valid snapshot")
	for step in range(180): state.advance(1.0 / 60.0, _sample(1000.0))
	check(not state.active, "Three seconds of 60Hz safe input reaches the exit boundary")
	for step in range(720): state.advance(1.0 / 60.0, _sample(1000.0))
	check(state.fog == 0.0, "Twelve seconds of 60Hz input fully clears fading fog")

func _test_sampling() -> void:
	var profile := WorldProfile.new()
	profile.generation_version = 10
	var field := WorldField.new(42, profile)
	var site := field.stop(3)
	check(site.get("deep_forest", false), "Fixture uses a real deep weaving entrance route")
	for index in range(site.route.size()):
		var point: Vector3 = site.route[index]
		point.y += 400.0
		var sampled := RoutePressureSample.sample(field, point)
		check(sampled.exempt and sampled.progress_valid and sampled.progress == site.s, "Every true weaving-route vertex is exempt in XZ")
		if index > 0:
			point = (site.route[index - 1] + site.route[index]) * 0.5
			check(RoutePressureSample.sample(field, point).exempt, "Actual route segment midpoint is exempt")
	var off_route: Vector3 = site.road * Vector3(float(site.side) * 192.0, 0.0, 0.0)
	var sampled := RoutePressureSample.sample(field, off_route)
	check(not sampled.exempt and not sampled.progress_valid and sampled.forest_offset > 100.0, "Deep course AABB interior away from the polyline is forest deviation")
	var connection: Vector3 = (site.road.origin + site.route[0]) * 0.5
	check(RoutePressureSample.sample(field, connection).exempt, "Road-to-first-route connection is exempt")
	var station := field.stop(1)
	var definition := POIConfig.definition_for_site(station)
	var bounds := definition.site_bounds
	var center := bounds.get_center()
	var building: Transform3D = station.building
	var inside: Vector3 = building * Vector3(bounds.end.x - 0.1, 900.0, center.z)
	check(RoutePressureSample.sample(field, inside).exempt, "Rotated real POI footprint ignores height")
	var outside: Vector3 = building * Vector3(bounds.end.x + 0.1, 0.0, bounds.position.z + 0.1)
	check(not RoutePressureSample.sample(field, outside).exempt, "Rotated footprint does not exempt its enclosing world AABB corners")
	var driveway: Vector3 = (station.road.origin + station.frame.origin) * 0.5
	check(RoutePressureSample.sample(field, driveway).exempt, "Walk-in driveway uses the real road connection")
	var safe := RoutePressureSample.sample(field, field.road_frame(2400.0).origin)
	check(safe.progress_valid and is_equal_approx(safe.progress, 2400.0), "Ordinary road progress is signed longitudinal distance")
	check(safe.backward_direction.y == 0.0 and safe.backward_direction.length() > 0.99, "Backward danger direction follows road frame in XZ")
	check(RoutePressureSample.sample(field, Vector3(INF, 0, 0)).is_empty(), "Invalid sample coordinates are rejected")

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
