extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	var player_script: Script = load("res://player/player.gd")
	if player_script == null:
		failures.append("Player script should load.")
		_finish()
		return

	var player: Node = player_script.new()
	if player == null:
		failures.append("Player should instantiate.")
		_finish()
		return

	if not player.has_method("_abort_climb"):
		failures.append("Player should expose _abort_climb(reason).")

	if not player.has_method("_compute_mantle_target"):
		failures.append("Player should expose _compute_mantle_target(top_point, rv_up, cam_forward).")
	else:
		var target: Vector3 = player._compute_mantle_target(Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
		if target.y < 1.25:
			failures.append("Mantle target should provide deterministic top-out clearance (>=1.25m).")

	player.free()
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("PASS: player climbing runtime tests")
		quit(0)
		return

	push_error("FAIL: player climbing runtime tests")
	for failure in failures:
		push_error(" - " + failure)
	quit(1)
