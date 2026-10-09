extends SceneTree
## Production rig, navigation and physical shell; RV motion is scripted here.
## Wheel-driven vehicle behavior is validated separately in the playground.
var failures: Array[String] = []
var world: Node3D
var giant: SlenderSpeaker
var map: RID

class Vehicle extends RigidBody3D:
	func add_item(_item): pass
	func deduct_materials(_cost): pass
	func vehicle_impact_point_velocity(point: Vector3) -> Vector3:
		return linear_velocity + angular_velocity.cross(point - global_position)

func _init() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func shape(body: Node3D, size: Vector3, center := Vector3.ZERO) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.position = center
	body.add_child(collision)

func frames(count := 2) -> void:
	for tick in count: await physics_frame

func make_vehicle(point: Vector3, speed := 0.0) -> Vehicle:
	var rv := Vehicle.new()
	rv.freeze = true
	rv.position = point
	rv.linear_velocity = Vector3(0, 0, -speed)
	shape(rv, Vector3(2.4, 2.4, 5.0), Vector3.UP * 1.2)
	world.add_child(rv)
	rv.add_to_group(Groups.RV)
	return rv

func panel(rv: Vehicle, point: Vector3, size := Vector3(1.2, 2.0, .15)) -> RVStructurePanel:
	var shell := RVStructurePanel.new()
	shell.position = point
	shape(shell, size)
	rv.add_child(shell)
	return shell

func step_vehicle(rv: Vehicle, delta: float) -> void:
	rv.position += rv.linear_velocity * delta
	if not rv.angular_velocity.is_zero_approx():
		rv.rotation.y += rv.angular_velocity.y * delta

func local_bone(name: String) -> Transform3D:
	return giant.global_transform.affine_inverse() * giant.visual.bone_world(name)

func prepare(rv: Vehicle, speed: float) -> void:
	giant.position = rv.position + Vector3(0, 0, 6.5)
	giant.rotation = Vector3.ZERO
	giant.velocity = Vector3(0, 0, -speed)
	giant.target_player = null
	giant.target_vehicle = rv
	giant._follow_plan.clear()
	giant._sense_remaining = 100.0
	giant._visible_target = true
	giant._set_phase(SlenderSpeaker.Phase.CHASE)
	giant._sample("idle_play", 0.0)

func check_follow() -> void:
	var rv := make_vehicle(Vector3(0, 0, 40), 8.0)
	panel(rv, Vector3(0, 2.0, 2.6))
	prepare(rv, 8.0)
	await frames()
	var minimum_gap := INF
	var maximum_gap := 0.0
	for tick in 360:
		step_vehicle(rv, 1.0 / 60.0)
		await physics_frame
		# Test follow control in isolation so shell destruction cannot remove its target.
		var desired: Vector3 = giant._follow_vehicle(1.0 / 60.0)
		giant._move_swept(desired, 1.0 / 60.0)
		var gap := giant.position.z - rv.position.z - 2.5
		minimum_gap = minf(minimum_gap, gap)
		maximum_gap = maxf(maximum_gap, gap)
		for collision in giant.get_slide_collision_count():
			check(RVConnection.resolve(giant.get_slide_collision(collision).get_collider()) != rv, "Matched-speed follow never rams physical RV shell")
		check(giant.velocity.slide(Vector3.UP).length() <= 60.0 / 3.6 + .001, "Following stays capped at 60 km/h")
		if tick > 60:
			check((giant.velocity - rv.linear_velocity).slide(Vector3.UP).length() < .5, "Close follow matches 8 m/s RV with low relative velocity")
	check(minimum_gap > 3.7 and maximum_gap < 4.3, "Six-second matched-speed chase retains four metres of nominal RV root clearance")
	check(giant._follow_plan.get("can_attack", false), "Wider nominal pursuit gap still permits a real shell attack")
	print("FOLLOW clearance=", minimum_gap, "..", maximum_gap, " velocity=", giant.velocity)
	# A tree can stop the RV in one step. Even before ordinary 6 m/s² braking
	# catches up, the collision envelope must prevent the giant ramming it.
	rv.linear_velocity = Vector3.ZERO
	var stop_clearance := INF
	# The wider pursuit slot also needs time to back away after emergency
	# braking near the shell; retain collision checks throughout that retreat.
	for tick in 480:
		await physics_frame
		var desired: Vector3 = giant._follow_vehicle(1.0 / 60.0)
		giant._move_swept(desired, 1.0 / 60.0)
		var clearance := giant.position.z - rv.position.z - 2.5
		stop_clearance = minf(stop_clearance, clearance)
		for collision in giant.get_slide_collision_count():
			check(RVConnection.resolve(giant.get_slide_collision(collision).get_collider()) != rv, "Suddenly stopped RV is never physically rammed by its pursuing giant")
	check(stop_clearance >= 1.25 - .001, "Sudden RV stop retains at least 1.25 m root clearance")
	check(giant.velocity.slide(Vector3.UP).length() < .05, "Pursuing giant stops behind abruptly stationary RV")
	var settled_clearance := giant.position.z - rv.position.z - 2.5
	check(settled_clearance > 3.7 and settled_clearance < 4.3, "Emergency retreat restores four metres of nominal RV root clearance")
	check(giant._follow_plan.get("can_attack", false), "Safe settled position after emergency stop permits another attack")
	print("FOLLOW sudden-stop minimum_clearance=", stop_clearance, " settled_clearance=", settled_clearance, " velocity=", giant.velocity)
	rv.queue_free()
	await frames()

