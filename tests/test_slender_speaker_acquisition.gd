extends SceneTree
## Production Player/RV target shapes, authored fingers and extraction ownership.
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const PLAYER := preload("res://player/player.tscn")
const VEHICLE := preload("res://rv/new_rv.tscn")
const ARM_POSE_METRICS := preload("res://tests/support/slender_speaker_arm_pose_metrics.gd")
var failures: Array[String] = []
var world: Node3D
var giant: SlenderSpeaker
var player: CharacterBody3D
var vehicle: Node3D
var chassis: Chassis

func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)
func frames(count := 2) -> void:
	for i in count:
		await physics_frame
		await process_frame

func reset_player(point: Vector3) -> void:
	giant._cancel_execution("fixture_reset")
	if player.is_grabbed(): player.grab_control.end("fixture_reset")
	player.ragdoll_control.stop()
	player.is_player_dead = false
	player.restore_checkpoint_state({"items": [], "slot": 0, "health": 100.0, "transform": Transform3D(Basis.IDENTITY, point)})
	player.set_physics_process(false)
	player.grab_control.immunity = 0.0
	giant.target_player = player
	giant.target_vehicle = null
	giant._strike_resolved = false
	giant.velocity = Vector3.ZERO
	giant.rotation = Vector3.ZERO

func pose_giant(offset: Vector3) -> void:
	var contact: Vector3 = player.execution_contact_position()
	giant.global_position = contact.slide(Vector3.UP) + offset
	var direction := (contact - giant.global_position).slide(Vector3.UP).normalized()
	giant.rotation.y = atan2(-direction.x, -direction.z)
	giant._sample("idle_play", 0.0)

func settle_pose() -> void:
	var locomotion: Node = player.get_node("Visuals/Locomotion")
	if player.is_crawling() or player.seated_in != null or player.locomotion_state == player.LocomotionState.CLIMBING:
		locomotion._physics_process(.7)
	else:
		locomotion.animation.play("locomotion/idle", 0.0)
		locomotion.animation.advance(0.0)
	player.get_node("Visuals").skeleton.force_update_all_bone_transforms()

func pose_metrics() -> Dictionary:
	var previous: Dictionary = {}
	for bone in ["hand.R", "hand.L", "forearm.R", "forearm.L"]: previous[bone] = giant.visual.bone_world(bone)
	var joint_metrics := ARM_POSE_METRICS.new_metrics()
	ARM_POSE_METRICS.observe(joint_metrics, giant.visual.skeleton)
	return {"previous": previous, "joint_metrics": joint_metrics, "hand_step": 0.0, "elbow_step": 0.0, "angle": 0.0, "angle_time": 0.0, "angle_bone": "", "axis_angle": 0.0, "radial_roll": 0.0, "finger_error": 0.0, "arm_separation": INF}

func record_pose(metrics: Dictionary) -> void:
	ARM_POSE_METRICS.observe(metrics.joint_metrics, giant.visual.skeleton)
	var previous: Dictionary = metrics.previous
	var before := previous.duplicate()
	for bone in previous:
		var current: Transform3D = giant.visual.bone_world(bone)
		var old: Transform3D = before[bone]
		if String(bone).begins_with("forearm") and current.origin.distance_to(old.origin) > .8:
			var side := String(bone).get_slice(".", 1)
			print("IK_POLE_SPIKE time=", giant.phase_elapsed, " side=", side, " shoulder=", giant._bone_position("upper_arm." + side), " old_elbow=", old.origin, " elbow=", current.origin, " old_wrist=", before["hand." + side].origin, " wrist=", giant._bone_position("hand." + side))
		var key := "hand_step" if String(bone).begins_with("hand") else "elbow_step"
		metrics[key] = maxf(metrics[key], current.origin.distance_to(old.origin))
		var angle := rad_to_deg(old.basis.get_rotation_quaternion().angle_to(current.basis.get_rotation_quaternion()))
		if angle > metrics.angle:
			metrics.angle = angle
			metrics.angle_time = giant.phase_elapsed
			metrics.angle_bone = bone
			if String(bone).begins_with("forearm"):
				var side := String(bone).get_slice(".", 1)
				var old_axis: Vector3 = (before["hand." + side].origin - old.origin).normalized()
				var axis := (giant._bone_position("hand." + side) - current.origin).normalized()
				var old_radial := (Basis(Quaternion(old_axis, axis)) * old.basis.x).slide(axis).normalized()
				var radial := current.basis.x.slide(axis).normalized()
				metrics.axis_angle = rad_to_deg(old_axis.angle_to(axis))
				metrics.radial_roll = rad_to_deg(absf(old_radial.signed_angle_to(radial, axis)))
		previous[bone] = current
	var skeleton: Skeleton3D = giant.visual.skeleton
	for index in skeleton.get_bone_count():
		if not skeleton.get_bone_name(index).begins_with("finger_"): continue
		var parent := skeleton.get_bone_parent(index)
		var actual := skeleton.get_bone_global_pose(index).origin.distance_to(skeleton.get_bone_global_pose(parent).origin)
		metrics.finger_error = maxf(metrics.finger_error, absf(actual - skeleton.get_bone_rest(index).origin.length()))
	var closest := Geometry3D.get_closest_points_between_segments(giant._bone_position("forearm.R"), giant._bone_position("hand.R"), giant._bone_position("forearm.L"), giant._bone_position("hand.L"))
	metrics.arm_separation = minf(metrics.arm_separation, closest[0].distance_to(closest[1]))

