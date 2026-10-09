extends SceneTree
## Real collision queries and the production model/controller, without driving input.
var failures: Array[String] = []

class GrabControl extends Node:
	signal released(reason: String)
	var captor: Node3D

class Survivor extends CharacterBody3D:
	var is_player_dead := false
	var seated_in: Node3D
	var grab_control := GrabControl.new()
	var starts := 0
	var deaths := 0
	var anchor: Node3D
	func _ready() -> void: add_child(grab_control)
	func execution_contact_position() -> Vector3: return global_position + Vector3.UP * 1.25
	func can_be_executed() -> bool: return not is_player_dead and not is_instance_valid(grab_control.captor)
	func begin_execution(owner: Node3D, grip: Node3D, _focus: Node3D) -> bool:
		if not can_be_executed(): return false
		grab_control.captor = owner
		anchor = grip
		starts += 1
		return true
	func is_executing() -> bool: return is_instance_valid(grab_control.captor)
	func complete_execution(owner: Node3D) -> bool:
		if grab_control.captor != owner: return false
		deaths += 1
		is_player_dead = true
		grab_control.captor = null
		grab_control.released.emit("death")
		return true
	func cancel_execution(owner: Node3D, reason := "cancelled") -> void:
		if grab_control.captor != owner: return
		grab_control.captor = null
		grab_control.released.emit(reason)

class Vehicle extends RigidBody3D:
	var point_velocity := Vector3.ZERO
	func add_item(_item): pass
	func deduct_materials(_cost): pass
	func vehicle_impact_point_velocity(_point: Vector3) -> Vector3: return point_velocity

func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func add_shape(body: Node3D, size: Vector3, center := Vector3.ZERO) -> void:
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	node.shape = box
	node.position = center
	body.add_child(node)

func settle() -> void:
	await physics_frame
	await physics_frame

func gait_foot(giant: SlenderSpeaker, side: String) -> Vector3:
	return (giant.global_transform.affine_inverse() * giant.visual.bone_world("foot." + side)).origin

func check_steady_gait(giant: SlenderSpeaker) -> void:
	# Hold the actor fixed and advance the production locomotion sampler: only
	# real local leg motion can satisfy these checks, not world translation.
	giant._set_phase(SlenderSpeaker.Phase.PATROL)
	var reference_cycles: Array[float] = []
	for hz in [30, 60, 120]:
		var delta := 1.0 / float(hz)
		var cycles: Array[float] = []
		for speed in [3.5, 7.9, 8.0, 8.2, 60.0 / 3.6]:
			giant._gait_phase = .36
			giant._locomotion_clip = "walk"
			giant._gait_blend = 0.0
			giant._sample("walk", .36 * giant._duration("walk"))
			# Allow the initial idle/locomotion blend to settle before measuring.
			for tick in hz: giant._animate_locomotion(delta, speed)
			var settled_transitions := giant._locomotion_transitions
			var phase_travel := 0.0
			var previous_phase := giant._gait_phase
			var previous_right := gait_foot(giant, "R")
			var previous_left := gait_foot(giant, "L")
			var window_travel := 0.0
			var minimum_window := INF
			var window_ticks := maxi(1, int(round(float(hz) * .25)))
			for tick in hz * 3:
				giant._animate_locomotion(delta, speed)
				var advance := fposmod(giant._gait_phase - previous_phase, 1.0)
				check(advance > .0001 and advance < .1, "Fixed %.2f m/s gait advances continuously without phase restart at %d Hz" % [speed, hz])
				phase_travel += advance
				previous_phase = giant._gait_phase
				var right := gait_foot(giant, "R")
				var left := gait_foot(giant, "L")
				window_travel += right.distance_to(previous_right) + left.distance_to(previous_left)
				previous_right = right
				previous_left = left
				if (tick + 1) % window_ticks == 0:
					minimum_window = minf(minimum_window, window_travel)
					window_travel = 0.0
			check(minimum_window > .04, "Both production feet cannot freeze together over a quarter-second window at %.2f m/s, %d Hz" % [speed, hz])
			check(giant._locomotion_transitions == settled_transitions, "Constant %.2f m/s does not restart the locomotion blend at %d Hz" % [speed, hz])
			if speed >= 7.9:
				check(phase_travel > 1.5, "Fixed %.2f m/s gait completes a full stride within two seconds at %d Hz" % [speed, hz])
			cycles.append(phase_travel)
			print("STEADY_GAIT speed=", speed, " hz=", hz, " cycles_3s=", phase_travel, " min_foot_motion_250ms=", minimum_window)
		check(absf(cycles[2] / cycles[1] - 1.0) < .2 and absf(cycles[3] / cycles[1] - 1.0) < .2, "Crossing 8 m/s keeps continuous stride cadence at %d Hz" % hz)
		if reference_cycles.is_empty(): reference_cycles = cycles
		else:
			for index in cycles.size():
				check(absf(cycles[index] - reference_cycles[index]) < .01, "Constant-speed stride cadence is consistent at 30/60/120 Hz")