func check_comfortable_approach() -> void:
	var rv := make_vehicle(Vector3(0, 0, 40), 8.0)
	panel(rv, Vector3(0, 2.0, 2.6))
	prepare(rv, giant.settings.chase_speed)
	giant.position = rv.position + Vector3(0, 0, 42.5)
	await frames()
	var first_braking_gap := INF
	var maximum_deceleration := 0.0
	var minimum_gap := INF
	var previous_speed := giant.velocity.slide(Vector3.UP).length()
	for tick in 1200:
		step_vehicle(rv, 1.0 / 60.0)
		await physics_frame
		var gap_before := giant.position.z - rv.position.z - 2.5
		var desired := giant._follow_vehicle(1.0 / 60.0)
		giant._move_swept(desired, 1.0 / 60.0)
		var speed := giant.velocity.slide(Vector3.UP).length()
		var deceleration := (previous_speed - speed) * 60.0
		if deceleration > .01 and is_inf(first_braking_gap): first_braking_gap = gap_before
		if tick > 1:
			maximum_deceleration = maxf(maximum_deceleration, deceleration)
			check(deceleration <= 2.01, "Ordinary 60 km/h catch-up sheds at most 2 m/s² while matching the RV")
		previous_speed = speed
		var gap := giant.position.z - rv.position.z - 2.5
		minimum_gap = minf(minimum_gap, gap)
		check(gap > 3.7, "Early comfortable braking never overshoots the four-metre pursuit slot")
		for collision in giant.get_slide_collision_count():
			check(RVConnection.resolve(giant.get_slide_collision(collision).get_collider()) != rv, "Comfortable high-speed approach never contacts the physical RV shell")
	var settled_gap := giant.position.z - rv.position.z - 2.5
	check(not is_inf(first_braking_gap) and first_braking_gap > 8.0, "High-speed catch-up begins braking while still well outside the RV attack range")
	check(settled_gap > 3.7 and settled_gap < 4.3, "Comfortable high-speed approach settles at four metres of RV root clearance")
	check((giant.velocity - rv.linear_velocity).slide(Vector3.UP).length() < .1, "Comfortable approach settles to the RV's actual 8 m/s velocity")
	print("COMFORTABLE_APPROACH first_braking_gap=", first_braking_gap, " max_deceleration=", maximum_deceleration, " minimum_gap=", minimum_gap, " settled_gap=", settled_gap, " velocity=", giant.velocity)
	rv.queue_free()
	await frames()