func report_pose(label: String, metrics: Dictionary, seated := false) -> void:
	print(label, " hand_step=", metrics.hand_step, " elbow_step=", metrics.elbow_step, " joint_angle_deg=", metrics.angle, " angle_time=", metrics.angle_time, " angle_bone=", metrics.angle_bone, " axis_angle=", metrics.axis_angle, " radial_roll=", metrics.radial_roll, " finger_length_error=", metrics.finger_error, " forearm_separation=", metrics.arm_separation)
	check(metrics.finger_error < .001, label + " preserves every authored finger segment length")
	check(metrics.hand_step < .45 and metrics.elbow_step < .5 and metrics.angle < 15.0, label + " has no wrist or elbow frame discontinuity at 60Hz")
	var joints: Dictionary = metrics.joint_metrics
	print(label, " ANATOMICAL_JOINTS ", JSON.stringify(joints))
	check(joints.upper_roll_degrees <= 110.0, label + " avoids a shoulder half turn relative to the clavicle")
	check(joints.elbow_plane_degrees <= 35.0, label + " bends both elbows within their authored hinge planes")
	check(joints.wrist_roll_degrees <= 30.0, label + " keeps palm and forearm radial frames within 30 degrees")
	if seated:
		check(metrics.arm_separation >= .15, label + " keeps actual forearm segments separated in 3D")

func grab() -> bool:
	giant._begin_grab()
	var metrics := pose_metrics()
	var seated := player.seated_in != null
	for i in 60:
		giant.phase_elapsed = float(i + 1) / 60.0
		giant._advance_grab()
		record_pose(metrics)
		if giant.phase != SlenderSpeaker.Phase.GRAB: break
	report_pose("GRAB_CONTINUITY", metrics, seated and player.is_executing())
	print("ACQUISITION pose=", player.global_position, " contact=", player.execution_contact_position(), " phase=", giant.phase, " blocked=", giant._grab_blocked, " hands=", giant._grab_hands_touched)
	if giant._grab_blocked: print("BLOCKERS ", giant._grab_blocking_hits)
	return player.is_executing()

func capture_path_clear() -> bool:
	# Independently remove the player from the winning probe and test only
	# solid geometry through its actual contact fraction, including old blockers.
	var contact: Dictionary = giant._grab_capture_sweep
	if contact.is_empty(): return false
	var excluded: Array[RID] = [player.get_rid()]
	var seat: RID = player.grab_control.execution_seat_rid
	if seat.is_valid(): excluded.append(seat)
	var from: Vector3 = contact.from
	var end := from.lerp(contact.to, float(contact.fraction))
	return giant.sweep_hand(from, end, float(contact.radius), excluded).is_empty()

func lift_driver(label: String) -> void:
	var metrics := pose_metrics()
	print(label, " capture_socket_offset=", giant._execution_socket_offset)
	for tick in 84:
		giant.phase_elapsed = float(tick + 1) / 60.0
		giant._advance_execution()
		player._physics_process(1.0 / 60.0)
		await frames(1)
		record_pose(metrics)
		if not player.is_executing():
			print(label, " stopped reason/path time=", giant.phase_elapsed, " player=", player.global_position, " anchor=", giant.execution_anchor.global_position)
			break
	report_pose(label, metrics, true)
	print(label, " held_chest_socket=", player.execution_contact_position() - giant._bone_position("socket_grip_R"))
	check(player.is_executing() and giant.phase == SlenderSpeaker.Phase.HOLD and player.global_position.y > chassis.global_position.y + 2.6, label + " lifts the full survivor clear through only the roof opening")
	check(giant.execution_anchor.global_position.distance_to(giant._bone_position("socket_grip_R")) < .001, label + " smoothly finishes at the torso grip socket")
	check(player.execution_contact_position().distance_to(giant._bone_position("socket_grip_R")) < .03, label + " finishes with the actual posed torso inside the hand grip")

