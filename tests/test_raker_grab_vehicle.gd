extends SceneTree
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value: failures.append(note)
func run() -> void:
	root.size = Vector2i(1280,720)
	var scene: Node3D = load("res://tests/raker_vehicle_playground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 75: await physics_frame
	for scenario in [0, 1, 2, 3]:
		var mode := mini(scenario,2)
		scene.setup_grab(mode)
		var captured := false
		for i in 1200:
			await physics_frame
			if scene.player.is_grabbed():
				captured = true
				break
		check(captured,"Production AI captures scenario %d" % mode)
		if not captured:
			print("CAPTURE FAILED ",mode," gate ",scene.monster.grab.contact_failure," at ",scene.rv.to_local(scene.monster.global_position))
			continue
		var player: CharacterBody3D = scene.player
		await process_frame
		var viewport_rect := player.get_viewport().get_visible_rect()
		print("GRAB_HUD ",viewport_rect," label=",player.grab_control.label.get_global_rect()," bar=",player.grab_control.bar.get_global_rect())
		check(viewport_rect.encloses(player.grab_control.label.get_global_rect()),"Struggle label stays inside viewport")
		check(viewport_rect.encloses(player.grab_control.bar.get_global_rect()) and player.grab_control.bar.size.y >= 24,"Struggle progress bar stays visible")
		check(player.get_player_mode()==player.PlayerMode.GRABBED,"Grab mode takes priority over seat")
		var before: Transform3D = (player.seated_in.seat_camera if mode==2 else player.camera).transform
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(100,100)
		player._unhandled_input(motion)
		if mode==2:
			var seat: Node3D = player.seated_in
			seat._unhandled_input(motion)
			check(seat.seat_camera.transform==before,"Seated mouse input blocked")
			var handbrake: bool = scene.rv.handbrake
			var space := InputEventKey.new()
			space.physical_keycode = KEY_SPACE
			space.pressed = true
			seat._unhandled_input(space)
			check(scene.rv.handbrake==handbrake,"Struggle Space never toggles handbrake")
			check(scene.rv.driver_controls_locked(),"Driver polling controls locked")
			Input.action_press("move_forward")
			for i in 20: await physics_frame
			Input.action_release("move_forward")
			check(player.is_grabbed(),"Capture persists on common moving support")
			check(scene.rv.throttle_input<.01 and not scene.rv.handbrake,"Throttle releases to coast")
			if scenario == 3:
				while player.grab_control.presses*5 < player.grab_control.required*4: player.submit_struggle()
				scene.monster.grab.tick(2)
				scene.monster.grab.tick(.38)
				check(player.current_player_health==50 and not player.is_grabbed(),"Surviving driver is released at bite contact")
				check(player.seated_in==seat and not scene.rv.driver_controls_locked(),"Seat and driving controls resume on contact tick")
			else:
				seat.exit_seat(true)
				check(not player.is_grabbed() and not scene.rv.driver_controls_locked(),"Forced seat exit releases driver and monster")
		else:
			check(player.camera.transform==before,"Ground/cabin mouse input blocked")
			var count: int = player.grab_control.required
			for i in count: player.submit_struggle()
			check(not player.is_grabbed() and player.current_player_health==100,"Scenario escapes without damage")
	scene.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: Ground/cabin/moving-driver grabs, camera/input gates, coasting, seat cleanup")
	else:
		for note in failures: push_error(note)
	quit(0 if failures.is_empty() else 1)
