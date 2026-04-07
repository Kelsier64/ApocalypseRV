extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_test_navigation_contract_methods_exist()
	_test_climb_contract_methods_exist()
	_test_monster_mantle_target_clearance()
	_test_fallback_direction_is_normalized()
	_test_stuck_progress_gate()
	_test_stuck_threshold_scales_with_delta()
	_test_elevation_gap_gate()
	_test_elevation_assist_velocity_builder()
	_test_vehicle_impact_direction_and_speed_gate()
	_finish()

func _new_monster() -> Node:
	var monster_script: Script = load("res://enemies/monster.gd")
	_expect(monster_script != null, "Monster script should load.")
	if monster_script == null:
		return null
	var monster: Node = monster_script.new()
	_expect(monster != null, "Monster should instantiate.")
	return monster

func _test_navigation_contract_methods_exist() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_resolve_navigation_agent"), "Monster should expose _resolve_navigation_agent().")
	_expect(monster.has_method("_can_use_navigation"), "Monster should expose _can_use_navigation().")
	_expect(monster.has_method("_get_navigation_direction"), "Monster should expose _get_navigation_direction(destination).")
	_expect(monster.has_method("_compute_fallback_direction"), "Monster should expose _compute_fallback_direction(origin, destination).")
	_expect(monster.has_method("_is_progress_too_small"), "Monster should expose _is_progress_too_small(progress, threshold).")
	_expect(monster.has_method("_get_frame_progress_threshold"), "Monster should expose _get_frame_progress_threshold(delta).")
	_expect(monster.has_method("_update_stuck_watchdog"), "Monster should expose _update_stuck_watchdog(delta, moving_intent).")
	_expect(monster.has_method("_can_trigger_stuck_recovery"), "Monster should expose _can_trigger_stuck_recovery().")
	_expect(monster.has_method("_is_elevation_gap_climbable"), "Monster should expose _is_elevation_gap_climbable(gap).")
	_expect(monster.has_method("_build_elevation_assist_velocity"), "Monster should expose _build_elevation_assist_velocity(planar_velocity).")
	_expect(monster.has_method("_build_stuck_recovery_velocity"), "Monster should expose _build_stuck_recovery_velocity(planar_dir, side_sign).")
	_expect(monster.has_method("_compute_vehicle_approach_speed"), "Monster should expose _compute_vehicle_approach_speed(vehicle_velocity, impact_direction).")
	_expect(monster.has_method("_should_apply_vehicle_damage"), "Monster should expose _should_apply_vehicle_damage(vehicle_velocity, impact_direction).")

	monster.free()

func _test_climb_contract_methods_exist() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_try_start_climb"), "Monster should expose _try_start_climb(destination).")
	_expect(monster.has_method("_process_climbing"), "Monster should expose _process_climbing(delta, destination).")
	_expect(monster.has_method("_begin_mantle"), "Monster should expose _begin_mantle(target).")
	_expect(monster.has_method("_process_mantle"), "Monster should expose _process_mantle(delta).")
	_expect(monster.has_method("_compute_mantle_target"), "Monster should expose _compute_mantle_target(top_point, rv_up, approach_forward).")
	_expect(monster.has_method("_can_start_mantle"), "Monster should expose _can_start_mantle(top_surface_ok, stand_clearance_ok, forward_clear_ok).")
	_expect(monster.has_method("_is_rv_wall_normal"), "Monster should expose _is_rv_wall_normal(hit_normal, rv_up).")

	monster.free()