func check_shared_seated_pose(seat: Node3D, offset: Vector3) -> void:
	# Keep the real driver's exact posed body/contact and giant transform. Only
	# seated metadata differs: this isolates animation from contact geometry.
	# The physical ownership/clearance routes below remain separate assertions.
	var reference: Array = []
	var target_pose: Array[Transform3D] = []
	var target_transform := Transform3D.IDENTITY
	var max_position_error := 0.0
	var max_angle_error := 0.0
	var max_basis_error := 0.0
	for seated in [true, false]:
		reset_player(seat.global_position)
		seat.interact_hold(player)
		player._physics_process(1.0 / 60.0)
		await frames(3)
		settle_pose()
		var target_skeleton: Skeleton3D = player.get_node("Visuals").skeleton
		if seated:
			target_transform = player.global_transform
			for index in target_skeleton.get_bone_count(): target_pose.append(target_skeleton.get_bone_pose(index))
		else:
			player.global_transform = target_transform
			for index in target_pose.size(): target_skeleton.set_bone_pose(index, target_pose[index])
			target_skeleton.force_update_all_bone_transforms()
		pose_giant(offset)
		if not seated: player.seated_in = null
		giant._begin_grab()
		for tick in 59:
			giant.phase_elapsed = float(tick + 1) / 60.0
			giant._pose_grab_reach()
			var poses: Array[Transform3D] = []
			for index in giant.visual.skeleton.get_bone_count():
				poses.append(giant.visual.skeleton.global_transform * giant.visual.skeleton.get_bone_global_pose(index))
			if seated: reference.append(poses)
			else:
				for index in poses.size():
					var expected: Transform3D = reference[tick][index]
					max_position_error = maxf(max_position_error, expected.origin.distance_to(poses[index].origin))
					max_angle_error = maxf(max_angle_error, rad_to_deg(expected.basis.get_rotation_quaternion().angle_to(poses[index].basis.get_rotation_quaternion())))
					for column in 3: max_basis_error = maxf(max_basis_error, expected.basis[column].distance_to(poses[index].basis[column]))
		# Seat release is real for both equality passes. This direct execution
		# start tests lift pose only, not physical acquisition authorization.
		player.seated_in = seat
		check(giant._start_execution(), "Shared-pose comparison starts a real execution owner")
		if player.is_executing():
			for tick in 84:
				giant.phase_elapsed = float(tick + 1) / 60.0
				giant._advance_execution()
				var poses: Array[Transform3D] = []
				for index in giant.visual.skeleton.get_bone_count():
					poses.append(giant.visual.skeleton.global_transform * giant.visual.skeleton.get_bone_global_pose(index))
				if seated: reference.append(poses)
				else:
					for index in poses.size():
						var expected: Transform3D = reference[59 + tick][index]
						max_position_error = maxf(max_position_error, expected.origin.distance_to(poses[index].origin))
						max_angle_error = maxf(max_angle_error, rad_to_deg(expected.basis.get_rotation_quaternion().angle_to(poses[index].basis.get_rotation_quaternion())))
						for column in 3: max_basis_error = maxf(max_basis_error, expected.basis[column].distance_to(poses[index].basis[column]))
		giant._cancel_execution("fixture_reset")
	print("SHARED_SEATED_POSE offset=", offset, " bone_position_error=", max_position_error, " basis_error=", max_basis_error, " bone_angle_error_deg=", max_angle_error)
	check(reference.size() == 143 and max_position_error < .00001 and max_basis_error < .00001, "Equal seated/outside targets use identical grab/lift bone poses without wrist rotation or detours")

func clear_sight_memory() -> void:
	giant.reset_after_restore()
	giant._sense_remaining = 0.0
	giant.velocity = Vector3.ZERO

func check_single_hand_capture(side: String) -> void:
	reset_player(Vector3(0, -.249, -2.1))
	await frames()
	settle_pose()
	pose_giant(Vector3(0, 0, 2.1))
	giant._begin_grab()
	# Prime a real frame of the shared reach, then place the production capsule
	# beside one finger. The next production tick sweeps both actual hands.
	giant.phase_elapsed = .5
	giant._pose_grab_reach()
	var other := "L" if side == "R" else "R"
	var selected := Vector3.ZERO
	var largest_separation := -INF
	for bone in giant._hand_contact_bones(side):
		var point := giant._bone_position(bone)
		var separation := INF
		for opposite in giant._hand_contact_bones(other):
			separation = minf(separation, point.distance_to(giant._bone_position(opposite)))
		if separation > largest_separation:
			largest_separation = separation
			selected = point
	var chest_offset: Vector3 = player.execution_contact_position() - player.global_position
	var outward := (selected - giant._bone_position("hand." + other)).slide(Vector3.UP).normalized()
	var isolated := false
	for distance in [.22, .30, .38, .44]:
		player.global_position = selected + outward * distance - chest_offset
		await frames()
		if giant._hand_currently_touches_player(side) and not giant._hand_currently_touches_player(other):
			isolated = true
			break
	check(isolated, side + "-hand fixture overlaps only that actual hand with the production player capsule")
	if not isolated: return
	var before: Transform3D = player.global_transform
	var view_before: Basis = player.camera.global_basis
	giant._set_phase(SlenderSpeaker.Phase.PATROL)
	var finger := giant._bone_position(giant._hand_contact_bones(side)[0])
	giant._hand_hits_player(finger, selected, .13, side)
	check(not player.is_executing() and not giant.execution_music.playing, "Idle hand contact cannot start capture or execution music")
	giant._set_phase(SlenderSpeaker.Phase.GRAB)
	giant.phase_elapsed = .5 + 1.0 / 60.0
	for hand in ["R", "L"]:
		for bone in giant._hand_contact_bones(hand): giant._previous_hands[bone] = giant._bone_position(bone)
	giant._advance_grab()
	check(player.is_executing() and giant.phase == SlenderSpeaker.Phase.LIFT,
		side + " hand starts capture on its actual contact before grab windup finishes")
	check(giant._grab_hands_touched.has(side) and giant._grab_hands_touched.size() == 1,
		side + " hand capture requires no opposite hand contact")
	check(player.global_transform.is_equal_approx(before) and player.camera.global_basis.is_equal_approx(view_before),
		side + " hand capture preserves the real body position and initial camera view")
	check(player.grab_control.captor == giant and player.camera.current
		and player.grab_control.execution_observer == null and not player.body_collision_shape.disabled,
		side + " hand transfers shared ownership and full collision while retaining first-person view during lift")
	giant._cancel_execution("fixture_reset")

