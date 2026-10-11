extends SceneTree
## Production input, collision movement, pose selection and ownership in a low tunnel.
const PLAYER := preload("res://player/player.tscn")
const STANDING_REFERENCE := preload("res://assets/models/player_animations_v021/player_animations_v021.glb")
const CROUCH_VARIANTS := [preload("res://assets/animations/player/crouch_bent.res"), preload("res://assets/animations/player/crouch.res")]
const ACTIONS := ["crouch", "sprint", "jump", "move_forward", "move_back", "move_left", "move_right"]
var failures: Array[String] = []
var arena: Node3D
var actor: CharacterBody3D
var driver: Node
var metrics: Array[Dictionary] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok and detail not in failures:
		failures.append(detail)
		push_error("FAIL: " + detail)

func steps(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func release_inputs() -> void:
	for action: String in ACTIONS: Input.action_release(action)
	ctrl(false)

func ctrl(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_CTRL
	event.physical_keycode = KEY_CTRL
	event.pressed = pressed
	Input.parse_input_event(event)

func box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = at
	arena.add_child(body)
	return body

func reset(at: Vector3 = Vector3(0, .05, 0), body: Dictionary = {}) -> void:
	release_inputs()
	actor.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0,
		"transform": Transform3D(Basis.IDENTITY, at), "body": body})
	await steps(40)
	check(actor.is_on_floor(), "Fixture settles on a real collision floor")

func sole_y() -> float:
	var capsule := actor.body_collision_shape.shape as CapsuleShape3D
	return actor.body_collision_shape.position.y - capsule.height * .5

func test_input_geometry_and_directions() -> void:
	check(InputMap.has_action("crouch"), "Crouch action exists")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_CTRL
	check(InputMap.event_is_action(event, "crouch"), "Physical Ctrl maps to crouch")
	await reset()
	var upright_sole := sole_y()
	var start_y := actor.position.y
	var upright_eye: float = actor.camera.position.y
	ctrl(true)
	await steps(1)
	check(actor.is_crouching(), "Held physical Ctrl enters crouch on the floor")
	var first_eye: float = actor.camera.position.y
	check(first_eye < upright_eye and first_eye > 1.20, "Eye begins a smooth descent instead of snapping")
	check(absf(first_eye - upright_eye) < .15, "Initial crouch camera step is bounded")
	await steps(40)
	var capsule := actor.body_collision_shape.shape as CapsuleShape3D
	check(is_equal_approx(capsule.height, 1.05) and is_equal_approx(capsule.radius, .4), "Crouch lowers collision height and preserves body width")
	check(is_equal_approx(sole_y(), upright_sole) and absf(actor.position.y - start_y) < .01, "Crouch preserves capsule sole and grounded root")
	check(absf(actor.camera.position.y - 1.20) < .03, "Crouch eye settles at its lower target")
	check(driver.current_clip == "crouch/idle", "Stationary crouch selects idle pose")
	check(not actor._can_use_ladder(), "Crouching cannot enter a ladder")
	for direction: String in ["forward", "back", "left", "right"]:
		var action := "move_" + direction
		var start := actor.position
		Input.action_press(action)
		await steps(30)
		check(driver.current_clip == "crouch/" + direction, "Real movement selects crouch " + direction)
		var relative: Vector3 = actor.global_basis.inverse() * (actor.position - start)
		var expected := Vector3(0, 0, -1) if direction == "forward" else Vector3(0, 0, 1)
		if direction == "left": expected = Vector3.LEFT
		if direction == "right": expected = Vector3.RIGHT
		check(relative.dot(expected) > .85 and relative.slide(expected).length() < .03, "Crouch " + direction + " moves through real physics in the requested direction")
		check(absf(Vector2(actor.velocity.x, actor.velocity.z).length() - 2.0) < .01, "Crouch " + direction + " uses 2 m/s")
		check(actor.is_on_floor() and absf(actor.position.y - start_y) < .01, "Directional crouch stays grounded")
		Input.action_release(action)
		await steps(6)
		check(driver.current_clip == "crouch/idle", "Releasing direction returns to crouch idle")
	ctrl(false)
	await steps(40)
	check(not actor.is_crouching() and is_equal_approx(sole_y(), upright_sole), "Ctrl release restores upright collision in open space")
	check(absf(actor.camera.position.y - upright_eye) < .03, "Ctrl release smoothly restores standing eye height")
	check(driver.current_clip == "idle", "Standing locomotion resumes after release")
	metrics.append({"case": "directions", "sole": upright_sole, "first_eye": first_eye, "standing_eye": upright_eye})

