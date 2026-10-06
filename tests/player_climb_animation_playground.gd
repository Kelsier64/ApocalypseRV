extends "res://tests/rv_climb_playground.gd"
## Close-up presentation review; the separate two-actor replay remains available.
const OUT := "res://docs/validation/rv-ladders-20261005/"
var capture_directory := OUT
var reviewing := false
var side_view := false
var last_clip := ""

func _ready() -> void:
	super._ready()
	get_window().title = "ApocalypseRV - Climb Animation Acceptance"
	get_window().size = Vector2i(1200, 850)
	monster.queue_free()
	status.position.y = 150
	observer.fov = 48
	observer.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "--camera-review" in OS.get_cmdline_user_args():
		capture_directory = OUT + "camera/"
	DirAccess.make_dir_recursive_absolute(capture_directory)
	if "--animation-review" in OS.get_cmdline_user_args(): review.call_deferred()

func _physics_process(delta: float) -> void:
	var clip: String = player.get_node("Visuals/Locomotion").current_clip
	if clip != last_clip:
		print("CLIMB_TRANSITION ", clip, " local=", rv.to_local(player.global_position), " floor=", player.is_on_floor(), " supported=", player.rv_support.rv == rv)
		last_clip = clip
	if driving:
		rv.position += -rv.basis.z * 4.0 * delta
		rv.rotate_y(.12 * delta)
	var target := player.global_position + Vector3(0, 1.1, 0)
	observer.global_position = target + rv.global_basis * (Vector3(1.4, .5, 3) if side_view else Vector3(2.6, .7, 2.2))
	observer.look_at(target)
	status.text = "CLIMB ANIMATION | 60 Hz | " + player.get_node("Visuals/Locomotion").current_clip + "\nF1 first person | F2 observer | F3 replay | Esc close\n" + ("Carrier moving + turning" if driving else "Stationary carrier")

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F1:
			player.camera.rotation.x = deg_to_rad(-35)
			player.camera.make_current()
		KEY_F2: observer.make_current()
		KEY_F3:
			if not reviewing: review()
		KEY_ESCAPE: get_tree().quit()

func frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame
		await get_tree().process_frame
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_directory + "godot_" + label + ".png")
	print("CLIMB_CAPTURE ", label, " clip=", player.get_node("Visuals/Locomotion").current_clip)
func review() -> void:
	reviewing = true
	driving = false
	player._exit_climb_to_normal()
	var ladder: RVLadder = rv.get_node("RoofLadder")
	player.global_position = ladder.climb_point(0.0) - Vector3.UP * .24
	player.rotation.y = ladder.global_rotation.y
	player.velocity = Vector3.ZERO
	await frames(45)
	# Match the cabin ladder lane and actual capsule feet.
	player.global_position = ladder.climb_point(0.0) - Vector3.UP * .24
	player.velocity = Vector3.ZERO
	Input.action_press("move_forward")
	for frame in 90:
		await frames(1)
		if player.get_node("Visuals/Locomotion").current_clip == "climb_up": break
	if player.get_node("Visuals/Locomotion").current_clip != "climb_up":
		push_error("Climb review did not reach the ladder")
		Input.action_release("move_forward")
		reviewing = false
		return
	await frames(12)
	await capture("up")
	Input.action_release("move_forward")
	await frames(20)
	side_view = true
	await capture("hold_side")
	player.camera.rotation.x = deg_to_rad(-35)
	player.camera.make_current()
	await capture("hold_first_person")
	if "--camera-review" in OS.get_cmdline_user_args():
		player.camera.rotation.x = deg_to_rad(-75)
		await capture("hold_look_down")
		player.camera.rotation.x = 0
		await capture("hold_look_level")
	observer.make_current()
	side_view = false
	Input.action_press("move_back")
	await frames(6)
	await capture("down")
	Input.action_release("move_back")
	await frames(15)
	driving = true
	await frames(45)
	await capture("carrier_hold")
	driving = false
	Input.action_press("move_forward")
	for frame in 180:
		await frames(1)
		if player.ladder_transition == player.LadderTransition.TOP: break
	await frames(30)
	await capture("roof_top_hold")
	Input.action_release("move_forward")
	if player.ladder_transition != player.LadderTransition.TOP:
		push_error("Climb review did not reach the top hold")
		reviewing = false
		return
	await frames(15)
	Input.action_press("move_back")
	for frame in 120:
		await frames(1)
		if player.locomotion_state == player.LocomotionState.NORMAL: break
	Input.action_release("move_back")
	if player.locomotion_state != player.LocomotionState.NORMAL:
		push_error("Manual walking did not reach the roof")
		reviewing = false
		return
	await capture("roof_exit")
	await frames(30)
	await capture("roof_idle")
	print("PASS: rendered ladder up, hold, down, moving carrier, first person, top hold and manual roof exit at ", Engine.physics_ticks_per_second, " Hz")
	reviewing = false

func _exit_tree() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right"]: Input.action_release(action)