func check_independent_finger_contact(side: String) -> void:
	reset_player(Vector3(0, -.249, -2.1))
	await frames()
	settle_pose()
	pose_giant(Vector3(0, 0, 2.1))
	giant._begin_grab()
	# Prime a real locked authored pose, then test a zero-motion contact tick.
	# The production capsule touches a clear palm probe while a small solid
	# overlaps a later finger outside the palm's destruction volume.
	giant.phase_elapsed = .8
	giant._pose_grab_reach()
	var other := "L" if side == "R" else "R"
	var palm := giant._bone_position("hand." + side)
	var outward := (palm - giant._bone_position("hand." + other)).slide(Vector3.UP).normalized()
	var chest_offset: Vector3 = player.execution_contact_position() - player.global_position
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * .025
	collision.shape = shape
	blocker.add_child(collision)
	world.add_child(blocker)
	blocker.global_position = Vector3(1000, 1000, 1000)
	var blocked_bone := ""
	for distance in [.12, .22, .30, .38]:
		player.global_position = palm + outward * distance - chest_offset
		await frames()
		if giant._grab_sweep(palm, palm, .13).get("collider") != player or giant._hand_currently_touches_player(other): continue
		var bones := giant._hand_contact_bones(side)
		for index in range(bones.size() - 1, 0, -1):
			var point := giant._bone_position(bones[index])
			var away: Vector3 = (point - player.execution_contact_position()).normalized()
			for offset in [Vector3.ZERO, away * .08, Vector3.UP * .08, Vector3.DOWN * .08]:
				blocker.global_position = point + offset
				await frames()
				var palm_center := giant._grab_palm_position(side)
				var palm_clear := giant.sweep_hand(palm_center, palm_center, .24, [player.get_rid()]).is_empty()
				if palm_clear and giant._grab_sweep(palm, palm, .13).get("collider") == player and giant._grab_sweep(point, point, .13).get("collider") == blocker and not giant._hand_currently_touches_player(other):
					blocked_bone = bones[index]
					break
			if not blocked_bone.is_empty(): break
		if not blocked_bone.is_empty(): break
	check(not blocked_bone.is_empty(), side + " finger fixture isolates a clear palm/player contact and a later blocked finger with opposite hand clear")
	if not blocked_bone.is_empty():
		var blocked_point := giant._bone_position(blocked_bone)
		check(giant._grab_sweep(palm, palm, .13).get("safe_fraction", 0.0) == 0.0 and giant._grab_sweep(blocked_point, blocked_point, .13).get("safe_fraction", 0.0) == 0.0,
			side + " palm/player and later finger/blocker contacts occur at the same zero sweep fraction")
		for hand in ["R", "L"]:
			for bone in giant._hand_contact_bones(hand): giant._previous_hands[bone] = giant._bone_position(bone)
			giant._previous_palms[hand] = giant._grab_palm_position(hand)
			giant._remember_grab_hand(hand)
		giant._advance_grab()
		check(player.is_executing() and giant.phase == SlenderSpeaker.Phase.LIFT and giant.execution_music.playing,
			side + " clear palm captures in the same tick despite a simultaneous separate finger obstruction")
		check(giant._grab_hands_touched.has(side) and capture_path_clear() and is_instance_valid(blocker),
			side + " capture uses its real independently clear probe while the finger obstruction stays physical")
		print("INDEPENDENT_FINGER_CONTACT side=", side, " blocked_bone=", blocked_bone, " palm=", palm,
			" blocked_point=", blocked_point, " capture=", player.is_executing())
	giant._cancel_execution("fixture_reset")
	blocker.queue_free()
	await frames()

func face_parked_vehicle() -> void:
	giant.global_position = chassis.global_position + Vector3(-35, 0, 0)
	giant.rotation = Vector3(0, -PI * .5, 0)
	giant._sample("idle_play", 0.0)

