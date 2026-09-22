extends SceneTree
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok: failures.append(note)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var actor: Raker = load("res://enemies/raker.tscn").instantiate()
	world.add_child(actor)
	actor.set_physics_process(false)
	var visual := actor.get_node("BodyMesh")
	visual.set_process(false)
	var anim: AnimationPlayer = visual.animation_player
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	visual.play("walk", 1.0, true)
	anim.advance(0)
	anim.seek(anim.current_animation_length * .63, true)
	visual.play("chase")
	check(absf(anim.current_animation_position / anim.current_animation_length - .63) < .001, "Walk to run preserves foot cycle")
	visual.play("sprint")
	check(absf(anim.current_animation_position / anim.current_animation_length - .63) < .001, "Run to sprint preserves foot cycle")
	visual.ground_clip = "walk"
	visual.filtered_speed = 2.3
	for i in 60:
		visual._ground_locomotion(1.0 / 60, 2.0 + .25 * sin(i))
		check(visual.ground_clip == "walk", "Threshold noise does not chatter into run")
	visual._ground_locomotion(1.0, 3.4)
	check(visual.ground_clip == "chase", "Sustained speed enters run")
	for i in 60:
		visual._ground_locomotion(1.0 / 60, 2.1 + .15 * sin(i))
		check(visual.ground_clip == "chase", "Run holds through threshold noise")
	actor.pursuit_gait = Raker.PursuitGait.VEHICLE_SPRINT
	visual._ground_locomotion(1.0, 3.0)
	check(visual.ground_clip == "chase", "Sprint intent does not play sprint while still accelerating slowly")
	visual._ground_locomotion(1.0, 8.0)
	check(visual.ground_clip == "sprint", "Sprint appears after speed builds")
	actor.pursuit_gait = Raker.PursuitGait.RUN
	visual._ground_locomotion(1.0, 3.4)
	check(visual.ground_clip == "chase", "Leaving vehicle sprint returns to run")
	visual._ground_locomotion(1.0 / 60.0, 0.0)
	check(visual.ground_clip == "idle", "A blocked or stopped actor does not run in place")
	# Keep a far-away destination for longer than the former four-second timer.
	actor.position = Vector3.ZERO
	actor.velocity = Vector3.ZERO
	for i in 360:
		actor._process_chase(1.0 / 60.0, Vector3(0, 0, -20))
		if i > 60: check(actor.velocity.length() > 3.3, "Long chase no longer periodically snaps to walking")
	world.free()
	if failures.is_empty(): print("PASS: Raker gait phase continuity, speed hysteresis, acceleration and sustained pursuit")
	else:
		for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
