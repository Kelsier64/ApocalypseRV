extends SceneTree
## Real production wall/input test: animation observes relative carrier movement.
const PLAYER = preload("res://player/player.tscn")
var failures: Array[String] = []
var arena: Node3D
var rv: Node3D
var actor: CharacterBody3D
var driver: Node
var driving := false
var traces: Array = []
var handoffs: Array = []
var neutral_eye := Vector3.ZERO
var maximum_view_separation := 0.0

func _init() -> void: run.call_deferred()
func check(value: bool, note: String) -> void:
	if not value and note not in failures: failures.append(note)
func steps(count: int) -> void:
	for frame in count:
		await physics_frame
		if driving:
			rv.position += -rv.basis.z * 4.0 / 60.0
			rv.rotate_y(.12 / 60.0)
		await process_frame
		if is_instance_valid(actor) and not actor.is_player_dead:
			var skeleton: Skeleton3D = actor.get_node("Visuals").skeleton
			check(skeleton.get_bone_pose_position(skeleton.find_bone("root")).length() <= .501, "Pose-space approach never doubles during animation blends")
			if actor.seated_in == null and not actor.is_grabbed():
				var root_bone := skeleton.find_bone("root")
				var body_shift := skeleton.global_basis * (skeleton.get_bone_global_pose(root_bone).origin - skeleton.get_bone_global_rest(root_bone).origin)
				var eye_shift: Vector3 = actor.camera.global_position - actor.to_global(neutral_eye)
				var separation := body_shift.distance_to(eye_shift)
				maximum_view_separation = maxf(maximum_view_separation, separation)
				check(separation < .001, "Camera follows the rendered body through climb and recovery without separation")
func spawn_actor() -> void:
	actor = PLAYER.instantiate()
	actor.position = rv.to_global(Vector3(2.65, -.8, 0))
	actor.rotation.y = rv.rotation.y + PI / 2
	arena.add_child(actor)
	driver = actor.get_node("Visuals/Locomotion")
	neutral_eye = actor.camera.position
	await steps(10)
func start_climb() -> void:
	Input.action_press("move_forward")
	for frame in 90:
		await steps(1)
		if driver.current_clip == "climb_up": break
	check(driver.current_clip == "climb_up", "Actual RV wall and W select upward climbing")
	await steps(8)
	Input.action_release("move_forward")
	await steps(10)
	check(driver.current_clip == "climb_hold", "Releasing W holds wall without cycling")
func record(label: String) -> void:
	traces.append({"case": label, "clip": driver.current_clip, "position_in_rv": str(rv.to_local(actor.global_position)), "controller_velocity": str(actor.velocity)})

