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
		# The preceding scenario actually severs an arm; each capture needs a
		# fresh body so its wounded outcome cannot promote to a fatal head bite.
		scene.player.body_state.reset()
		scene.player._apply_body_capabilities()
		scene.setup_grab(mode)
		var player: CharacterBody3D = scene.player
		for i in 1200:
			await physics_frame
			if player.is_grabbed(): break
		check(player.is_grabbed(),'Production capture %d' % mode)
		if not player.is_grabbed(): continue
		while player.grab_control.presses*5 < player.grab_control.required*4: player.submit_struggle()
		var view: Camera3D = player.seated_in.seat_camera if mode == 2 else player.camera
		var captured_body_yaw: float = player.rotation.y
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
		check(not player.grab_control.hud.visible and player.grab_control.camera == null,'Natural bite contact releases HUD and camera ownership %d' % mode)
		if mode != 2:
			check(absf(angle_difference(player.rotation.y, captured_body_yaw)) < .001,'Natural arm bite preserves body yaw %d' % mode)
		var position_before: Vector3 = player.global_position
		var yaw_before: float = view.rotation.y - player.grab_control.recovery_rotation.y if mode == 2 else player.rotation.y
		var pitch_before: float = view.rotation.x - player.grab_control.recovery_rotation.x
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(90,25)
		motion.position = root.get_visible_rect().size*.5
		Input.parse_input_event(motion)
		for i in 2: await process_frame
		if DisplayServer.get_name() != 'headless':
			check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,'Mouse recaptured on release %d' % mode)
			var yaw_after: float = view.rotation.y - player.grab_control.recovery_rotation.y if mode == 2 else player.rotation.y
			var pitch_after: float = view.rotation.x - player.grab_control.recovery_rotation.x
			check(absf(yaw_after-yaw_before) > .1 and absf(pitch_after-pitch_before) > .02,'Real mouse event changes yaw AND pitch %d' % mode)
			print('RELEASE_LOOK mode=',mode,' yaw_delta=',yaw_after-yaw_before,' pitch_delta=',pitch_after-pitch_before)
			# Camera recovery can finish independently, but must keep the real
			# mouse yaw already accepted during the contact frame.
			player.grab_control._process(1.0)
			var recovered_yaw: float = view.rotation.y if mode == 2 else player.rotation.y
			check(absf(angle_difference(recovered_yaw, yaw_after)) < .0001,'Camera recovery retains immediate mouse yaw %d' % mode)
			var recovered_pitch: float = view.rotation.x
			check(absf(recovered_pitch - pitch_after) < .0001,'Camera recovery retains immediate mouse pitch %d' % mode)
			motion.relative = Vector2(-60,-20)
			Input.parse_input_event(motion)
			for i in 2: await process_frame
			var subsequent_yaw: float = view.rotation.y if mode == 2 else player.rotation.y
			check(absf(angle_difference(subsequent_yaw, recovered_yaw)) > .08 and absf(view.rotation.x-recovered_pitch) > .015,'Real mouse yaw and pitch remain available after recovery %d' % mode)
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
		if mode == 2:
			player.grab_control.recovery_camera = view
			player.grab_control.recovery_rotation = Vector3(-.5, -.5, 0)
			view.rotation = Vector3(deg_to_rad(80), deg_to_rad(120), 0)
			player.grab_control._process(1.0)
			check(absf(view.rotation.x) <= deg_to_rad(80) + .0001 and absf(view.rotation.y) <= deg_to_rad(120) + .0001,'Completed seat effect preserves pitch/yaw limits')
			# Exercise departure while a contact effect is still pending, even
			# on a real display where the input assertions advanced it to completion.
			player.grab_control.recovery_camera = view
			player.grab_control.recovery_rotation = Vector3(-.1, .2, 0)
			view.rotation += player.grab_control.recovery_rotation
			var seat: Node3D = player.seated_in
			seat.exit_seat(true)
			check(player.seated_in == null and player.grab_control.recovery_camera == null,'Seat exit cancels pending arm view %d' % mode)
			player.grab_control._process(.5)
			check(view.rotation.is_equal_approx(seat.REST_CAMERA_ROTATION),'Old arm view cannot change the reset seat camera %d' % mode)
	if DisplayServer.get_name() == 'headless': print('NOTE: Dummy display cannot capture mouse; run this suite with a real display for look verification.')
	scene.queue_free()
	for i in 4: await process_frame
	if failures.is_empty(): print('PASS: Natural bite release restores real movement and available mouse/seat input')
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
