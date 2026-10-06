extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_ladder_capability_gate()
	_test_active_large_item_gate()
	_test_wall_normal_geometry()
	_test_wall_hit_height_geometry()
	_test_collision_disabled_during_climb_states()
	_test_rv_delta_compensation_math()
	_test_climb_exit_velocity_sanitized()
	_test_abort_contract_exists()
	_test_player_has_climb_state_contract()
	_finish()

func _new_player() -> Node:
	var player_script: Script = load("res://player/player.gd")
	_expect(player_script != null, "Player script should load.")
	if player_script == null:
		return null
	var p: Node = player_script.new()
	_expect(p != null, "Player should instantiate.")
	return p

func _test_ladder_capability_gate() -> void:
	# Route and input authorization use production ladders in test_rv_ladders.
	var player := _new_player()
	if player == null:
		return
	_expect(player.has_method("_can_use_ladder"), "Player exposes the ladder capability gate.")
	if player.has_method("_can_use_ladder"):
		_expect(player._can_use_ladder(), "Healthy empty-handed player can use a ladder.")
		player.body_state.sever(&"left_arm")
		_expect(not player._can_use_ladder(), "A ladder requires both arms.")
		player.body_state.reset()
		player.body_state.sever(&"right_leg")
		_expect(not player._can_use_ladder(), "Crawling cannot use a ladder.")
		player.body_state.reset()
		player.is_player_dead = true
		_expect(not player._can_use_ladder(), "Dead players cannot use a ladder.")
	player.free()

func _test_active_large_item_gate() -> void:
	var player := _new_player()
	if player == null:
		return
	_expect(player._can_use_ladder(), "Empty hands retain ladder capability.")
	player.inventory.add_item("Small cargo", false, "unused")
	_expect(player._can_use_ladder(), "Small cargo retains ladder capability.")
	player.inventory.add_item("Custom large cargo", true, "unused", {"id": "cargo-identity", "condition": 37.0})
	_expect(player.held_item_node == null, "Fixture has no held visual; inventory remains the source of truth.")
	var original: Dictionary = player.inventory.active_item().duplicate(true)
	for attempt in range(3):
		_expect(not player._can_use_ladder(), "Active large cargo blocks ladder capability on repeated attempts.")
	_expect(player.inventory.items.size() == 2 and player.inventory.active_item() == original, "Rejected climb leaves item identity, state and count unchanged.")
	# Restored inventories can retain a large item in an inactive slot.
	player.inventory.active_slot = 0
	_expect(player._can_use_ladder(), "Inactive large cargo does not override the active small-item contract.")
	player.inventory.active_slot = 1
	player.inventory.consume_active()
	_expect(player._can_use_ladder(), "Removing large cargo immediately restores ladder capability.")
	player.free()

func _test_wall_normal_geometry() -> void:
	# Retained geometry utilities do not authorize player wall climbing.
	var player := _new_player()
	if player == null:
		return

	if player.has_method("_is_rv_wall_normal"):
		_expect(player._is_rv_wall_normal(Vector3.FORWARD, Vector3.UP), "Wall geometry identifies a vertical normal.")
		_expect(not player._is_rv_wall_normal(Vector3.UP, Vector3.UP), "Wall geometry excludes a floor normal.")

	player.free()

func _test_wall_hit_height_geometry() -> void:
	var player := _new_player()
	if player == null:
		return

	if player.has_method("_is_valid_climb_hit_height"):
		_expect(not player._is_valid_climb_hit_height(-0.9), "Hit-height geometry excludes an undercarriage hit.")
		_expect(player._is_valid_climb_hit_height(0.7), "Hit-height geometry includes a chest-height hit.")

	player.free()

func _test_collision_disabled_during_climb_states() -> void:
	var player := _new_player()
	if player == null:
		return

	_expect(player.has_method("_should_disable_body_collision_for_locomotion"), "Player should expose _should_disable_body_collision_for_locomotion(state).")
	if player.has_method("_should_disable_body_collision_for_locomotion"):
		_expect(not player._should_disable_body_collision_for_locomotion(player.LocomotionState.NORMAL), "Body collision should stay enabled during NORMAL locomotion.")
		_expect(not player._should_disable_body_collision_for_locomotion(player.LocomotionState.CLIMBING), "Climbing must keep body collision enabled to prevent tunneling.")

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

func _test_abort_contract_exists() -> void:
	var player := _new_player()
	if player == null:
		return

	_expect(player.has_method("_abort_climb"), "Player should expose _abort_climb(reason).")

	player.free()

func _test_player_has_climb_state_contract() -> void:
	var player := _new_player()
	if player == null:
		return

	_expect(player.has_method("_try_start_climb"), "Player should expose _try_start_climb() state transition helper.")
	_expect(player.has_method("_process_climbing"), "Player should expose _process_climbing(delta).")
	_expect(player.has_method("_build_climb_motion"), "Player should expose _build_climb_motion(...) helper.")

	if player.has_method("_build_climb_motion"):
		var m: Vector3 = player._build_climb_motion(Vector3.UP, Vector3.FORWARD, 0.0, 0.0, 1.0)
		_expect(m.dot(-Vector3.FORWARD) <= 0.0001, "Climb motion should not push player into wall interior.")
		var tilted_up := Vector3(0.0, 0.8, 0.2).normalized()
		var m2: Vector3 = player._build_climb_motion(tilted_up, Vector3.FORWARD, 1.0, 0.0, 1.0)
		_expect(m2.dot(-Vector3.FORWARD) <= 0.0001, "Climb motion should not push into wall even when RV up is tilted.")

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
