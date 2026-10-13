extends "res://tests/test_training_driving.gd"

func world_scene() -> String:
	return "res://tests/tutorial_shelter_playground.tscn"

func check_entrypoint() -> void:
	var player: Node3D = world.get_node("Player")
	check(not world.get("review_mode") and not is_instance_valid(world.get("overview")) and world.get("status") == null,
		"Normal F6 playground entry does not create review cameras or status HUD")
	check(player.camera.current, "Normal F6 playground entry keeps the production player camera current")
	check(tutorial.stage == 1 and not tutorial.flags.viewed and not tutorial.flags.flashlight
		and tutorial.flags.marker_index == 0 and not tutorial.flags.reversed and not tutorial.flags.parked,
		"Normal F6 playground entry keeps all five lesson conditions incomplete")
	var f2 := InputEventKey.new()
	f2.pressed = true
	f2.physical_keycode = KEY_F2
	world.call("_input", f2)
	world.call("_start_replay")
	check(not world.get("replay_started") and run_owner.gate.target == 0.0
		and run_owner.phase == "preparing", "F2 and direct replay call cannot bypass training locks")
	check(world.call("requests_review", PackedStringArray(["--review"]))
		and world.call("requests_review", PackedStringArray(["--replay"]))
		and world.call("requests_review", PackedStringArray(["--art-daylight"]))
		and world.call("requests_review", PackedStringArray(["--inspect-gate"]))
		and not world.call("requests_review", PackedStringArray()), "Only explicit review arguments select review mode")
