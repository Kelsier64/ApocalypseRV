extends SceneTree
## Exercise real event routing and physics, not just cleared ownership flags.
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value: failures.append(note)
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
func run() -> void:
	var scene: Node3D = load('res://tests/raker_vehicle_playground.tscn').instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 75: await physics_frame
	for mode in [0,1,2]:
		scene.setup_grab(mode)
		var player: CharacterBody3D = scene.player
		for i in 1200:
			await physics_frame
			if player.is_grabbed(): break
		check(player.is_grabbed(),'Production capture %d' % mode)
		if not player.is_grabbed(): continue
		while player.grab_control.presses*5 < player.grab_control.required*4: player.submit_struggle()
		var view: Camera3D = player.seated_in.seat_camera if mode == 2 else player.camera
		# Reproduce focus/UI input capture being lost during a grab. Old end()
		# hid the HUD but left mouse look gated by MOUSE_MODE_VISIBLE.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if mode == 0: player.set_process_unhandled_input(false)
		var contact_seen := false
		for i in 400:
			await physics_frame
			if not player.is_grabbed():
				contact_seen = true
				break
		check(contact_seen and player.current_player_health == 50,'Survivor released on natural bite clock %d' % mode)
		if not contact_seen: continue
		check(scene.monster.grab.phase == scene.monster.grab.Phase.RELEASE,'Player released before monster recovery %d' % mode)
		var position_before: Vector3 = player.global_position
		var yaw_before: float = view.rotation.y if mode == 2 else player.rotation.y
		var pitch_before: float = view.rotation.x
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(90,25)
		motion.position = root.get_visible_rect().size*.5
		Input.parse_input_event(motion)
		for i in 2: await process_frame
		if DisplayServer.get_name() != 'headless':
			check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,'Mouse recaptured on release %d' % mode)
			var yaw_after: float = view.rotation.y if mode == 2 else player.rotation.y
			check(absf(yaw_after-yaw_before) > .1 and absf(view.rotation.x-pitch_before) > .02,'Real mouse event changes yaw AND pitch %d' % mode)
			print('RELEASE_LOOK mode=',mode,' yaw_delta=',yaw_after-yaw_before,' pitch_delta=',view.rotation.x-pitch_before)
		if mode == 2:
			scene.cruise_index = -1
			key(KEY_W,true)
		else: key(KEY_S,true)
		for i in 15: await physics_frame
		if mode == 2:
			key(KEY_W,false)
			check(scene.rv.throttle_input > .1 and not scene.rv.driver_controls_locked(),'Real driver throttle resumes')
		else:
			key(KEY_S,false)
			var distance := (player.global_position-position_before).slide(Vector3.UP).length()
			print('RELEASE_MOVE mode=',mode,' distance=',distance)
			check(distance > .15,'Real key event moves surviving body %d' % mode)
		check(not player.is_grabbed(),'Recovery cannot reacquire input %d' % mode)
	if DisplayServer.get_name() == 'headless': print('NOTE: Dummy display cannot capture mouse; run this suite with a real display for look verification.')
	scene.queue_free()
	for i in 4: await process_frame
	if failures.is_empty(): print('PASS: Natural bite release restores real movement and available mouse/seat input')
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