func _test_monster_mantle_target_clearance() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_compute_mantle_target"), "Monster should expose _compute_mantle_target(top_point, rv_up, approach_forward).")
	if monster.has_method("_compute_mantle_target"):
		var target: Vector3 = monster._compute_mantle_target(Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
		_expect(target.y >= 1.25, "Monster mantle target should provide deterministic top-out clearance (>=1.25m).")

	monster.free()

func _test_fallback_direction_is_normalized() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	if monster.has_method("_compute_fallback_direction"):
		var dir: Vector3 = monster._compute_fallback_direction(Vector3.ZERO, Vector3(3.0, 2.0, 4.0))
		_expect(dir.is_equal_approx(Vector3(0.6, 0.0, 0.8)), "Fallback direction should normalize destination vector on XZ plane.")

	monster.free()

func _test_stuck_progress_gate() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	if monster.has_method("_is_progress_too_small"):
		_expect(monster._is_progress_too_small(0.01, 0.05), "Progress below threshold should be treated as stalled.")
		_expect(not monster._is_progress_too_small(0.20, 0.05), "Progress above threshold should not be stalled.")

	monster.free()

func _test_stuck_threshold_scales_with_delta() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	if monster.has_method("_get_frame_progress_threshold") and monster.has_method("_is_progress_too_small"):
		var frame_threshold_60fps: float = monster._get_frame_progress_threshold(1.0 / 60.0)
		_expect(frame_threshold_60fps > 0.0, "Frame threshold should be positive.")
		_expect(frame_threshold_60fps < monster.move_progress_threshold, "Frame threshold should scale down from per-second threshold.")

		var normal_move_progress := 0.03
		_expect(not monster._is_progress_too_small(normal_move_progress, frame_threshold_60fps), "Normal frame progress should not be treated as stuck at 60 FPS.")

	monster.free()

func _test_elevation_gap_gate() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	if monster.has_method("_is_elevation_gap_climbable"):
		_expect(not monster._is_elevation_gap_climbable(0.1), "Very small elevation gaps should not trigger assist.")
		_expect(monster._is_elevation_gap_climbable(0.2), "Low-but-meaningful elevation gaps should trigger assist eligibility.")
		_expect(monster._is_elevation_gap_climbable(0.6), "Moderate elevation gaps should trigger assist eligibility.")
		_expect(monster._is_elevation_gap_climbable(2.2), "Mid-high elevation gaps should still be eligible for assist.")
		_expect(not monster._is_elevation_gap_climbable(3.5), "Very high elevation gaps should not trigger assist eligibility.")

	monster.free()

func _test_elevation_assist_velocity_builder() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	if monster.has_method("_build_elevation_assist_velocity"):
		var base_velocity := Vector3(2.0, 0.0, 1.0)
		var assisted: Vector3 = monster._build_elevation_assist_velocity(base_velocity)
		_expect(assisted.y > 0.0, "Elevation assist velocity should apply positive upward speed.")
		_expect(assisted.x <= base_velocity.x and assisted.z <= base_velocity.z, "Elevation assist should reduce planar push while climbing up.")

	if monster.has_method("_build_stuck_recovery_velocity"):
		var recovery: Vector3 = monster._build_stuck_recovery_velocity(Vector3(1.0, 0.0, 0.0), 1.0)
		_expect(recovery.y > 0.0, "Stuck recovery velocity should include upward hop.")
		_expect(absf(recovery.z) > 0.01, "Stuck recovery velocity should include side push for corner escape.")

	monster.free()

func _test_vehicle_impact_direction_and_speed_gate() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	if monster.has_method("_compute_vehicle_approach_speed") and monster.has_method("_should_apply_vehicle_damage"):
		var impact_dir := Vector3(0.0, 0.0, 1.0)
		var frontal_speed: float = monster._compute_vehicle_approach_speed(Vector3(0.0, 0.0, 10.0), impact_dir)
		_expect(frontal_speed > 0.0, "Frontal approach speed should be positive.")
		_expect(monster._should_apply_vehicle_damage(Vector3(0.0, 0.0, 10.0), impact_dir), "Fast frontal impact should apply damage.")

		_expect(not monster._should_apply_vehicle_damage(Vector3(10.0, 0.0, 0.0), impact_dir), "Side swipe should not apply damage.")
		_expect(not monster._should_apply_vehicle_damage(Vector3(0.0, 0.0, -10.0), impact_dir), "Vehicle moving away should not apply damage.")
		_expect(not monster._should_apply_vehicle_damage(Vector3(0.0, 0.0, 1.0), impact_dir), "Low-speed contact should not apply damage.")

	monster.free()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("PASS: monster navigation tests")
		quit(0)
		return

	push_error("FAIL: monster navigation tests")
	for failure in failures:
		push_error(" - " + failure)
	quit(1)
