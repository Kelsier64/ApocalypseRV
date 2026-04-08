extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_test_navigation_contract_methods_exist()
	_test_climb_contract_methods_exist()
	_test_descent_hint_direction_from_last_climb_wall()
	_test_chase_direction_uses_descent_hint_even_off_rv_surface()
	_test_attack_gate_rejects_large_vertical_gap()
	_test_attack_gate_requires_line_of_sight()
	_test_climb_contact_grace_scales_with_vertical_speed()
	_test_descent_hint_prefers_climb_side_when_target_below()
	_test_fallback_wall_contact_helper_safe_outside_tree()
	_test_climb_separation_state_labels()
	_test_navigation_gate_after_separation_with_vertical_gap()
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
	_expect(not monster.has_method("_begin_mantle"), "Monster mantle helper _begin_mantle should be removed.")
	_expect(not monster.has_method("_process_mantle"), "Monster mantle helper _process_mantle should be removed.")
	_expect(not monster.has_method("_compute_mantle_target"), "Monster mantle helper _compute_mantle_target should be removed.")
	_expect(not monster.has_method("_can_start_mantle"), "Monster mantle helper _can_start_mantle should be removed.")
	_expect(monster.has_method("_is_rv_wall_normal"), "Monster should expose _is_rv_wall_normal(hit_normal, rv_up).")
	_expect(monster.has_method("_get_descent_hint_direction"), "Monster should expose _get_descent_hint_direction(destination).")

	monster.free()

func _test_descent_hint_direction_from_last_climb_wall() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_get_descent_hint_direction"), "Monster should expose _get_descent_hint_direction(destination).")
	if monster.has_method("_get_descent_hint_direction"):
		monster.last_climb_wall_normal = Vector3.RIGHT
		var hint: Vector3 = monster._get_descent_hint_direction(Vector3(0.0, -2.0, 0.0))
		_expect(hint.is_equal_approx(Vector3.RIGHT), "When target is below and horizontal fallback is zero, descent hint should follow last climb wall normal.")

	monster.free()

func _test_chase_direction_uses_descent_hint_even_off_rv_surface() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_resolve_chase_direction"), "Monster should expose _resolve_chase_direction(destination, on_rv_surface, nav_active).")
	if monster.has_method("_resolve_chase_direction"):
		monster.last_climb_wall_normal = Vector3.RIGHT
		monster.post_climb_transfer_direction = Vector3.ZERO
		monster.post_climb_transfer_time_remaining = 0.0
		var dir: Vector3 = monster._resolve_chase_direction(Vector3(0.0, -2.0, 0.0), false, false)
		_expect(dir.is_equal_approx(Vector3.RIGHT), "Chase direction should use descent hint when fallback is zero and target is below, even if RV surface ray misses.")

	monster.free()

func _test_attack_gate_rejects_large_vertical_gap() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_can_attack_target_position"), "Monster should expose _can_attack_target_position(target_position).")
	if monster.has_method("_can_attack_target_position"):
		monster.position = Vector3.ZERO
		var high_target := Vector3(0.1, 1.9, 0.1)
		var near_flat_target := Vector3(0.6, 0.2, 0.4)
		_expect(not monster._can_attack_target_position(high_target), "Attack gate should reject targets with large vertical gap.")
		_expect(monster._can_attack_target_position(near_flat_target), "Attack gate should allow nearby targets with small vertical gap.")

	monster.free()

func _test_attack_gate_requires_line_of_sight() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_can_attack_target_position"), "Monster should expose _can_attack_target_position(target_position, has_line_of_sight).")
	if monster.has_method("_can_attack_target_position"):
		monster.position = Vector3.ZERO
		var near_target := Vector3(0.6, 0.2, 0.4)
		_expect(monster._can_attack_target_position(near_target, true), "Attack gate should allow close target when line of sight is available.")
		_expect(not monster._can_attack_target_position(near_target, false), "Attack gate should reject close target when line of sight is blocked.")

	monster.free()

func _test_climb_contact_grace_scales_with_vertical_speed() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_compute_climb_contact_grace_time"), "Monster should expose _compute_climb_contact_grace_time(vertical_speed).")
	if monster.has_method("_compute_climb_contact_grace_time"):
		var low_speed_grace: float = monster._compute_climb_contact_grace_time(1.0)
		var high_speed_grace: float = monster._compute_climb_contact_grace_time(3.0)
		_expect(low_speed_grace > high_speed_grace, "Lower climb speed should increase wall-contact grace time.")
		_expect(high_speed_grace >= 0.28, "Grace time should not drop below base minimum.")

	monster.free()

func _test_descent_hint_prefers_climb_side_when_target_below() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_get_descent_hint_direction"), "Monster should expose _get_descent_hint_direction(destination).")
	if monster.has_method("_get_descent_hint_direction"):
		monster.position = Vector3.ZERO
		monster.last_climb_wall_normal = Vector3.LEFT
		var hint: Vector3 = monster._get_descent_hint_direction(Vector3(1.0, -2.0, 0.0))
		_expect(hint.x < 0.0, "When target is below, descent direction should still favor the last climb side instead of drifting across the roof.")

	monster.free()

func _test_fallback_wall_contact_helper_safe_outside_tree() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_get_fallback_wall_contact_normal"), "Monster should expose _get_fallback_wall_contact_normal(rv_up).")
	if monster.has_method("_get_fallback_wall_contact_normal"):
		monster.active_wall_normal = Vector3.RIGHT
		var normal: Vector3 = monster._get_fallback_wall_contact_normal(Vector3.UP)
		_expect(normal.is_equal_approx(Vector3.ZERO), "Fallback wall contact helper should safely return ZERO when monster is outside the scene tree.")

	monster.free()

func _test_climb_separation_state_labels() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_get_climb_separation_state"), "Monster should expose _get_climb_separation_state(has_wall_contact, grace_remaining).")
	if monster.has_method("_get_climb_separation_state"):
		_expect(monster._get_climb_separation_state(true, 0.0) == "attached", "Separation state should be attached when wall contact exists.")
		_expect(monster._get_climb_separation_state(false, 0.2) == "detaching", "Separation state should be detaching during grace window without contact.")
		_expect(monster._get_climb_separation_state(false, 0.0) == "separated", "Separation state should be separated when grace is exhausted.")

	monster.free()

func _test_navigation_gate_after_separation_with_vertical_gap() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_should_use_navigation_for_chase"), "Monster should expose _should_use_navigation_for_chase(can_nav, on_rv_surface, vertical_gap, post_separation_block_remaining).")
	if monster.has_method("_should_use_navigation_for_chase"):
		monster.last_climb_separation_state = "separated"
		_expect(not monster._should_use_navigation_for_chase(true, false, 1.2, 0.0), "Navigation should pause right after separation when vertical gap is large.")
		_expect(not monster._should_use_navigation_for_chase(true, false, 0.2, 0.3), "Navigation should stay paused during post-separation block even with small vertical gaps.")
		_expect(monster._should_use_navigation_for_chase(true, false, 0.2, 0.0), "Navigation should resume for small vertical gaps after post-separation block expires.")
		_expect(not monster._should_use_navigation_for_chase(true, true, 0.2, 0.0), "Navigation should be disabled when standing on RV surface.")

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