func check_recovery_posture(rv: Vehicle) -> void:
	var bones := ["pelvis", "spine", "chest", "neck", "hand.R", "hand.L", "foot.R", "foot.L"]
	var previous: Dictionary = {}
	for bone in bones: previous[bone] = local_bone(bone)
	var maximum_upper_step := 0.0
	var maximum_foot_step := 0.0
	for tick in 180:
		if giant.phase != SlenderSpeaker.Phase.RECOVER: break
		step_vehicle(rv, 1.0 / 60.0)
		await physics_frame
		giant._physics_process(1.0 / 60.0)
		for bone in bones:
			var current := local_bone(bone)
			var step := current.origin.distance_to(previous[bone].origin)
			if String(bone).begins_with("foot."):
				maximum_foot_step = maxf(maximum_foot_step, step)
				check(step < .45, "Moving smash recovery keeps actual %s continuous through its final frame" % bone)
			else:
				maximum_upper_step = maxf(maximum_upper_step, step)
				check(step < .25, "Moving smash recovery keeps actual %s continuous instead of snapping upright" % bone)
			previous[bone] = current
	check(giant.phase == SlenderSpeaker.Phase.CHASE, "Completed moving smash recovery returns to chase")
	var completed_pose := giant._capture_pose()
	var completed: Dictionary = {}
	for bone in bones: completed[bone] = local_bone(bone)
	# Compare against the production gait at precisely the same phase, speed
	# and actor transform, then restore the actually observed recovery pose.
	giant._sample_gait(0.0, giant.velocity.slide(Vector3.UP).length())
	for bone in bones:
		var expected := local_bone(bone)
		var actual: Transform3D = completed[bone]
		check(actual.origin.distance_to(expected.origin) < .01 and actual.basis.get_rotation_quaternion().angle_to(expected.basis.get_rotation_quaternion()) < .005, "Completed moving recovery matches the ongoing production gait for " + bone)
	giant._blend_from_pose(completed_pose, 0.0)
	giant._begin_smash()
	for bone in bones:
		check(local_bone(bone).origin.distance_to(completed[bone].origin) < .001, "Next moving attack preserves recovered production " + bone + " at entry")
	step_vehicle(rv, 1.0 / 60.0)
	await physics_frame
	giant._physics_process(1.0 / 60.0)
	check(giant.phase == SlenderSpeaker.Phase.SMASH and giant.velocity.slide(Vector3.UP).length() > 7.0, "Next smash begins while continuing matched-speed pursuit")
	for bone in ["pelvis", "spine", "chest", "neck"]:
		check(local_bone(bone).origin.distance_to(completed[bone].origin) < .25, "Next smash first frame keeps the recovered moving " + bone + " posture")
	print("RECOVERY_POSTURE max_upper_step=", maximum_upper_step, " max_foot_step=", maximum_foot_step)

func check_moving_windup() -> void:
	var rv := make_vehicle(Vector3(0, 0, 40), 8.0)
	var shell := panel(rv, Vector3(0, 2.0, 2.6))
	var leg_bones := ["pelvis", "thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R"]
	for start_phase in [0.0, .23, .51, .79]:
		prepare(rv, 8.0)
		await frames()
		giant._gait_phase = start_phase
		giant._gait_blend = .5
		giant._locomotion_clip = "run"
		giant._sample_gait(0.0, 8.0)
		var entry_hand := local_bone("hand.R").origin
		var entry_pelvis := local_bone("pelvis").origin
		giant._begin_smash()
		var maximum_leg_error := 0.0
		var minimum_forward_lean := INF
		var maximum_pelvis_rise := 0.0
		for tick in 79:
			# Exercise the complete runtime windup, including reach correction,
			# while holding the actor/RV transforms fixed for local-pose checks.
			giant.phase_elapsed = float(tick) / 60.0
			giant._advance_smash(0.0 if tick == 0 else 1.0 / 60.0)
			check(giant.phase == SlenderSpeaker.Phase.SMASH and not shell.is_destroyed, "Moving windup remains active without early shell damage at gait phase %.2f" % start_phase)
			var actual_pose := giant._capture_pose()
			var actual_legs: Dictionary = {}
			for bone in leg_bones: actual_legs[bone] = local_bone(bone)
			var pelvis := local_bone("pelvis").origin
			var chest := local_bone("chest").origin
			var forward_lean := -(chest.z - pelvis.z)
			minimum_forward_lean = minf(minimum_forward_lean, forward_lean)
			maximum_pelvis_rise = maxf(maximum_pelvis_rise, pelvis.y - entry_pelvis.y)
			check(forward_lean > .005, "Moving windup keeps the chest leaning forward instead of straightening or leaning backward")
			check(pelvis.y - entry_pelvis.y < .01, "Moving windup cannot raise the pelvis out of its ongoing gait")
			giant._sample_gait(0.0, giant.velocity.slide(Vector3.UP).length())
			for bone in leg_bones:
				var expected := local_bone(bone)
				var actual: Transform3D = actual_legs[bone]
				var error := actual.origin.distance_to(expected.origin)
				maximum_leg_error = maxf(maximum_leg_error, error)
				check(error < .01 and actual.basis.get_rotation_quaternion().angle_to(expected.basis.get_rotation_quaternion()) < .005, "Moving windup preserves live-gait " + bone + " throughout 0..1.3 seconds at initial phase %.2f" % start_phase)
			giant._blend_from_pose(actual_pose, 0.0)
		var raised_hand := local_bone("hand.R").origin
		check(raised_hand.y > entry_hand.y + 2.0 and raised_hand.y > local_bone("chest").origin.y, "Moving windup still raises the actual striking hand while the legs keep walking")
		print("MOVING_WINDUP initial_phase=", start_phase, " max_leg_error=", maximum_leg_error, " min_forward_lean=", minimum_forward_lean, " max_pelvis_rise=", maximum_pelvis_rise, " hand_rise=", raised_hand.y - entry_hand.y)
	rv.queue_free()
	await frames()

