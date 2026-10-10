extends SceneTree
## Production RV/Player, real input and swept movement. Continuous cabin
## motion must permit an authored attempt without bypassing sight or contact.
## --native-physics uses engine callbacks for variable render timing; omit
## --fixed-fps when validating that mode. Default stepping includes focused
## motion-envelope probes and is run by the fixed-FPS integration runner.
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const PLAYER := preload("res://player/player.tscn")
const VEHICLE := preload("res://rv/starter_rv.tscn")
const STEP := 1.0 / 60.0
const ROOF_SETUP_TICKS := 3600 # 60 seconds; autonomous approach and real demolition.
const MOVEMENT_TICKS := 480 # Eight seconds from the actual roof opening.
const RECOVERY_TICKS := 1200 # A separate 20-second stationary recovery window.
var failures: Array[String] = []
var world: Node3D
var giant: SlenderSpeaker
var player: CharacterBody3D
var vehicle: Node3D
var chassis: Chassis
var map: RID
var native_physics := false

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)

func frames(count := 1) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func movement(action: String) -> void:
	for other in ["move_forward", "move_back", "move_left", "move_right"]:
		if other == action: Input.action_press(other)
		else: Input.action_release(other)

func fresh_fixture(local_start: Vector3, giant_start: Vector3) -> void:
	movement("")
	if is_instance_valid(giant):
		giant._cancel_execution("fixture_reset")
		giant.queue_free()
	if is_instance_valid(player): player.queue_free()
	if is_instance_valid(vehicle): vehicle.queue_free()
	for part in get_nodes_in_group("player_detached_parts"): part.queue_free()
	await frames(3)
	var drops := world.get_node_or_null(WorldEntities.CONTAINER_NAME)
	if drops != null:
		drops.queue_free()
		await frames(3)
	vehicle = VEHICLE.instantiate()
	vehicle.position.y = 1.226
	world.add_child(vehicle)
	chassis = vehicle.get_node("Chassis")
	chassis.freeze = true
	player = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.global_position = chassis.to_global(local_start)
	player.grab_control.immunity = 0.0
	giant = GIANT.instantiate()
	world.add_child(giant)
	giant.set_physics_process(false)
	giant.set_giant_navigation_map(map)
	giant.global_position = giant_start
	var direction := (player.global_position - giant.global_position).slide(Vector3.UP).normalized()
	giant.rotation.y = atan2(-direction.x, -direction.z)
	giant._sample("idle_play", 0.0)
	await frames(5)
	var locomotion: Node = player.get_node("Visuals/Locomotion")
	locomotion.animation.play("locomotion/idle", 0.0)
	locomotion.animation.advance(0.0)
	player.get_node("Visuals").skeleton.force_update_all_bone_transforms()
	check(player.seated_in == null and player.can_be_executed(), "Moving fixture uses an unseated production survivor")
	if native_physics:
		player.set_physics_process(true)
		giant.set_physics_process(true)

func step() -> void:
	await frames()
	if not native_physics:
		player._physics_process(STEP)
		giant._physics_process(STEP)

func elapsed_seconds(start_frame: int, manual_tick: int) -> float:
	return float(Engine.get_physics_frames() - start_frame) * STEP if native_physics else float(manual_tick) * STEP

func readiness_diagnostics() -> Dictionary:
	var plan := giant._parked_plan
	var result := {
		"phase": SlenderSpeaker.Phase.keys()[giant.phase],
		"intent": giant._encounter_decision.get("intent", "none"),
		"status": plan.get("status", "missing"), "action": plan.get("action", "none"),
		"visible": giant.can_see_player(player), "executable": player.can_be_executed(),
		"roof": plan.get("roof"), "occupant_is_player": plan.get("occupant") == player,
		"settled": giant._parked_facing_waypoint != Vector3.INF,
		"navigation_ready": map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0,
	}
	if not plan.has("standoff_point"): return result
	var stance: Vector3 = plan.standoff_point
	result.stance_gap = giant.global_position.slide(Vector3.UP).distance_to(stance.slide(Vector3.UP))
	result.facing = giant._facing_dot(plan.get("facing_point", plan.surface_point))
	result.required_facing = plan.get("facing_dot", -1.0)
	result.clearance = plan.get("clearance", -1.0)
	result.reach_gap = plan.get("gap", -1.0)
	if plan.has("route_frame"):
		var inverse: Transform3D = plan.route_frame.affine_inverse()
		result.longitudinal_gap = absf((inverse * giant.global_position).z - (inverse * stance).z)
	return result

