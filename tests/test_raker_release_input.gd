extends SceneTree
const GrabRules = preload("res://core/raker_grab_rules.gd")
## Exercise real event routing and physics, not just cleared ownership flags.
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value and note not in failures: failures.append(note)
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
		for attempt in player.grab_control.required:
			if player.grab_control.presses >= GrabRules.minimum_wounded_presses(player.grab_control.required): break
			if not player.submit_struggle(): break
		check(GrabRules.reaches_wounded_threshold(player.grab_control.presses, player.grab_control.required), "Struggle reaches the wounded threshold before the deadline %d" % mode)
		if mode == 2 and not is_instance_valid(player.seated_in):
			check(false, "Driver remains seated after capture")
			continue
		var view: Camera3D = player.seated_in.seat_camera if mode == 2 else player.camera
		var arm_samples := {"count": 0}
		if mode == 2:
			var visual: Node3D = scene.monster.get_node("BodyMesh")
			var captured_monster: Raker = scene.monster
			# Inspect the evaluated IK, before Skeleton3D restores the input pose.
			visual.pose_modifier.modification_processed.connect(func():
				if captured_monster.grab.phase != captured_monster.grab.Phase.BITE or captured_monster.grab.elapsed < .08: return
				arm_samples.count += 1
				var skeleton: Skeleton3D = visual.skeleton
				for suffix in ["_L", "_R"]:
					var points: Array[Vector3] = []
					for bone in ["upper_arm", "forearm", "hand"]:
						points.append(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(bone + suffix)).origin))
					for segment in [[points[0], points[1]], [points[1], points[2]]]:
						var query := PhysicsRayQueryParameters3D.create(segment[0], segment[1], 1, [player.get_rid(), captured_monster.get_rid()])
						var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
						check(hit.is_empty(), "Rendered driver bite arms clear the seatback and cabin: " + suffix)
			)
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
		if mode == 2:
			check(arm_samples.count >= 5, "Driver arm clearance sampled through the bite approach")
			print("DRIVER_ARM_CLEARANCE_SAMPLES ", arm_samples.count)
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
	await verify_driver_barrier(scene)
	if DisplayServer.get_name() == 'headless': print('NOTE: Dummy display cannot capture mouse; run this suite with a real display for look verification.')
	scene.queue_free()
	for i in 4: await process_frame
	if failures.is_empty(): print('PASS: Natural bite release restores real movement and available mouse/seat input')
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func verify_driver_barrier(scene: Node3D) -> void:
	scene.player.body_state.reset()
	scene.player._apply_body_capabilities()
	scene.setup_grab(2)
	for i in 1200:
		await physics_frame
		if scene.player.is_grabbed(): break
	check(scene.player.is_grabbed(), "Driver captured before introducing a blocking wall")
	if not scene.player.is_grabbed(): return
	scene.monster.set_physics_process(false)
	scene.rv.freeze = true
	await process_frame
	var shoulder: Vector3 = scene.monster.grab_shoulder_position(1)
	var wrist: Vector3 = scene.monster.grab.head_grip(scene.player.grab_contact_origin(), scene.monster.global_basis, 1)
	var lengths: Vector2 = scene.monster.get_node("BodyMesh").arm_lengths(1)
	check(scene.monster.grab.arm_path(shoulder, wrist, lengths, scene.monster.global_basis, 1, scene.player).blocked.is_empty(), "Seated elbow route is clear before introducing the wall")
	var wall := StaticBody3D.new()
	wall.name = "GrabBarrier"
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, .1)
	collision.shape = box
	wall.add_child(collision)
	scene.add_child(wall)
	wall.global_basis = Basis.looking_at((wrist - shoulder).normalized())
	wall.global_position = shoulder.lerp(wrist, .5)
	await physics_frame
	check(not scene.monster.grab.arm_path(shoulder, wrist, lengths, scene.monster.global_basis, 1, scene.player).blocked.is_empty(), "A solid wall blocks every seated elbow route")
	scene.monster.grab.tick(1.0 / 60.0)
	check(not scene.player.is_grabbed() and not scene.monster.grab.busy(), "Blocked driver capture releases both owners")