func run() -> void:
	check(Engine.physics_ticks_per_second == 60, "Climb presentation preserves 60 Hz")
	arena = Node3D.new()
	root.add_child(arena)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(collision)
	arena.add_child(floor_body)
	var vehicle: Node3D = preload("res://rv/new_rv.tscn").instantiate()
	arena.add_child(vehicle)
	rv = vehicle.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	rv.position.y = 1.2
	await spawn_actor()
	var camera_pose: Transform3D = actor.camera.transform
	await start_climb()
	record("hold")
	var wall_point: Vector3 = actor.climb_wall_probe.get_collision_point()
	check((actor.camera.global_position - wall_point).dot(actor.active_wall_normal) > .08, "Aligned eye remains outside the wall")
	for pitch in [-60.0, 30.0]:
		actor.camera.rotation.x = deg_to_rad(pitch)
		actor.rotate_y(.15)
		await steps(3)
		check(is_equal_approx(actor.camera.rotation.x, deg_to_rad(pitch)), "Climb alignment preserves free-look pitch")
		actor.rotate_y(-.15)
	actor.camera.basis = camera_pose.basis
	var anchor: Vector3 = rv.to_local(actor.global_position)
	driving = true
	await steps(40)
	check(driver.current_clip == "climb_hold", "Car translation and turning alone never cycle climbing")
	check(rv.to_local(actor.global_position).distance_to(anchor) < .03, "Holding retains carrier-relative anchor")
	record("moving_car_hold")
	for direction in ["left", "right"]:
		Input.action_press("move_" + direction)
		await steps(10)
		check(driver.current_clip == "climb_" + direction, "Actual lateral motion selects " + direction)
		check(actor.velocity.is_zero_approx(), "Climb animation works while controller velocity remains zero")
		record(direction)
		Input.action_release("move_" + direction)
		await steps(8)
		check(driver.current_clip == "climb_hold", "Lateral stop returns to holding")
	driving = false
	actor.enter_ui_mode()
	var time: float = driver.animation.current_animation_position
	await steps(15)
	check(is_equal_approx(time, driver.animation.current_animation_position), "UI freezes held pose")
	actor.exit_ui_mode()
	Input.action_press("move_forward")
	var seen_exit := false
	for frame in 180:
		await steps(1)
		if driver.current_clip == "climb_exit":
			seen_exit = true
			break
	Input.action_release("move_forward")
	check(seen_exit and actor.is_on_floor(), "Actual roof transfer starts arm recovery")
	record("roof_transfer")
	await steps(30)
	check(driver.current_clip == "idle", "Roof recovery returns to ground locomotion")
	check(driver.climb_pose_offset.is_zero_approx(), "Roof recovery clears the presentation offset")
	check(actor.camera.transform.is_equal_approx(camera_pose), "Roof recovery restores neutral camera position and preserves view rotation")
	actor.queue_free()
	await steps(2)
	# Fractional contact heights cover a roof transfer whose floor flag is
	# published on the following frame; presentation must not miss recovery.
	for height in [-.2, .017]:
		await spawn_actor()
		actor.global_position = rv.to_global(Vector3(2.65, height, 0))
		actor.velocity = Vector3.ZERO
		Input.action_press("move_forward")
		var entered := false
		for frame in 150:
			await steps(1)
			entered = entered or actor.locomotion_state == actor.LocomotionState.CLIMBING
			if entered and actor.locomotion_state == actor.LocomotionState.NORMAL: break
		Input.action_release("move_forward")
		check(entered and driver.current_clip == "climb_exit", "Fractional-height roof transfer retains recovery before floor flags settle")
		record("fractional_roof_" + str(height))
		await steps(30)
		check(driver.current_clip == "idle", "Fractional-height recovery settles to idle")
		actor.queue_free()
		await steps(2)
	for release_action in ["jump", "move_back"]:
		await spawn_actor()
		await start_climb()
		Input.action_press(release_action)
		await steps(2)
		Input.action_release(release_action)
		check(actor.locomotion_state == actor.LocomotionState.NORMAL and driver.current_clip == "jump_fall", release_action + " detaches directly into falling")
		record(release_action + "_detach")
		actor.queue_free()
		await steps(2)
	# These actual wall trajectories retain the 25 mm gate. The separate jump
	# high-drop failures remain documented; these cases do not supersede them.
	for delay in [0, 6, 12]:
		await spawn_actor()
		await start_climb()
		Input.action_press("move_forward")
		await steps(delay + 1)
		var clip: String = driver.current_clip
		var eye_before_death: Vector3 = actor.camera.global_position
		actor.take_damage(1000)
		Input.action_release("move_forward")
		await steps(2)
		check(actor.is_player_dead and driver.suspended, "Climbing death suspends animation for physics")
		check(actor.camera.global_position.distance_to(eye_before_death) < .08, "Death camera handoff does not snap back by the climb approach distance")
		var peak := 0.0
		var bone := ""
		for frame in 90:
			await steps(1)
			for link: Dictionary in actor.ragdoll_control.links:
				var gap: float = (link.parent.global_transform * link.parent_frame).origin.distance_to((link.child.global_transform * link.child.joint_offset).origin)
				if gap > peak:
					peak = gap
					bone = link.child.get("bone_name")
		handoffs.append({"delay_frames": delay, "clip": clip, "peak_gap_m": peak, "peak_bone": bone, "stability_pass": peak < .025})
		check(peak < .025, "Actual climb death retains joints below 25 mm")
		await steps(70)
		check(not actor.is_player_dead and not driver.suspended, "Climb death respawns and resumes presentation")
		check(actor.camera.position.is_equal_approx(neutral_eye), "Respawn removes the temporary climb camera offset")
		actor.queue_free()
		await steps(2)
	print("PLAYER_CLIMB_TRACES ", JSON.stringify(traces))
	print("PLAYER_CLIMB_HANDOFFS ", JSON.stringify(handoffs))
	print("PLAYER_CLIMB_MAX_VIEW_SEPARATION_M ", maximum_view_separation)
	for failure in failures: push_error(failure)
	arena.queue_free()
	await steps(2)
	if failures.is_empty(): print("PASS: real wall climb, hold, carrier motion, traversal, roof recovery, detach, UI and three death/respawn handoffs below 25 mm")
	quit(0 if failures.is_empty() else 1)