func check_chase_motion(giant: SlenderSpeaker) -> void:
	check(absf(giant.settings.chase_speed * 3.6 - 60.0) < .0001, "Default chase maximum is 60 km/h")
	check(is_equal_approx(giant.settings.acceleration, 2.5), "Default acceleration is 2.5 m/s²")
	check(is_equal_approx(giant.settings.braking, 6.0), "Default braking is 6 m/s²")
	var cap := giant.settings.chase_speed
	var parked := Vector3(-40, 0, 30)
	for hz in [30, 60, 120]:
		var delta := 1.0 / float(hz)
		giant.velocity = Vector3.ZERO
		for tick in hz * 7:
			giant.position = parked
			giant._move_swept(Vector3(0, 0, -32), delta)
			var expected := minf(cap, 2.5 * float(tick + 1) * delta)
			check(absf(giant.velocity.slide(Vector3.UP).length() - expected) < .001, "Straight acceleration and 60 km/h cap at %d Hz, tick %d" % [hz, tick])
			if tick == hz * 6 - 1:
				check(giant.velocity.slide(Vector3.UP).length() < cap - 1.0, "Chase still accelerating at six seconds at %d Hz" % hz)
		giant.position = parked
		giant.velocity = Vector3(24, 5, -24)
		giant._move_swept(Vector3(32, 20, -32), delta)
		check(giant.velocity.slide(Vector3.UP).length() <= cap + .001, "Diagonal desired and inherited overspeed are capped at %d Hz" % hz)
		giant.velocity = Vector3(0, 0, -cap)
		for tick in hz:
			giant.position = parked
			giant._move_swept(Vector3.ZERO, delta)
		check(absf(giant.velocity.slide(Vector3.UP).length() - (cap - 6.0)) < .001, "Braking removes 6 m/s in one second at %d Hz" % hz)

