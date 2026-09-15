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

	if player.has_method("_begin_mantle"):
		failures.append("Player mantle API should be removed (_begin_mantle).")

	if player.has_method("_process_mantle"):
		failures.append("Player mantle API should be removed (_process_mantle).")

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