func test_exertion_and_airborne_entry() -> void:
	await reset()
	Input.action_press("crouch")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	actor.current_stamina = 80.0
	actor.stamina_recovery_delay_remaining = 10.0
	await steps(10)
	var start := actor.position
	Input.action_press("jump")
	for frame in 90:
		await steps(1)
		check(actor.is_on_floor() and actor.velocity.y <= .01, "Space cannot jump while crouched")
		check(absf(Vector2(actor.velocity.x, actor.velocity.z).length() - 2.0) < .01, "Shift cannot sprint while crouched")
		check(is_equal_approx(actor.current_stamina, 80.0), "Crouch with Shift and Space spends no stamina")
	check(actor.position.distance_to(start) > 2.8, "Crouch remains mobile while sprint and jump inputs are held")
	release_inputs()
	await steps(10)
	Input.action_press("jump")
	await steps(2)
	Input.action_release("jump")
	check(not actor.is_on_floor() and actor.velocity.y > 0, "Airborne entry fixture uses an actual standing jump")
	Input.action_press("crouch")
	await steps(8)
	check(not actor.is_crouching(), "Ctrl does not change the collision shape in midair")
	await steps(90)
	check(actor.is_on_floor() and actor.is_crouching(), "Ctrl held during a jump begins crouch after landing")

func test_standing_head_recovery() -> void:
	# Evaluate the untouched imported standing clip on a separate rested rig.
	# Checking only the selected clip name misses stale constant glTF channels.
	var reference := STANDING_REFERENCE.instantiate()
	arena.add_child(reference)
	var reference_skeleton := reference.find_child("Skeleton3D", true, false) as Skeleton3D
	var reference_animation := reference.get_node("AnimationPlayer") as AnimationPlayer
	reference_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skeleton: Skeleton3D = actor.get_node("Visuals").skeleton
	var neck := skeleton.find_bone("neck_01")
	var original: AnimationLibrary = driver.crouch_clips
	for variant: AnimationLibrary in CROUCH_VARIANTS:
		driver.crouch_clips = variant
		for direction: String in ["idle", "forward", "back", "left", "right"]:
			await reset()
			Input.action_press("crouch")
			if direction != "idle": Input.action_press("move_" + direction)
			await steps(40)
			check(actor.is_crouching() and driver.current_clip == "crouch/" + direction, "Head recovery fixture enters real crouch " + direction)
			var crouched_rotation := skeleton.get_bone_pose_rotation(neck)
			var resting_rotation := reference_skeleton.get_bone_rest(reference_skeleton.find_bone("neck_01")).basis.get_rotation_quaternion()
			check(crouched_rotation.angle_to(resting_rotation) > .08, "Crouch fixture actually changes neck posture")
			Input.action_release("crouch")
			await steps(1)
			var first_rotation := skeleton.get_bone_pose_rotation(neck)
			check(first_rotation.angle_to(crouched_rotation) < .15 and first_rotation.angle_to(resting_rotation) > .02, "Standing neck begins a smooth blend from crouch " + direction)
			await steps(40)
			var standing_clip := "idle" if direction == "idle" else "jog_" + direction
			check(not actor.is_crouching() and driver.current_clip == standing_clip, "Ctrl release enters standing " + standing_clip)
			reference_animation.stop()
			reference_skeleton.reset_bone_poses()
			reference_animation.play(standing_clip, 0.0)
			reference_animation.seek(driver.animation.current_animation_position, true)
			skeleton.force_update_all_bone_transforms()
			reference_skeleton.force_update_all_bone_transforms()
			for bone_name: String in ["neck_01", "head"]:
				var bone := skeleton.find_bone(bone_name)
				var reference_bone := reference_skeleton.find_bone(bone_name)
				var local_error := skeleton.get_bone_pose_rotation(bone).angle_to(reference_skeleton.get_bone_pose_rotation(reference_bone))
				var actual := skeleton.get_bone_global_pose(bone)
				var expected := reference_skeleton.get_bone_global_pose(reference_bone)
				var global_error := actual.basis.get_rotation_quaternion().angle_to(expected.basis.get_rotation_quaternion())
				var position_error := actual.origin.distance_to(expected.origin)
				check(local_error < .002 and global_error < .002 and position_error < .0001, "%s %s returns to fresh standing %s pose (local %.4f rad, global %.4f rad, %.5f m)" % [variant.resource_path.get_file(), bone_name, standing_clip, local_error, global_error, position_error])
			metrics.append({"case": "head_recovery", "variant": variant.resource_path.get_file(), "standing_clip": standing_clip,
				"neck_error": skeleton.get_bone_pose_rotation(neck).angle_to(resting_rotation)})
			release_inputs()
	driver.crouch_clips = original
	reference.queue_free()
	await steps(2)