func oscillation(cross_cabin: bool) -> void:
	var label := "CROSS_CABIN" if cross_cabin else "FRONT_BACK"
	await fresh_fixture(Vector3(-.65 if cross_cabin else 0.0, .55, 4.7), Vector3(-9, 0, 4))
	var roof: RVStructurePanel = chassis.get_node("StructureSlots").panel("roof_2")
	# Setup cannot consume the movement/recovery budget. No roof damage,
	# phase or target is granted: wait for the autonomous swept demolition.
	var setup_start_frame := Engine.get_physics_frames()
	var setup_ticks := 0
	while not roof.is_destroyed and elapsed_seconds(setup_start_frame, setup_ticks) < ROOF_SETUP_TICKS * STEP:
		await step()
		setup_ticks += 1
	var setup_seconds := elapsed_seconds(setup_start_frame, setup_ticks)
	print("CABIN_ROOF_SETUP ", label, " seconds=", setup_seconds, " roof_destroyed=", roof.is_destroyed,
		" readiness=", readiness_diagnostics())
	check(roof.is_destroyed, label + " autonomously removes the real roof within the bounded setup window")
	if not roof.is_destroyed: return
	var moving_ticks := 0
	var observed_ticks := 0
	var attack_starts := 0
	var finished_attempts := 0
	var side_changes := 0
	var previous_side := 0.0
	var previous_stance := Vector3.INF
	var previous_facing_point := Vector3.INF
	var largest_facing_drift := 0.0
	var unchanged_ticks := 0
	var longest_unchanged := 0
	var nearest_stance := INF
	var best_facing := -1.0
	var settled_ticks := 0
	var minimum_coordinate := INF
	var maximum_coordinate := -INF
	var direction := 1.0
	var first_grab := -1.0
	var capture_at := -1.0
	var captured_moving := false
	var stationary_ticks := 0
	var logged_arrival := false
	var logged_settled := false
	var logged_deadline := false
	var previous_phase := giant.phase
	var start_frame := Engine.get_physics_frames()
	# Eight seconds of perpetual movement after the real roof removal, then
	# a separate stationary recovery window. A physical capture ends input.
	for tick in MOVEMENT_TICKS + RECOVERY_TICKS:
		var elapsed := elapsed_seconds(start_frame, tick)
		if elapsed >= (MOVEMENT_TICKS + RECOVERY_TICKS) * STEP: break
		var moving: bool = elapsed < MOVEMENT_TICKS * STEP and not player.is_executing()
		var local := chassis.to_local(player.global_position)
		var coordinate := local.x if cross_cabin else local.z
		if moving:
			if coordinate >= (.65 if cross_cabin else 5.0): direction = -1.0
			elif coordinate <= (-.65 if cross_cabin else 4.4): direction = 1.0
			movement(("move_right" if direction > 0.0 else "move_left") if cross_cabin else ("move_back" if direction > 0.0 else "move_forward"))
			moving_ticks += 1
			minimum_coordinate = minf(minimum_coordinate, coordinate)
			maximum_coordinate = maxf(maximum_coordinate, coordinate)
		else:
			movement("")
			stationary_ticks += 1
		await step()
		if moving and giant.can_see_player(player): observed_ticks += 1
		if giant.phase == SlenderSpeaker.Phase.GRAB and previous_phase != giant.phase:
			if moving: attack_starts += 1
			if first_grab < 0.0: first_grab = elapsed_seconds(start_frame, tick)
		if previous_phase == SlenderSpeaker.Phase.GRAB and giant.phase in [SlenderSpeaker.Phase.RECOVER, SlenderSpeaker.Phase.LIFT]: finished_attempts += 1
		previous_phase = giant.phase
		if moving and giant.phase == SlenderSpeaker.Phase.CHASE and not giant._parked_plan.is_empty() and giant._parked_plan.get("occupant") == player and giant._parked_plan.get("roof") == null:
			var stance: Vector3 = giant._parked_plan.standoff_point
			var facing_point: Vector3 = giant._parked_plan.get("facing_point", giant._parked_plan.surface_point)
			if previous_stance != Vector3.INF and stance.distance_to(previous_stance) < .01:
				largest_facing_drift = maxf(largest_facing_drift, facing_point.distance_to(previous_facing_point))
			previous_facing_point = facing_point
			nearest_stance = minf(nearest_stance, giant.global_position.slide(Vector3.UP).distance_to(stance.slide(Vector3.UP)))
			best_facing = maxf(best_facing, giant._facing_dot(giant._parked_plan.surface_point))
			if giant._parked_facing_waypoint != Vector3.INF: settled_ticks += 1
			var side := signf(chassis.to_local(stance).x)
			if previous_side != 0.0 and side != previous_side: side_changes += 1
			previous_side = side
			unchanged_ticks = unchanged_ticks + 1 if previous_stance != Vector3.INF and stance.distance_to(previous_stance) < .01 else 0
			longest_unchanged = maxi(longest_unchanged, unchanged_ticks)
			previous_stance = stance
			if not logged_arrival and giant.global_position.slide(Vector3.UP).distance_to(stance.slide(Vector3.UP)) < .12:
				logged_arrival = true
				print("CABIN_FIRST_ARRIVAL ", label, " movement_seconds=", elapsed,
					" readiness=", readiness_diagnostics())
			if not logged_settled and giant._parked_facing_waypoint != Vector3.INF:
				logged_settled = true
				print("CABIN_FIRST_SETTLED ", label, " movement_seconds=", elapsed,
					" readiness=", readiness_diagnostics())
		if not moving and not logged_deadline and attack_starts == 0:
			logged_deadline = true
			print("CABIN_MOVEMENT_DEADLINE ", label, " readiness=", readiness_diagnostics())
		if player.is_executing():
			capture_at = elapsed_seconds(start_frame, tick)
			captured_moving = moving
			break
	print("CABIN_MOVEMENT ", label, " roof=", roof.is_destroyed, " moving_ticks=", moving_ticks,
		" observed_ticks=", observed_ticks, " physical_range=", maximum_coordinate - minimum_coordinate,
		" moving_attempts=", attack_starts, " completed_attempts=", finished_attempts,
		" stable_ticks=", longest_unchanged, " side_changes=", side_changes,
		" nearest_stance=", nearest_stance, " best_facing=", best_facing, " settled_ticks=", settled_ticks,
		" first_grab_seconds=", first_grab, " capture_seconds=", capture_at,
		" captured_moving=", captured_moving, " stationary_ticks=", stationary_ticks,
		" setup_seconds=", setup_seconds, " readiness=", readiness_diagnostics(),
		" giant=", giant.global_position, " local_player=", chassis.to_local(player.global_position))
	check(roof.is_destroyed, label + " removes the real roof before testing cabin grab movement")
	check(captured_moving or elapsed_seconds(start_frame, moving_ticks) >= MOVEMENT_TICKS * STEP,
		label + " preserves the entire eight-second movement window unless live hand contact captures the survivor")
	check(moving_ticks >= 30 and maximum_coordinate - minimum_coordinate > (.8 if cross_cabin else .4), label + " uses sustained physical Player movement inside the cabin")
	check(observed_ticks >= 24, label + " actually observes the moving survivor")
	check(attack_starts > 0 and finished_attempts > 0, label + " starts and resolves a real grab during continuous movement")
	check(capture_at >= 0.0 and player.grab_control.captor == giant, label + " eventually captures through live hand contact, including stationary recovery after a miss")
	check(side_changes <= 2, label + " avoids frantic repeated side reversal")
	check(largest_facing_drift < .01, label + " keeps torso aim fixed with the committed stance while hands observe live movement")
	if not cross_cabin: check(longest_unchanged >= 24, label + " retains a committed stance while the observed survivor makes small longitudinal moves")
	movement("")
	if native_physics:
		player.set_physics_process(false)
		giant.set_physics_process(false)