func check_attack_gait() -> void:
	# Fix the upper-body strike sample and actor transform to exclude attack
	# crouching and world translation from the gait measurements.
	var cadence: Array[float] = []
	for speed in [7.9, 8.0, 8.2]:
		giant.velocity = Vector3(0, 0, -speed)
		giant._gait_phase = .36
		giant._gait_blend = 0.0
		giant._locomotion_clip = "walk"
		for tick in 60: giant._sample_smash_motion(1.0, 1.0 / 60.0)
		var phase_travel := 0.0
		var previous_phase := giant._gait_phase
		var previous_right := local_bone("foot.R").origin
		var previous_left := local_bone("foot.L").origin
		var window_motion := 0.0
		var minimum_motion := INF
		for tick in 120:
			giant._sample_smash_motion(1.0, 1.0 / 60.0)
			var advance := fposmod(giant._gait_phase - previous_phase, 1.0)
			check(advance > .0001 and advance < .1, "Fixed upper-body moving smash preserves continuous leg phase at %.2f m/s" % speed)
			phase_travel += advance
			previous_phase = giant._gait_phase
			var right := local_bone("foot.R").origin
			var left := local_bone("foot.L").origin
			window_motion += right.distance_to(previous_right) + left.distance_to(previous_left)
			previous_right = right
			previous_left = left
			if (tick + 1) % 15 == 0:
				minimum_motion = minf(minimum_motion, window_motion)
				window_motion = 0.0
		check(phase_travel > 1.0 and minimum_motion > .04, "Actual smash legs complete a stride within two seconds without freezing at %.2f m/s" % speed)
		cadence.append(phase_travel)
		print("ATTACK_GAIT speed=", speed, " cycles_2s=", phase_travel, " min_foot_motion_250ms=", minimum_motion)
	check(absf(cadence[1] / cadence[0] - 1.0) < .2 and absf(cadence[2] / cadence[0] - 1.0) < .2, "Moving attack stride cadence stays continuous across 8 m/s")