func test_low_ceiling() -> void:
	await reset()
	var ceiling := box(Vector3(0, 1.48, -4), Vector3(4, .2, 4))
	await steps(3)
	Input.action_press("move_forward")
	await steps(70)
	var blocked_at: Vector3 = actor.position
	check(blocked_at.z > -1.75, "Standing capsule cannot walk into the low tunnel")
	Input.action_press("crouch")
	await steps(70)
	Input.action_release("move_forward")
	await steps(5)
	check(actor.position.z < -3.5 and actor.position.z > -5.5, "Held crouch traverses the real low ceiling entrance")
	check(actor.is_on_floor(), "Tunnel crouch remains supported by the floor")
	var below: Vector3 = actor.position
	Input.action_release("crouch")
	await steps(35)
	check(actor.is_crouching() and is_equal_approx((actor.body_collision_shape.shape as CapsuleShape3D).height, 1.05), "Releasing Ctrl under solid ceiling safely keeps reduced collision")
	check(actor.position.distance_to(below) < .01 and driver.current_clip == "crouch/idle", "Blocked stand does not move the player or play upright idle")
	# The root saved while crouched must not restore a full capsule into the roof.
	# First restore upright elsewhere so stale crouch visuals cannot pass the check.
	actor.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0,
		"transform": Transform3D(Basis.IDENTITY, Vector3(8, -.25, 0))})
	actor.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0,
		"transform": Transform3D(Basis.IDENTITY, below), "crouching": true})
	check(driver.current_clip == "crouch/idle" and absf(actor.camera.position.y - 1.20) < .01, "Crouched checkpoint applies matching pose and eye synchronously")
	var skeleton: Skeleton3D = actor.get_node("Visuals").skeleton
	skeleton.force_update_all_bone_transforms()
	check(skeleton.get_bone_global_pose(skeleton.find_bone("pelvis")).origin.y < .7, "Crouched checkpoint evaluates bent body before the first rendered frame")
	check(actor.camera.global_position.y < 1.38, "Crouched checkpoint eye never starts above the tunnel ceiling")
	await steps(35)
	var restored_capsule := actor.body_collision_shape.shape as CapsuleShape3D
	var capsule_top: float = actor.body_collision_shape.global_position.y + restored_capsule.height * .5
	check(actor.is_crouching() and driver.current_clip == "crouch/idle", "Crouched checkpoint under a roof restores its safe contact pose")
	check(capsule_top < 1.38 and actor.position.distance_to(below) < .02 and actor.is_on_floor(), "Low-ceiling checkpoint restore has no roof overlap, displacement or loss of floor support")
	Input.action_press("move_forward")
	await steps(100)
	Input.action_release("move_forward")
	await steps(35)
	check(actor.position.z < -6.5 and not actor.is_crouching(), "Released crouch stands automatically only after walking clear of ceiling")
	check(is_equal_approx((actor.body_collision_shape.shape as CapsuleShape3D).height, 1.5), "Safe tunnel exit restores standing capsule")
	metrics.append({"case": "low_tunnel", "standing_stop_z": blocked_at.z, "release_z": below.z, "exit_z": actor.position.z})
	ceiling.queue_free()
	await steps(2)