func transient_occlusion() -> void:
	await fresh_fixture(Vector3(0, .55, 4.7), Vector3(-9, 0, 4))
	var ready := false
	var setup_start_frame := Engine.get_physics_frames()
	for tick in ROOF_SETUP_TICKS:
		if elapsed_seconds(setup_start_frame, tick) >= ROOF_SETUP_TICKS * STEP: break
		await step()
		if giant.phase == SlenderSpeaker.Phase.CHASE and not giant._parked_plan.is_empty() and giant._parked_plan.get("roof") == null and giant._parked_plan.get("occupant") == player:
			var gap := giant.global_position.slide(Vector3.UP).distance_to(Vector3(giant._parked_plan.standoff_point).slide(Vector3.UP))
			if gap < .6 and gap > .15:
				ready = true
				break
	print("CABIN_OCCLUSION_SETUP ready=", ready, " readiness=", readiness_diagnostics())
	check(ready, "Wall fixture autonomously reaches the visible post-roof grab approach within bounded setup")
	if not ready: return
	var live_margin := float(giant._parked_plan.get("body_margin", -1.0))
	var seen_point: Vector3 = giant._encounter_decision.point
	var contact: Vector3 = player.execution_contact_position()
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.06, 14, 6)
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)
	# The real eye leans inside the shell after bending. Place the screen in
	# the empty aisle between that eye and the survivor, with physical room
	# for both actors; it cannot manufacture contact or block their movement.
	var frame: Transform3D = giant._parked_plan.route_frame
	wall.global_position = frame * Vector3(-1.0, 7.0, chassis.to_local(contact).z)
	await frames(3)
	check(not giant.can_see_player(player), "A real transient wall occludes the cabin survivor")
	var hidden_ticks := 0
	var margin_preserved := true
	var point_preserved := true
	var memory_smash_planned := false
	var hidden_capture := false
	var before_hidden_move := player.global_position
	for tick in 36:
		movement("move_forward" if tick < 6 else "")
		await step()
		if not giant.can_see_player(player):
			hidden_ticks += 1
			margin_preserved = margin_preserved and is_equal_approx(float(giant._parked_approach_memory.get("body_margin", -2.0)), live_margin)
			# Losing sight permits a new approach/turn for a last-seen smash.
			# The observed contact, rather than the former grab stance, is fixed.
			point_preserved = point_preserved and Vector3(giant._encounter_decision.point).distance_to(seen_point) < .01
			if giant._parked_plan.get("smash_kind") == "cabin_memory":
				memory_smash_planned = true
				point_preserved = point_preserved and Vector3(giant._parked_plan.surface_point).distance_to(seen_point) < .01
				check(giant._parked_plan.get("occupant") == null and giant._parked_plan.action != "grab", "Last-seen cabin strikes never substitute a hidden occupant for a live grab")
			hidden_capture = hidden_capture or player.is_executing()
	check(hidden_ticks >= 24 and margin_preserved and live_margin >= 1.1 and live_margin < 1.24, "Observed grab clearance survives real occlusion without switching to the incompatible follower margin")
	check(point_preserved and memory_smash_planned, "Hidden physical movement cannot update the last-seen cabin strike point while its approach replans")
	check(player.global_position.distance_to(before_hidden_move) > .35, "Wall-obscured survivor moves with real input before stopping")
	check(not hidden_capture, "Memory alone never captures the wall-obscured survivor")
	movement("")
	wall.queue_free()
	await frames(3)
	if not native_physics: await remembered_boundary_sweep()
	var capture := false
	for tick in 1200:
		await step()
		if player.is_executing():
			capture = true
			break
	print("CABIN_OCCLUSION hidden_ticks=", hidden_ticks, " live_margin=", live_margin,
		" margin_preserved=", margin_preserved, " point_preserved=", point_preserved,
		" memory_smash_planned=", memory_smash_planned,
		" captured_after_wall=", capture, " giant=", giant.global_position)
	check(capture, "Removing the real wall restores sight and physically captures the now-stationary survivor after movement")
	if native_physics:
		player.set_physics_process(false)
		giant.set_physics_process(false)