func check_independent_rv_sight_and_smash_commit() -> void:
	# Real production actors feed the controller's ray-tested observation,
	# while the frozen RV gives this target-identity check a fixed frame.
	var chassis_processing := chassis.is_physics_processing()
	chassis.set_physics_process(false)
	reset_player(chassis.to_global(Vector3(-2.45, .9, -1.0)))
	player.locomotion_state = player.LocomotionState.CLIMBING
	player.active_climb_rv = chassis
	player.active_wall_normal = Vector3.LEFT
	face_parked_vehicle()
	clear_sight_memory()
	await frames(3)
	settle_pose()
	chassis._road_speed = 8.0
	chassis.linear_velocity = Vector3(0, 0, -8)
	check(giant.can_see_player(player), "Mixed-sight fixture first observes the real survivor on the RV's near side")
	giant._refresh_sight()
	giant._update_encounter(0.0)
	check(giant.target_player == player and giant.target_vehicle == chassis and giant._encounter_decision.mode == "pursuit", "Actual visible climbing survivor acquires its independently visible fast RV")
	player.global_position = chassis.to_global(Vector3(2.45, .9, -1.0))
	var bystander: CharacterBody3D = PLAYER.instantiate()
	world.add_child(bystander)
	bystander.set_physics_process(false)
	bystander.global_position = chassis.global_position + Vector3(-8, 0, 5)
	await frames(3)
	settle_pose()
	check(not giant.can_see_player(player) and giant.can_see_player(bystander), "Real RV shell hides the retained survivor while a separate ground survivor remains visible")
	giant._refresh_sight()
	check(giant._observation.player == bystander and giant._observation.player_vehicle == null and giant._observation.vehicle == chassis and giant._observation.vehicle_visible, "Raw perception records bystander association separately from retained RV visibility")
	giant._update_encounter(.1)
	check(giant.target_player == player and giant.target_vehicle == chassis and giant._encounter_decision.intent == "vehicle_assault", "Unrelated bystander cannot replace the survivor or hide its escaping RV from pursuit")
	giant._follow_vehicle(0.0)
	var health := chassis.get_engine().health
	giant._begin_smash("vehicle_assault")
	player.active_climb_rv = null
	player.locomotion_state = player.LocomotionState.NORMAL
	player.global_position = chassis.global_position + Vector3(-5, 0, -1)
	chassis._road_speed = 0.0
	chassis.linear_velocity = Vector3.ZERO
	await frames(3)
	settle_pose()
	giant._refresh_sight()
	check(giant._observation.player == player and giant._observation.player_vehicle == null, "Real visible ground survivor reports its disembark during the committed smash")
	giant._update_encounter(.8)
	check(giant.phase == SlenderSpeaker.Phase.SMASH and giant.target_player == player and giant.target_vehicle == chassis and giant._action_context.kind == "vehicle_assault" and giant._encounter_decision.mode == "pursuit", "Committed smash retains both target identities and mode despite visible disembark and sustained slowdown")
	giant._set_phase(SlenderSpeaker.Phase.CHASE)
	giant._update_encounter(0.0)
	check(giant.target_player == player and giant.target_vehicle == null and giant._encounter_decision.mode == "ground", "Visible disembark commits only after smash action unlocks")
	check(is_equal_approx(chassis.get_engine().health, health), "Observation and action-context checks cannot cause proximity chassis damage")
	bystander.queue_free()
	reset_player(Vector3(1000, 0, 1000))
	chassis.set_physics_process(chassis_processing)
	clear_sight_memory()
	await frames()