func test_ui_settings_and_grab() -> void:
	await reset()
	Input.action_press("crouch")
	Input.action_press("move_left")
	await steps(20)
	check(actor.enter_ui_mode(), "Normal crouched player can enter UI")
	var at := actor.position
	var eye: Vector3 = actor.camera.position
	var shape: Shape3D = actor.body_collision_shape.shape
	var pose_time: float = driver.animation.current_animation_position
	release_inputs()
	await steps(20)
	check(actor.is_crouching() and actor.position.is_equal_approx(at), "UI preserves crouch state and freezes real movement")
	check(actor.camera.position.is_equal_approx(eye) and actor.body_collision_shape.shape == shape, "UI freezes crouch camera and collision")
	check(is_equal_approx(driver.animation.current_animation_position, pose_time), "UI freezes the crouch animation at its contact pose")
	actor.exit_ui_mode()
	await steps(40)
	check(not actor.is_crouching(), "Closing UI honors a released Ctrl in clear space")
	var menu: Node = actor.get_node("SettingsMenu")
	check(menu.open_menu(), "Settings opens through production menu entry")
	ctrl(true)
	await steps(10)
	check(not actor.is_crouching(), "Ctrl pressed in settings does not enter crouch")
	menu.close_menu()
	await steps(10)
	check(actor.is_gameplay_input_blocked() and not actor.is_crouching(), "Closing settings latches held physical Ctrl")
	ctrl(false)
	await steps(3)
	check(not actor.is_gameplay_input_blocked(), "Releasing Ctrl clears settings input latch")
	ctrl(true)
	await steps(40)
	check(actor.is_crouching(), "A fresh Ctrl press after the latch enters crouch")
	var owner := Node3D.new()
	var anchor := Node3D.new()
	var face := Node3D.new()
	arena.add_child(owner)
	arena.add_child(anchor)
	arena.add_child(face)
	anchor.global_position = actor.execution_contact_position()
	face.global_position = anchor.global_position + Vector3(0, 2, -3)
	check(actor.begin_execution(owner, anchor, face), "Production shared grab can acquire the crouched contact pose")
	shape = actor.body_collision_shape.shape
	pose_time = driver.animation.current_animation_position
	ctrl(false)
	Input.action_press("move_forward")
	await steps(20)
	check(actor.is_grabbed() and actor.is_crouching() and actor.body_collision_shape.shape == shape, "Grab ownership preserves crouched contact volume despite Ctrl release")
	check(is_equal_approx(driver.animation.current_animation_position, pose_time), "Grab ownership freezes the crouch pose")
	release_inputs()
	actor.cancel_execution(owner, "test_complete")
	await steps(40)
	check(not actor.is_grabbed() and not actor.is_crouching(), "Released grab returns to safe standing movement")
	owner.queue_free()
	anchor.queue_free()
	face.queue_free()

