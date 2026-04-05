extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_test_wall_gate_requires_jump_and_w_and_rv()
	_test_wall_gate_rejects_undercarriage_like_hits()
	_test_top_gate_requires_standable_surface()
	_test_rv_delta_compensation_math()
	_test_climb_exit_velocity_sanitized()
	_finish()

func _new_player() -> Node:
	var player_script: Script = load("res://player/player.gd")
	_expect(player_script != null, "Player script should load.")
	if player_script == null:
		return null
	var p: Node = player_script.new()
	_expect(p != null, "Player should instantiate.")
	return p

func _test_wall_gate_requires_jump_and_w_and_rv() -> void:
	var player := _new_player()
	if player == null:
		return

	_expect(player.has_method("_is_rv_wall_normal"), "Player should expose _is_rv_wall_normal(normal, rv_up).")
	_expect(player.has_method("_is_valid_climb_hit_height"), "Player should expose _is_valid_climb_hit_height(local_hit_y).")
	_expect(player.has_method("_can_begin_climb"), "Player should expose _can_begin_climb(jump_pressed, w_pressed, is_rv_hit, wall_normal_ok, hit_height_ok).")

	if player.has_method("_can_begin_climb"):
		_expect(not player._can_begin_climb(false, true, true, true, true), "Jump is required to start climb.")
		_expect(not player._can_begin_climb(true, false, true, true, true), "W is required to start climb.")
		_expect(not player._can_begin_climb(true, true, false, true, true), "RV hit is required to start climb.")
		_expect(player._can_begin_climb(true, true, true, true, true), "All gates should allow climb start.")

	player.free()

func _test_wall_gate_rejects_undercarriage_like_hits() -> void:
	var player := _new_player()
	if player == null:
		return

	if player.has_method("_is_valid_climb_hit_height"):
		_expect(not player._is_valid_climb_hit_height(-0.9), "Undercarriage-like low hit should be rejected.")
		_expect(player._is_valid_climb_hit_height(0.7), "Chest-height wall hit should be accepted.")

	player.free()

func _test_top_gate_requires_standable_surface() -> void:
	var player := _new_player()
	if player == null:
		return

	_expect(player.has_method("_can_start_mantle"), "Player should expose _can_start_mantle(top_surface_ok, stand_clearance_ok, forward_clear_ok).")
	if player.has_method("_can_start_mantle"):
		_expect(not player._can_start_mantle(true, false, true), "Mantle should fail without stand clearance.")
		_expect(player._can_start_mantle(true, true, true), "Mantle should pass when all top gates are valid.")

	player.free()

func _test_rv_delta_compensation_math() -> void:
	var player := _new_player()
	if player == null:
		return

	_expect(player.has_method("_compute_rv_position_delta"), "Player should expose _compute_rv_position_delta(prev, next).")
	if player.has_method("_compute_rv_position_delta"):
		var prev := Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))
		var next := Transform3D(Basis.IDENTITY, Vector3(3, 3, 7))
		var d: Vector3 = player._compute_rv_position_delta(prev, next)
		_expect(d.is_equal_approx(Vector3(2, 1, 4)), "RV delta should be next.origin - prev.origin.")

	player.free()

func _test_climb_exit_velocity_sanitized() -> void:
	var player := _new_player()
	if player == null:
		return

	_expect(player.has_method("_sanitize_velocity_after_climb"), "Player should expose _sanitize_velocity_after_climb(v).")
	if player.has_method("_sanitize_velocity_after_climb"):
		var out: Vector3 = player._sanitize_velocity_after_climb(Vector3(2, 30, -1))
		_expect(out.y <= 0.1, "Vertical velocity should be sanitized when exiting climb.")

	player.free()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("PASS: player climbing tests")
		quit(0)
		return

	push_error("FAIL: player climbing tests")
	for failure in failures:
		push_error(" - " + failure)
	quit(1)