func check_attack(speed: float, escape := false, block := false) -> void:
	var rv := make_vehicle(Vector3(0, 0, 40), speed)
	# The chassis carries the floor; independent panels own the upper shell.
	rv.get_child(0).shape.size = Vector3(2.4, .3, 5.0)
	rv.get_child(0).position.y = .15
	var first := panel(rv, Vector3(0, 2.0, 2.6))
	var second := panel(rv, Vector3(0, 2.0, 2.3))
	var roof := panel(rv, Vector3(0, 2.45, 0), Vector3(2.6, .15, 5.2))
	prepare(rv, speed)
	await frames()
	giant._begin_smash()
	check(absf(giant.velocity.z + speed) < .001, "Smash phase entry preserves world velocity at %s m/s" % speed)
	var previous_foot := local_bone("foot.R")
	var previous_gait := giant._gait_phase
	var gait_travel := 0.0
	var last_gait := previous_gait
	var foot_motion := 0.0
	var locked := Vector3.ZERO
	var blocker: StaticBody3D
	for tick in 109:
		step_vehicle(rv, 1.0 / 60.0)
		await physics_frame
		giant._physics_process(1.0 / 60.0)
		gait_travel += fposmod(giant._gait_phase - last_gait, 1.0)
		last_gait = giant._gait_phase
		var current_foot := local_bone("foot.R")
		foot_motion = maxf(foot_motion, current_foot.origin.distance_to(previous_foot.origin))
		if tick < 107: check(not first.is_destroyed and not second.is_destroyed and not roof.is_destroyed, "Smash windup cannot damage nearby shell early")
		if tick == 77:
			locked = giant._strike_point
			check(giant._strike_locked, "World impact point locks at 1.3 seconds")
			var predicted: Vector3 = giant._attack_surface() + (rv.linear_velocity * .5 if speed > 0.0 else Vector3.ZERO)
			check(locked.distance_to(predicted) < .05, "Lock predicts actual shell surface half a second ahead")
			if escape:
				# A sudden acceleration and turn after lock leave the predicted world point.
				rv.linear_velocity = Vector3(16, 0, -speed)
				rv.angular_velocity = Vector3(0, 1.0, 0)
			if block:
				blocker = StaticBody3D.new()
				shape(blocker, Vector3(.3, .3, .3))
				world.add_child(blocker)
				blocker.global_position = giant._bone_position("socket_strike_R")
		if tick > 77: check(giant._strike_point.distance_to(locked) < .001, "Locked impact stays at fixed world point despite body and RV motion")
		if speed > 0.0 and not escape:
			check(giant.velocity.slide(Vector3.UP).length() > 7.0, "Moving smash keeps chasing instead of stopping")
	check(giant.phase == SlenderSpeaker.Phase.RECOVER, "One complete smash enters recovery")
	if speed > 0.0:
		check(foot_motion > .08 and not is_equal_approx(previous_gait, giant._gait_phase), "Actual production feet and gait continue through moving smash")
		if not escape: check(gait_travel > .9, "Moving 8 m/s smash maintains a full stride within two seconds")
	if escape or block:
		check(not first.is_destroyed and not second.is_destroyed and not roof.is_destroyed, "Post-lock escape or real wall prevents proximity shell damage")
		if block: check(giant._strike_contact_collider == blocker, "Intervening wall is the actual swept first collider")
	else:
		var removed := int(first.is_destroyed) + int(second.is_destroyed) + int(roof.is_destroyed)
		check(removed == 1, "Actual swept strike destroys exactly one first shell panel at impact")
		check(giant._strike_contact_collider is RVStructurePanel and giant._strike_contact_collider.is_destroyed, "Destroyed shell is the actual first swept collider")
	if speed > 0.0 and not escape:
		var before_position := giant.position
		var before_foot := local_bone("foot.R")
		for tick in 60:
			step_vehicle(rv, 1.0 / 60.0)
			await physics_frame
			giant._physics_process(1.0 / 60.0)
		check(giant.phase == SlenderSpeaker.Phase.RECOVER and giant.position.distance_to(before_position) > 6.0, "Smash recovery retains moving world position and velocity")
		check(local_bone("foot.R").origin.distance_to(before_foot.origin) > .05, "Production leg motion continues during smash recovery")
		if not block: await check_recovery_posture(rv)
	if speed > 0.0:
		# Hold authored strike time and actor transform fixed: only walking can
		# move these feet, so upper-body crouch cannot satisfy this assertion.
		giant._sample_smash_motion(1.0, 0.0)
		var right := local_bone("foot.R").origin
		var left := local_bone("foot.L").origin
		giant._sample_smash_motion(1.0, .3)
		check(local_bone("foot.R").origin.distance_to(right) + local_bone("foot.L").origin.distance_to(left) > .1, "Moving strike layers actual walking feet over fixed upper-body attack pose")
		if not escape and not block: check_attack_gait()
	print("ATTACK speed=", speed, " escape=", escape, " blocked=", block, " panels=", [first.is_destroyed, second.is_destroyed, roof.is_destroyed], " foot_motion=", foot_motion)
	if blocker != null: blocker.queue_free()
	rv.queue_free()
	await frames()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	shape(floor_body, Vector3(400, .2, 400), Vector3(0, -.1, 0))
	world.add_child(floor_body)
	giant = load("res://enemies/slender_speaker/slender_speaker.tscn").instantiate()
	world.add_child(giant)
	giant.set_physics_process(false)
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-190, 0, -190), Vector3(-190, 0, 190), Vector3(190, 0, 190), Vector3(190, 0, -190)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)
	region.set_navigation_map(map)
	giant.set_giant_navigation_map(map)
	await frames()
	NavigationServer3D.map_force_update(map)
	check(giant.visual.available, "Production GLB, sockets and leg bones loaded")
	await check_follow()
	await check_comfortable_approach()
	await check_moving_windup()
	await check_attack(0.0)
	await check_attack(8.0)
	await check_attack(8.0, true)
	await check_attack(8.0, false, true)
	giant.set_giant_navigation_map(RID())
	NavigationServer3D.free_rid(map)
	world.queue_free()
	await frames()
	if failures.is_empty(): print("PASS: Slender Speaker moving attacks")
	else: print("FAIL Slender Speaker moving attacks: ", failures.size())
	quit(0 if failures.is_empty() else 1)