func test_injury_and_lifecycle() -> void:
	await reset()
	Input.action_press("crouch")
	await steps(10)
	check(actor.is_crouching(), "Lifecycle reset starts from a real crouch")
	release_inputs()
	actor.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0,
		"transform": Transform3D(Basis.IDENTITY, Vector3(0, .05, 0))})
	check(driver.current_clip == "idle" and absf(actor.camera.position.y - 1.78) < .01 and is_zero_approx(driver.crouch_eye_drop), "Upright checkpoint immediately clears crouch pose and camera offset")
	await steps(40)
	check(not actor.is_crouching() and driver.current_clip == "idle", "Checkpoint restore clears transient crouch and restores upright pose")
	var injured := PlayerBodyState.new()
	injured.sever(&"left_leg")
	actor.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0,
		"transform": Transform3D(Basis.IDENTITY, Vector3(0, .05, 0)), "body": injured.capture(), "crouching": true})
	var skeleton: Skeleton3D = actor.get_node("Visuals").skeleton
	skeleton.force_update_all_bone_transforms()
	check(actor.is_crawling() and not actor.is_crouching() and driver.current_clip == "injury/prone_idle", "Injured checkpoint ignores crouch and selects injury posture immediately")
	check(skeleton.get_bone_global_pose(skeleton.find_bone("pelvis")).origin.y < .23, "Injured checkpoint evaluates prone body before the first rendered frame")
	check(actor.camera.position.y < 1.0 and is_zero_approx(driver.crouch_eye_drop), "Injured checkpoint clears crouch eye offset immediately")
	await reset(Vector3(0, .05, 0), injured.capture())
	Input.action_press("crouch")
	Input.action_press("move_forward")
	await steps(50)
	check(actor.is_crawling() and not actor.is_crouching(), "Missing-leg crawling takes precedence over held Ctrl")
	check(driver.current_clip == "injury/crawl_missing_left_leg", "Held Ctrl preserves the correct injury crawl pose")
	check(absf(actor.velocity.z) < 1.1 and actor.camera.position.y < 1.0, "Injury retains its crawl speed and low view")
	await reset()
	Input.action_press("crouch")
	await steps(10)
	var seat := Node3D.new()
	arena.add_child(seat)
	seat.position = Vector3(8, 0, 0)
	check(actor.enter_seat_mode(seat), "Crouched healthy player can enter a seat through its ownership contract")
	check(not actor.is_crouching() and (actor.body_collision_shape.shape as CapsuleShape3D).height == 1.5, "Seat entry clears crouch and restores standing collision before disabling it")
	release_inputs()
	actor.exit_seat_mode(Vector3(8, .05, 0))
	await steps(40)
	check(not actor.is_crouching() and not actor.body_collision_shape.disabled, "Seat exit restores normal collision without stale crouch")
	seat.queue_free()
	Input.action_press("crouch")
	await steps(10)
	release_inputs()
	actor.take_damage(1000)
	var observed_respawn := false
	for frame in 300:
		await steps(1)
		if not actor.is_player_dead:
			observed_respawn = true
			check(driver.current_clip == "idle" and absf(actor.camera.position.y - 1.78) < .01 and is_zero_approx(driver.crouch_eye_drop), "Respawn immediately restores idle and standing eye without stale crouch offset")
			await steps(1)
			check(not String(driver.current_clip).begins_with("crouch/") and absf(actor.camera.position.y - 1.78) < .01, "First physics frame after respawn preserves standing eye and excludes crouch pose")
			break
	check(observed_respawn, "Real crouch death reaches automatic respawn within its existing deadline")
	check(not actor.is_player_dead and not actor.is_crouching(), "Real crouch death and automatic respawn clear transient state")
	check((actor.body_collision_shape.shape as CapsuleShape3D).height == 1.5 and not actor.body_collision_shape.disabled, "Respawn restores enabled standing capsule")

func run() -> void:
	arena = Node3D.new()
	root.add_child(arena)
	current_scene = arena
	box(Vector3(0, -.5, 0), Vector3(100, 1, 100))
	actor = PLAYER.instantiate()
	arena.add_child(actor)
	driver = actor.get_node("Visuals/Locomotion")
	await test_input_geometry_and_directions()
	await test_standing_head_recovery()
	await test_exertion_and_airborne_entry()
	await test_low_ceiling()
	await test_ui_settings_and_grab()
	await test_injury_and_lifecycle()
	release_inputs()
	print("PLAYER_CROUCH_METRICS ", JSON.stringify(metrics))
	arena.queue_free()
	await steps(2)
	if failures.is_empty(): print("PASS: crouch input, grounded directional movement, smooth head recovery into standing idle/jog for both variants, low ceiling safety, camera, exertion, UI/settings/grab ownership, injury and lifecycle resets")
	quit(0 if failures.is_empty() else 1)