func check_parked_vehicle_sight() -> void:
	# Use the real shell/roof/seat: an unseen driver must not be the only way
	# to notice a stopped RV. No velocity or pre-existing target seeds sight.
	var seat: Node3D = chassis.get_node("DriverSeat")
	reset_player(seat.global_position)
	seat.interact_hold(player)
	player._physics_process(1.0 / 60.0)
	chassis.linear_velocity = Vector3.ZERO
	chassis.angular_velocity = Vector3.ZERO
	face_parked_vehicle()
	await frames(3)
	settle_pose()
	clear_sight_memory()
	check(seat.current_driver == player and not giant.can_see(player, player.execution_contact_position()), "Parked acquisition fixture keeps actual seated driver behind intact real shell")
	check(giant.can_see(chassis, giant._vehicle_surface(chassis)), "Parked acquisition fixture exposes actual RV exterior to the speaker visual cone")
	giant._refresh_sight()
	check(giant._observation.get("vehicle") == chassis and giant._observation.get("vehicle_visible", false)
		and giant._observation.get("player") == null, "First-seen parked production RV is visually acquired despite its hidden driver")
	giant._physics_process(.01)
	check(giant.phase == SlenderSpeaker.Phase.CONFIRM, "Visible parked RV enters normal visual confirmation")
	giant._physics_process(giant.settings.confirm_time)
	check(giant.phase == SlenderSpeaker.Phase.CHASE, "Visible parked RV completes visual confirmation and begins pursuit")
	# A target outside the cone must still be lost and actually forgotten;
	# regaining sight later has to acquire a stationary RV from scratch.
	face_parked_vehicle()
	giant.rotation.y += PI
	giant._sample("idle_play", 0.0)
	giant._set_phase(SlenderSpeaker.Phase.SEARCH)
	giant._sense_remaining = 0.0
	giant._physics_process(giant.settings.search_seconds + .01)
	check(giant.phase == SlenderSpeaker.Phase.PATROL and giant.target_vehicle == null, "Search expiration really forgets parked RV behind the visual cone")
	face_parked_vehicle()
	giant._refresh_sight()
	check(giant._observation.get("vehicle") == chassis and giant._observation.get("vehicle_visible", false),
		"Forgotten parked RV is observed again when the speaker faces it")
	giant._update_encounter(.01)
	check(giant.target_vehicle == null and giant._encounter_decision.get("intent") == "none",
		"Expired stationary encounter remains suppressed despite renewed raw vehicle sight")
	# Empty parked vehicles are targets too; moving engines/driver presence
	# are not conditions of this visual-only detection contract.
	seat.exit_seat(true)
	reset_player(Vector3(1000, 0, 1000))
	face_parked_vehicle()
	clear_sight_memory()
	await frames()
	giant._refresh_sight()
	check(giant._observation.get("vehicle") == chassis and giant._observation.get("vehicle_visible", false)
		and giant._observation.get("player") == null, "Unoccupied parked production RV is observed on its visible exterior")
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(2, 40, 40)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.global_position = chassis.global_position + Vector3(-17.5, 12, 0)
	await frames()
	clear_sight_memory()
	giant._refresh_sight()
	check(not giant._observation.get("vehicle_visible", false) and giant._observation.get("vehicle") == null,
		"Opaque wall prevents first observation of parked RV")
	wall.queue_free()
	await frames()
	face_parked_vehicle()
	giant.rotation.y += PI
	giant._sample("idle_play", 0.0)
	clear_sight_memory()
	giant._refresh_sight()
	check(not giant._observation.get("vehicle_visible", false) and giant._observation.get("vehicle") == null,
		"Parked RV behind the actual speaker visual cone remains undetected")
	face_parked_vehicle()
	giant.global_position.x -= giant.settings.sight_range
	clear_sight_memory()
	giant._refresh_sight()
	check(not giant._observation.get("vehicle_visible", false) and giant._observation.get("vehicle") == null,
		"Parked RV beyond visual range remains undetected")
	clear_sight_memory()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	giant = GIANT.instantiate()
	world.add_child(giant)
	giant.set_physics_process(false)
	player = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	await frames()
	reset_player(Vector3(0, -.249, -2.1))
	await frames()
	settle_pose()
	pose_giant(Vector3(0, 0, 2.1))
	check(grab(), "Production standing torso is captured on the first real hand contact")
	if player.is_executing():
		var capture_elapsed := 0.0
		var ground_metrics := pose_metrics()
		while capture_elapsed < 4.0 and player.is_executing():
			var lifting := giant.phase == SlenderSpeaker.Phase.LIFT
			giant.phase_elapsed += 1.0 / 60.0
			giant._advance_execution()
			if lifting: record_pose(ground_metrics)
			capture_elapsed += 1.0 / 60.0
		report_pose("GROUND_LIFT_CONTINUITY", ground_metrics)
		check(player.is_player_dead and absf(capture_elapsed - 3.8) < .018,
			"Capture-to-crush duration includes a two-second HOLD and finishes at 3.8 seconds within one physics frame")
	player.ragdoll_control.stop()
	for part in get_nodes_in_group("player_detached_parts"): part.queue_free()
	await frames()
	await check_single_hand_capture("R")
	await check_single_hand_capture("L")
	await check_independent_finger_contact("R")
	await check_independent_finger_contact("L")
	reset_player(Vector3(0, -.249, -2.1))
	player.sever_part(&"left_leg")
	player.sever_part(&"right_leg")
	await frames(4)
	for part in get_nodes_in_group("player_detached_parts"): part.queue_free()
	await frames()
	settle_pose()
	pose_giant(Vector3(0, 0, 2.1))
	check(player.is_crawling() and grab(), "Production prone torso and horizontal crawl capsule can be grabbed")
	giant._cancel_execution("fixture_reset")

	vehicle = VEHICLE.instantiate()
	world.add_child(vehicle)
	vehicle.position = Vector3(20, 0, 0)
	chassis = vehicle.get_node("Chassis")
	chassis.freeze = true
	await frames(5)
	await check_independent_rv_sight_and_smash_commit()
	await check_parked_vehicle_sight()
	reset_player(chassis.to_global(Vector3(1.5, 2.452, -1.0)))
	await frames(3)
	settle_pose()
	pose_giant(Vector3(2.5, 0, 0))
	check(grab(), "Production roof-supported survivor can be grabbed without crossing car shell")
	if player.is_executing():
		giant.phase_elapsed = .15
		giant._advance_execution()
		player._physics_process(1.0 / 60.0)
		check(player.is_executing(), "Roof capture begins a clear swept lift")
	giant._cancel_execution("fixture_reset")

	reset_player(chassis.to_global(Vector3(-2.45, .9, -1.0)))
	player.locomotion_state = player.LocomotionState.CLIMBING
	player.active_climb_rv = chassis
	player.active_wall_normal = Vector3.LEFT
	await frames(3)
	settle_pose()
	pose_giant(Vector3(-2.1, 0, 0))
	check(grab(), "Production climbing torso can be grabbed")
	check(player.locomotion_state == player.LocomotionState.NORMAL and player.active_climb_rv == null, "Actual grab releases climbing carrier")
	giant._cancel_execution("fixture_reset")

	var seat: Item = chassis.get_node("DriverSeat")
	var panel: RVStructurePanel = chassis.get_node("StructureSlots").panel("left_0")
	var roof: RVStructurePanel = chassis.get_node("StructureSlots").panel("roof_0")
	check(panel != null and roof != null, "Production driver approach has actual front-side and roof panels")
	# Keep the moving-RV sight assertion separate from the destructive reach.
	reset_player(seat.global_position)
	seat.interact_hold(player)
	player._physics_process(1.0 / 60.0)
	await frames(3)
	settle_pose()
	check(seat.current_driver == player, "Production driver seat owns disabled locomotion capsule")
	panel.take_damage(panel.current_health)
	await frames(3)
	clear_sight_memory()
	chassis.linear_velocity = Vector3(0, 0, -1)
	pose_giant(Vector3(-60.0, 0, 0))
	giant._refresh_sight()
	giant._update_encounter(1.0 / 60.0)
	check(giant.target_player == player, "Visible driver acquired through real aperture even when nearest moving RV surface is closer")
	panel.set_health(panel.max_health)
	chassis.linear_velocity = Vector3.ZERO
	chassis.angular_velocity = Vector3.ZERO
	vehicle.position.y = 1.226
	reset_player(seat.global_position)
	seat.interact_hold(player)
	player._physics_process(1.0 / 60.0)
	await frames(3)
	settle_pose()
	pose_giant(Vector3(-2.6, 0, 0))
	var seat_health := seat.current_health
	var collateral: RVStructurePanel = chassis.get_node("StructureSlots").panel("roof_2")
	var collateral_health := collateral.current_health
	var side_bounds: AABB = panel.global_transform * panel.get_placement_bounds()
	var giant_capsule := giant.get_node("CollisionShape").shape as CapsuleShape3D
	check(giant.global_position.x + giant_capsule.radius < side_bounds.position.x and (player.execution_contact_position() - giant.global_position).slide(Vector3.UP).length() <= 2.7, "Roof capture fixture keeps full giant capsule outside shell within production grab distance")
	check(not roof.is_destroyed and panel.can_operate(), "Seated capture begins with the actual roof and side shell intact")
	check(grab(), "The same authored grab clears palm-touched shell and captures the real seated torso")
	print("SEATED_PALM_CLEARED ", giant._grab_cleared_obstacles)
	check(roof.is_destroyed and not giant._grab_cleared_obstacles.is_empty(), "Palm sweep removes the actual intact front roof during that grab")
	check(collateral.current_health == collateral_health and seat.current_health == seat_health and not seat.is_destroyed, "Untouched rear roof and occupied seat survive seated palm destruction")
	if player.is_executing():
		check(player.seated_in == null and seat.current_driver == null and capture_path_clear(), "Actual clear contact releases both seat owners after acquisition")
		await lift_driver("SIDE_ROOF_LIFT_CONTINUITY")
	giant._cancel_execution("fixture_reset")
	await frames()
	await check_shared_seated_pose(seat, Vector3(-2.6, 0, 0))
	await check_shared_seated_pose(seat, Vector3(0, 0, -2.57))
	reset_player(seat.global_position)
	seat.interact_hold(player)
	player._physics_process(1.0 / 60.0)
	await frames(3)
	settle_pose()
	pose_giant(Vector3(0, 0, -2.57))
	check(grab() and capture_path_clear(), "Front approach captures along an independently clear real sweep after palm shell removal")
	check(seat.current_health == seat_health and not seat.is_destroyed, "Front grab preserves the occupied seat component")
	giant._cancel_execution("fixture_reset")
	# Restore shell health before the separate smash contract assertions below.
	for child in chassis.get_children():
		if child is RVStructurePanel: child.set_health(child.max_health)
	panel.take_damage(panel.current_health)
	vehicle.position.y = 0.0
	await frames(3)
	var supported_ladder: Item = chassis.get_node("RoofLadder")
	var supporting_panel: RVStructurePanel = chassis.get_node("StructureSlots").panel("left_1")
	check(supported_ladder.is_fixed and supported_ladder.mount_support == supporting_panel, "Production ladder is mounted to actual left-middle panel")
	var item_health := supported_ladder.current_health
	var next_panel: RVStructurePanel = chassis.get_node("StructureSlots").panel("left_2")
	var next_health := next_panel.current_health
	giant.target_player = null
	giant.target_vehicle = chassis
	giant.position = Vector3(15.5, 0, 1.5)
	giant.rotation.y = -PI * .5
	giant._begin_smash()
	giant.phase_elapsed = 1.799
	giant._advance_smash()
	check(not supporting_panel.is_destroyed, "No shell damage before complete 1.8 second smash windup")
	var physical_hit := giant.sweep_hand(Vector3(15.5, 2, 1.5), Vector3(21, 2, 1.5), .2)
	check(physical_hit.get("collider") == supporting_panel, "Actual production sweep strikes one first valid shell panel away from mounted ladder")
	giant.phase_elapsed = 1.8
	check(giant.resolve_smash_hit(physical_hit.get("collider")) and supporting_panel.current_health == supporting_panel.max_health - 60.0, "One real production shell panel takes 60 damage at impact")
	await frames(3)
	check(not supporting_panel.is_destroyed and supported_ladder.is_fixed and not supported_ladder.support_lost, "A surviving wall continues supporting its mounted ladder")
	giant._strike_resolved = false
	check(giant.resolve_smash_hit(supporting_panel) and supporting_panel.is_destroyed, "A second 60-damage swing destroys the 120-health support wall")
	await frames(3)
	check(supported_ladder.support_lost and not supported_ladder.is_fixed and not supported_ladder.freeze and supported_ladder.get_parent() == WorldEntities.get_container(giant), "Existing mounted equipment support loss drops ladder into WorldEntities")
	check(supported_ladder.current_health == item_health and next_panel.current_health == next_health, "Equipment and adjacent shell retain health after one-panel smash")
	# A branch/wall touched during the raised windup cannot be skipped by the
	# last impact-frame sweep. Keep the real rear target intact for both paths.
	giant.position = Vector3(20.31, .001, 8.5)
	giant.rotation = Vector3.ZERO
	giant._begin_smash()
	giant.phase_elapsed = 1.3
	giant._advance_smash()
	var branch := StaticBody3D.new()
	var branch_shape := CollisionShape3D.new()
	var branch_box := BoxShape3D.new()
	branch_box.size = Vector3(.2, .2, .2)
	branch_shape.shape = branch_box
	branch.add_child(branch_shape)
	world.add_child(branch)
	branch.global_position = giant._bone_position("socket_strike_R")
	await frames()
	var blocked_target: RVStructurePanel
	var nearest_distance := INF
	for candidate in get_nodes_in_group(Groups.MONSTER_DAMAGEABLE):
		if not candidate is RVStructurePanel or candidate.is_destroyed or candidate.get_connected_rv() != chassis: continue
		var distance: float = candidate.global_position.distance_squared_to(giant._vehicle_surface(chassis))
		if distance < nearest_distance:
			blocked_target = candidate
			nearest_distance = distance
	giant._begin_smash()
	var obstruction_time := 0.0
	var stopped_point := Vector3.ZERO
	for i in 108:
		giant.phase_elapsed = float(i + 1) / 60.0
		giant._advance_smash()
		if obstruction_time == 0.0 and not giant._strike_obstruction_pose.is_empty():
			obstruction_time = float(i + 1) / 60.0
			stopped_point = giant._bone_position("socket_strike_R")
		elif obstruction_time > 0.0:
			check(giant._bone_position("socket_strike_R").distance_to(stopped_point) < .0001, "Opaque obstruction keeps actual hand pose stopped throughout remaining windup")
	check(obstruction_time > 0.0 and obstruction_time < 1.8, "Real swept smash contacts the intervening branch before final impact")
	check(blocked_target != null and not blocked_target.is_destroyed and giant.phase == SlenderSpeaker.Phase.RECOVER, "Earlier opaque contact prevents final impact from damaging the rear panel beyond it")
	giant.phase_elapsed = 1.0 / 60.0
	giant._advance_recovery()
	check(giant._bone_position("socket_strike_R").distance_to(stopped_point) < .35, "Interrupted raised strike recovers smoothly without teleporting through the obstruction")
	var first_contact_point := branch.global_position
	branch.queue_free()
	await frames()
	var early_panel := RVStructurePanel.new()
	var early_shape := CollisionShape3D.new()
	early_shape.shape = branch_box.duplicate()
	early_panel.add_child(early_shape)
	chassis.add_child(early_panel)
	early_panel.global_position = first_contact_point
	await frames()
	giant._begin_smash()
	for i in 108:
		giant.phase_elapsed = float(i + 1) / 60.0
		giant._advance_smash()
		if i < 107: check(not early_panel.is_destroyed, "First contacted panel is not damaged during windup")
	check(early_panel.current_health == early_panel.max_health - 60.0 and not early_panel.is_destroyed and blocked_target.current_health == blocked_target.max_health, "Windup holds at first actual panel and deals 60 damage only to that panel at 1.8 seconds")
	await frames()
	var escaping_panel := RVStructurePanel.new()
	var escaping_shape := CollisionShape3D.new()
	escaping_shape.shape = branch_box.duplicate()
	escaping_panel.add_child(escaping_shape)
	chassis.add_child(escaping_panel)
	escaping_panel.global_position = first_contact_point
	await frames()
	giant._begin_smash()
	for i in 107:
		giant.phase_elapsed = float(i + 1) / 60.0
		giant._advance_smash()
		if giant._strike_contact_collider != null: break
	check(giant._strike_contact_collider == escaping_panel, "Moving-target test begins with real swept first-panel contact")
	vehicle.position.x += 5.0
	await frames()
	giant.phase_elapsed = 1.8
	giant._advance_smash()
	check(not escaping_panel.is_destroyed and not blocked_target.is_destroyed and giant.phase == SlenderSpeaker.Phase.RECOVER, "Vehicle escaping after first contact avoids damage at fixed1.8sec impact without redirecting to another panel")
	world.queue_free()
	await frames()
	if failures.is_empty(): print("PASS: production Slender Speaker acquisition variants")
	else: print("FAIL production acquisition: ", failures.size())
	quit(0 if failures.is_empty() else 1)