func check_chase_turns(giant: SlenderSpeaker) -> void:
	var cap := giant.settings.chase_speed
	var parked := Vector3(-40, 0, 30)
	var final_speeds: Array[float] = []
	for sign_value in [-1.0, 1.0]:
		for hz in [30, 60, 120]:
			var delta := 1.0 / float(hz)
			giant.position = parked
			giant.rotation.y = 0.0
			giant.velocity = Vector3(0, 0, -cap)
			giant.phase_elapsed = 0.0
			for tick in hz * 2:
				giant.position = parked
				var target_direction := Vector3.FORWARD.rotated(Vector3.UP, giant.rotation.y + sign_value * deg_to_rad(15.0))
				# Let NavigationAgent refresh its real path on each simulated step.
				await physics_frame
				var previous_angle := giant.rotation.y
				var desired := giant._navigate(parked + target_direction * 30.0, cap, delta)
				check(absf(rad_to_deg(angle_difference(previous_angle, giant.rotation.y))) <= 45.0 * delta + .001, "Sustained chase turn retains yaw cap at %d Hz" % hz)
				giant._move_swept(desired, delta)
				check(giant.velocity.slide(Vector3.UP).length() <= cap + .001, "Turning chase stays below 60 km/h at %d Hz" % hz)
			var turn_speed := giant.velocity.slide(Vector3.UP).length()
			print("Chase turn direction=", sign_value, " hz=", hz, " speed=", turn_speed)
			final_speeds.append(turn_speed)
			check(turn_speed > 5.0 and turn_speed < cap * .55, "Sustained %s turn slows actual body speed at %d Hz" % ["left" if sign_value > 0 else "right", hz])
			giant.position = parked
			var straight_direction := -giant.global_basis.z
			await physics_frame
			var desired := giant._navigate(parked + straight_direction * 30.0, cap, delta)
			giant._move_swept(desired, delta)
			var resumed_speed := giant.velocity.slide(Vector3.UP).length()
			check(resumed_speed > turn_speed and resumed_speed <= turn_speed + 2.5 * delta + .001, "Straight exit resumes gradually at %d Hz" % hz)
			for tick in hz * 7:
				giant.position = parked
				giant._move_swept(straight_direction * cap, delta)
			check(absf(giant.velocity.slide(Vector3.UP).length() - cap) < .02, "Straight chase regains cap after turn at %d Hz" % hz)
	for speed in final_speeds:
		check(absf(speed - final_speeds[0]) < .15, "Left/right turn slowdown is consistent at 30/60/120 Hz")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	add_shape(floor_body, Vector3(200, 0.2, 200), Vector3(0, -0.1, 0))
	world.add_child(floor_body)
	var giant: SlenderSpeaker = load("res://enemies/slender_speaker/slender_speaker.tscn").instantiate()
	world.add_child(giant)
	giant.set_physics_process(false)
	var survivor := Survivor.new()
	add_shape(survivor, Vector3(.5, 1.7, .5), Vector3.UP * .85)
	survivor.position = Vector3(0, 0, -20)
	world.add_child(survivor)
	survivor.add_to_group(Groups.PLAYER)
	await settle()
	check(giant.visual.available, "Production GLB and sockets loaded")
	check(giant.can_see(survivor, survivor.execution_contact_position()), "Forward visible standing player confirmed from speaker head")
	survivor.position.z = 20
	await settle()
	check(not giant.can_see(survivor, survivor.execution_contact_position()), "Rear player excluded by speaker cone")
	survivor.position.z = -20
	var tree := StaticBody3D.new()
	add_shape(tree, Vector3(3, 15, 1), Vector3(0, 7.5, -10))
	world.add_child(tree)
	await settle()
	giant._refresh_sight()
	check(not giant._visible_target, "Actual forest trunk blocks visual confirmation")
	# Arbitrarily loud sources cannot call a hearing detector or change sight.
	giant._refresh_sight()
	check(giant.target_player == null, "Occluded player remains unacquired independent of sound")
	tree.queue_free()
	await settle()
	giant._refresh_sight()
	check(giant.target_player == survivor, "Cleared sight reacquires real player")
	giant.take_damage(100000.0)
	giant.die()
	check(not giant.is_dead and giant.current_health == giant.max_health, "First release is invincible")

	var rv := Vehicle.new()
	rv.freeze = true
	rv.position = Vector3(10, 0, 0)
	world.add_child(rv)
	rv.add_to_group(Groups.RV)
	var first := RVStructurePanel.new()
	add_shape(first, Vector3(1, 2, .2))
	first.position = Vector3(0, 2, -3)
	rv.add_child(first)
	var second := RVStructurePanel.new()
	add_shape(second, Vector3(1, 2, .2))
	second.position = Vector3(0, 2, -4)
	rv.add_child(second)
	await settle()
	var hit := giant.sweep_hand(Vector3(10, 2, 0), Vector3(10, 2, -6), .2)
	check(hit.get("collider") == first, "Swept hand reports first panel, not panel behind it")
	giant._strike_resolved = false
	check(giant.resolve_smash_hit(hit.get("collider")), "Actual first panel is destroyed")
	check(first.is_destroyed and not second.is_destroyed, "Exactly one car shell panel removed")
	check(not giant.resolve_smash_hit(second) and not second.is_destroyed, "Duplicate smash callback cannot remove another panel")
	giant._strike_resolved = false
	check(not giant.resolve_smash_hit(floor_body), "Miss/environment cannot proxy damage to nearest panel")
	giant.velocity = Vector3.ZERO
	giant.contact_sample_frame = -100
	rv.point_velocity = Vector3(9.9, 0, 0)
	check(not giant.receive_vehicle_body_contact(rv, Vector3.RIGHT, Vector3.ZERO), "Below 10 m/s impact does not stagger")
	rv.point_velocity.x = 10.0
	giant._set_phase(SlenderSpeaker.Phase.PATROL)
	giant._on_hitbox_body_entered(rv)
	check(giant.phase == SlenderSpeaker.Phase.PATROL and giant._stagger_cooldown == 0.0, "Predictive HitBox Area overlap cannot stagger before physical vehicle contact")
	check(giant.receive_vehicle_body_contact(rv, Vector3.RIGHT, Vector3.ZERO), "Valid 10 m/s frontal impact staggers")
	check(giant.phase == SlenderSpeaker.Phase.STAGGER and is_equal_approx(giant._stagger_cooldown, 8.0), "0.8 second stagger, 8 second cooldown configured")
	check(not giant.receive_vehicle_body_contact(rv, Vector3.RIGHT, Vector3.ZERO), "Cooldown rejects repeated impact")

	giant._stagger_cooldown = 0.0
	survivor.position = Vector3(0, 0, -1.4)
	giant.target_player = survivor
	giant.target_vehicle = null
	await settle()
	giant._begin_grab()
	check(not giant.can_save(), "Saving refused throughout grab windup")
	for index in 60:
		giant.phase_elapsed = float(index + 1) / 60.0
		giant._advance_grab()
		if giant.phase != SlenderSpeaker.Phase.GRAB: break
	print("Grab result phase=", giant.phase, " touched=", giant._grab_hands_touched, " socket=", giant._bone_position("socket_grip_R"), " contact=", survivor.execution_contact_position())
	check(giant.phase == SlenderSpeaker.Phase.LIFT and survivor.starts == 1, "Both actual hands reach and acquire sole execution owner")
	check(giant.execution_music.playing and giant._music_fade <= .1, "Successful grab starts execution music that same frame")
	check(not giant.receive_vehicle_body_contact(rv, Vector3.RIGHT, Vector3.ZERO), "Formal execution ignores vehicle stagger")
	giant._update_music(.1)
	check(not giant.patrol_music.playing, "Patrol music finishes switching within 100 ms")
	if giant.phase == SlenderSpeaker.Phase.LIFT:
		giant.phase_elapsed = 1.4
		giant._advance_execution()
		giant.phase_elapsed = .6
		giant._advance_execution()
		giant.phase_elapsed = .4
		giant._advance_execution()
	check(survivor.deaths == 1 and giant._music_tail, "Crush commits death once and retains execution tail")
	giant._on_execution_music_finished()
	check(giant.patrol_music.playing and not giant._music_tail, "After execution tail patrol loop resumes")
	check(giant.patrol_music.stream is AudioStreamWAV and giant.patrol_music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Patrol WAV loops explicitly")
	check(giant.execution_music.stream is AudioStreamWAV and giant.execution_music.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Execution WAV cannot loop")

	survivor.is_player_dead = false
	survivor.starts = 0
	var window := StaticBody3D.new()
	add_shape(window, Vector3(3, 3, .08), Vector3(0, 1.5, -1.0))
	world.add_child(window)
	await settle()
	giant._begin_grab()
	for index in 60:
		giant.phase_elapsed = float(index + 1) / 60.0
		giant._advance_grab()
		if giant.phase != SlenderSpeaker.Phase.GRAB: break
	check(survivor.starts == 0 and not giant.execution_music.playing, "Complete glass/shell blocks grabbing and never switches music on miss")
	window.queue_free()
	await settle()
	giant._sample("grab", 1.0)
	giant._grab_correction = survivor.execution_contact_position() - giant._bone_position("socket_grip_R")
	giant._start_execution()
	survivor.cancel_execution(giant, "execution_path_blocked")
	check(not giant.is_execution_active() and not giant.execution_music.playing and giant.patrol_music.playing, "Blocked lift cancellation clears music and ownership")
	for entry in [[SlenderSpeaker.Phase.SMASH, "smash", 1.8], [SlenderSpeaker.Phase.GRAB, "grab", 1.0], [SlenderSpeaker.Phase.LIFT, "lift", .4], [SlenderSpeaker.Phase.CRUSH, "crush", .4]]:
		giant._sample(entry[1], entry[2])
		giant._set_phase(entry[0])
		giant.phase_elapsed = entry[2]
		giant._strike_correction = Vector3.ZERO
		giant._grab_correction = Vector3.ZERO
		var before_right := giant._bone_position("hand.R")
		var before_left := giant._bone_position("hand.L")
		giant._set_phase(SlenderSpeaker.Phase.RECOVER)
		giant._advance_recovery()
		check(giant._bone_position("hand.R").distance_to(before_right) < .0001 and giant._bone_position("hand.L").distance_to(before_left) < .0001, "Recovery first frame preserves both real hand poses from " + entry[1])
		giant.phase_elapsed = 1.0 / 60.0
		giant._advance_recovery()
		check(giant._bone_position("hand.R").distance_to(before_right) < .35 and giant._bone_position("hand.L").distance_to(before_left) < .35, "Recovery continues smoothly without raised-hand teleport from " + entry[1])
	giant._set_phase(SlenderSpeaker.Phase.PATROL)
	giant._gait_phase = .36
	giant._locomotion_clip = "walk"
	giant._sample("walk", .36 * 2.4)
	var before_foot := giant._bone_position("foot.R")
	var transitions := giant._locomotion_transitions
	giant._animate_locomotion(1.0 / 60.0, 8.2)
	check(giant._locomotion_clip == "run" and giant._gait_phase > .36 and giant._gait_phase < .41, "Walk/run switch preserves normalized gait phase")
	check(giant._bone_position("foot.R").distance_to(before_foot) < .35, "Walk/run first transition frame does not teleport foot")
	for i in 30: giant._animate_locomotion(1.0 / 60.0, 6.5 + float(i % 6) * .25)
	check(giant._locomotion_transitions == transitions + 1 and giant._locomotion_clip == "run", "Oscillation around 7 m/s cannot retrigger gait transitions")
	var phase_before := giant._gait_phase
	giant._animate_locomotion(1.0 / 60.0, 5.9)
	check(giant._locomotion_clip == "walk" and giant._gait_phase > phase_before, "Deceleration crosses 6m/s hysteresis once and retains leg phase")
	check_steady_gait(giant)
	giant.position = Vector3(-40, 0, 0)
	giant.velocity = Vector3.ZERO
	giant._move_swept(Vector3(32, 0, 0), 1.0 / 60.0)
	check(absf(giant.velocity.x - 2.5 / 60.0) < .0001, "2.5m/s² acceleration increases speed gradually per 60Hz tick")
	check_chase_motion(giant)
	giant.position = Vector3(-40, 0, 0)
	var barrier := StaticBody3D.new()
	add_shape(barrier, Vector3(10, 20, .05), Vector3(-40, 10, -4))
	world.add_child(barrier)
	await settle()
	var collided := false
	for i in 20:
		giant.velocity = Vector3(0, 0, -32)
		giant._move_swept(giant.velocity, 1.0 / 60.0)
		collided = collided or giant.get_slide_collision_count() > 0
	check(giant.global_position.z > -3.0 and collided, "Inherited 32m/s overspeed is clamped and swept body cannot tunnel through thin obstruction")
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-90, 0, -90), Vector3(-90, 0, 90), Vector3(90, 0, 90), Vector3(90, 0, -90)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)
	region.set_navigation_map(map)
	giant.set_giant_navigation_map(map)
	await settle()
	giant.position = Vector3(-40, 0, 0)
	giant.rotation.y = 0.0
	giant.velocity = Vector3(0, 0, -32)
	NavigationServer3D.map_force_update(map)
	await check_chase_turns(giant)
	giant.position = Vector3(-40, 0, 0)
	giant.rotation.y = 0.0
	giant.velocity = Vector3(0, 0, -32)
	for i in 4:
		await settle()
		var previous := giant.rotation.y
		giant._navigate(Vector3(-20, 0, -10), 32.0, .1)
		check(absf(rad_to_deg(angle_difference(previous, giant.rotation.y))) <= 4.501, "High-speed navigation turns at most45degrees/second")
	check(absf(giant.rotation.y) > .001, "Giant navigation actually steers along independent map")
	var before_angle := giant.rotation.y
	giant.velocity = Vector3.ZERO
	giant._navigate(Vector3(-20, 0, -10), 4.0, .1)
	check(absf(rad_to_deg(angle_difference(before_angle, giant.rotation.y))) <= 9.001, "Near-speed navigation turns at most90degrees/second")
	for search_speed in [32.0, 0.0]:
		giant.position = Vector3(-40, 0, 0)
		giant.rotation.y = 0.0
		giant.velocity = Vector3(0, 0, -search_speed)
		giant.last_seen_position = giant.global_position + Vector3(-2, 0, 0)
		giant._sense_remaining = 100.0
		giant._visible_target = false
		giant._set_phase(SlenderSpeaker.Phase.SEARCH)
		giant._physics_process(.1)
		var limit := 4.5 if search_speed > 7.0 else 9.0
		check(absf(rad_to_deg(giant.rotation.y) - limit) < .001, "Search scan uses one total speed-dependent yaw budget at " + str(search_speed) + "m/s")
	giant.position = Vector3(-40, 0, 0)
	giant.rotation.y = 0.0
	giant.velocity = Vector3.ZERO
	giant.last_seen_position = giant.global_position + Vector3(2, 4, 0)
	giant._set_phase(SlenderSpeaker.Phase.SEARCH)
	giant._physics_process(.1)
	check(absf(rad_to_deg(giant.rotation.y) - 9.0) < .001, "Search scans beneath elevated last-seen torso using planar arrival distance")
	NavigationServer3D.free_rid(map)
	giant.set_giant_navigation_map(RID())
	giant.position = Vector3(-40, 0, 0)
	giant.target_vehicle = rv
	giant.target_player = null
	giant._begin_smash()
	giant.phase_elapsed = 1.29
	giant._advance_smash()
	var prelock := giant._strike_point
	rv.position.x += 5.0
	giant.phase_elapsed = 1.3
	giant._advance_smash()
	var locked := giant._strike_point
	check(giant._strike_locked and locked.distance_to(prelock) > 4.9, "Smash tracks actual moving vehicle until lock at 1.3 seconds")
	rv.position.x += 5.0
	giant.phase_elapsed = 1.799
	giant._advance_smash()
	check(giant._strike_point.is_equal_approx(locked) and not second.is_destroyed, "Last .5 second keeps fixed landing point with no early panel damage")
	giant.phase_elapsed = 1.8
	giant._advance_smash()
	check(giant.phase == SlenderSpeaker.Phase.RECOVER, "At 1.8 seconds impact/miss enters recovery")
	giant._sense_remaining = 100.0
	giant._visible_target = false
	giant._physics_process(2.99)
	check(giant.phase == SlenderSpeaker.Phase.RECOVER, "Smash recovery still active at 2.99 seconds")
	giant._physics_process(.011)
	check(giant.phase != SlenderSpeaker.Phase.RECOVER, "Smash recovery ends after the configured3seconds")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: Slender Speaker behavior")
	else: print("FAIL Slender Speaker behavior: ", failures.size())
	quit(0 if failures.is_empty() else 1)