func remembered_boundary_sweep() -> void:
	# A focused motion-envelope fixture uses the geometry acquired above.
	# Place the body at two boundary positions; actual sight, acceleration,
	# the controller's reserve and CharacterBody sweep still own each probe.
	var original_position := giant.global_position
	var snapshot: Dictionary = giant._parked_approach_memory.duplicate()
	var frame: Transform3D = snapshot.route_frame
	var shell: AABB = snapshot.route_shell
	var local_stance: Vector3 = frame.affine_inverse() * Vector3(snapshot.standoff_point)
	giant.global_position = frame * Vector3(shell.position.x - 1.24, -frame.origin.y, local_stance.z)
	var eye_screen := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.02, 20, 20)
	collision.shape = shape
	eye_screen.add_child(collision)
	world.add_child(eye_screen)
	# The last-seen smash turns at a different pose from the former grab.
	# A box on socket_focus can now overlap the tall body capsule and make
	# move_and_slide depenetrate outwards, masking the velocity reserve.
	# Screen the whole shell from its side, outside both probe positions.
	eye_screen.global_position = frame * Vector3(shell.position.x - .04, 7.5, local_stance.z)
	await frames(3)
	giant._refresh_sight()
	giant._update_encounter(STEP)
	check(giant._observation.get("vehicle") == null and giant._observation.get("player") == null and giant.target_vehicle == chassis and not giant._parked_approach_memory.is_empty(), "Real eye occlusion clears observations while retaining the encounter and observed shell geometry")
	var inward := frame.basis.x
	var before := giant.global_position
	giant.velocity = inward * .3
	giant._move_swept(inward * .3, STEP)
	var low_step := (giant.global_position - before).dot(inward)
	check(low_step > .002 and low_step < .008, "Occluded remembered grab stance permits safe inward swept movement inside the follower's old margin")
	giant.global_position = frame * Vector3(shell.position.x - 1.19, -frame.origin.y, local_stance.z)
	giant.velocity = inward * 3.0
	before = giant.global_position
	giant._move_swept(inward * 3.0, STEP)
	var blocked_step := (giant.global_position - before).dot(inward)
	check(absf(blocked_step) < .003 and giant.velocity.dot(inward) < .01, "Occluded remembered shell applies the physical reserve before a fast inward CharacterBody sweep")
	print("CABIN_MEMORY_SWEEP low_speed_step=", low_step, " reserved_step=", blocked_step,
		" reserved_speed=", giant.velocity.dot(inward), " live_target=", giant.target_vehicle)
	giant.global_position = original_position
	giant.velocity = Vector3.ZERO
	eye_screen.queue_free()
	await frames(3)
	giant._refresh_sight()

func run() -> void:
	native_physics = "--native-physics" in OS.get_cmdline_user_args()
	print("CABIN_PHYSICS_MODE ", "engine_callbacks" if native_physics else "controlled_fixed_step")
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_collision)
	world.add_child(floor_body)
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-100, 0, -100), Vector3(-100, 0, 100), Vector3(100, 0, 100), Vector3(100, 0, -100)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)
	region.set_navigation_map(map)
	await frames(3)
	NavigationServer3D.map_force_update(map)
	await oscillation(false)
	await oscillation(true)
	await transient_occlusion()
	movement("")
	giant._cancel_execution("test_complete")
	giant.set_giant_navigation_map(RID())
	NavigationServer3D.free_rid(map)
	world.queue_free()
	await frames(3)
	if failures.is_empty():
		print("PASS: real moving cabin survivors permit stable approaches and live grab attempts through transient occlusion; ", "engine callbacks, envelope probes omitted" if native_physics else "controlled stepping with envelope probes")
	quit(0 if failures.is_empty() else 1)
