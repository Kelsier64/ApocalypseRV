extends SceneTree
## Production Player/RV target shapes, authored fingers and extraction ownership.
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const PLAYER := preload("res://player/player.tscn")
const VEHICLE := preload("res://rv/new_rv.tscn")
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

func grab() -> bool:
	giant._begin_grab()
	for i in 60:
		giant.phase_elapsed = float(i + 1) / 60.0
		giant._advance_grab()
		if giant.phase != SlenderSpeaker.Phase.GRAB: break
	print("ACQUISITION pose=", player.global_position, " contact=", player.execution_contact_position(), " phase=", giant.phase, " blocked=", giant._grab_blocked, " hands=", giant._grab_hands_touched)
	if giant._grab_blocked: print("BLOCKERS ", giant._grab_blocking_hits)
	return player.is_executing()

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
	check(grab(), "Production standing torso is grabbed by both real hand paths")
	if player.is_executing():
		var capture_elapsed := 0.0
		while capture_elapsed < 2.5 and player.is_executing():
			giant.phase_elapsed += 1.0 / 60.0
			giant._advance_execution()
			capture_elapsed += 1.0 / 60.0
		check(player.is_player_dead and absf(capture_elapsed - 2.4) < .018, "Capture-to-crush duration matches music impact at 2.4 seconds within one physics frame")
	player.ragdoll_control.stop()
	for part in get_nodes_in_group("player_detached_parts"): part.queue_free()
	await frames()
	reset_player(Vector3(0, -.249, -2.1))
	await frames()
	settle_pose()
	pose_giant(Vector3(0, 0, 2.1))
	giant._begin_grab()
	for i in 59:
		giant.phase_elapsed = float(i + 1) / 60.0
		giant._advance_grab()
	check(giant._grab_hands_touched.size() == 2, "Both hands physically touched during locked reach before late evasion")
	player.global_position += Vector3(cos(PI / 4.0), 0, sin(PI / 4.0)) * .64
	await frames()
	giant.phase_elapsed = 1.0
	giant._advance_grab()
	check(not giant._hand_currently_touches_player("L") and giant._hand_currently_touches_player("R"), "Production late sidestep leaves only one hand physically touching")
	check(not player.is_executing() and not giant.execution_music.playing and giant.phase == SlenderSpeaker.Phase.RECOVER, "Stale earlier left-hand contact cannot authorize bilateral capture or execution music")
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

	var seat: Node3D = chassis.get_node("DriverSeat")
	reset_player(seat.global_position)
	seat.interact_hold(player)
	player._physics_process(1.0 / 60.0)
	await frames(3)
	settle_pose()
	check(seat.current_driver == player, "Production driver seat owns disabled locomotion capsule")
	pose_giant(Vector3(-2.57, 0, 0))
	check(not grab() and player.seated_in == seat and not giant.execution_music.playing, "Intact real glass and shell block driver grab without changing ownership/music")
	# A real removed 4m side panel creates a broad aperture beside the driver.
	var panel: RVStructurePanel = chassis.get_node("StructureSlots").panel("left_0")
	check(panel != null, "Production left-front shell panel exists")
	if panel != null: panel.take_damage(panel.current_health)
	await frames(3)
	giant.target_player = null
	giant.target_vehicle = null
	chassis.linear_velocity = Vector3(0, 0, -1)
	pose_giant(Vector3(-60.0, 0, 0))
	giant._refresh_sight()
	check(giant.target_player == player, "Visible driver acquired through real aperture even when nearest moving RV surface is closer")
	giant.target_player = player
	pose_giant(Vector3(-2.57, 0, 0))
	check(grab(), "Large real side-panel aperture permits both hands to grab disabled seated torso")
	if player.is_executing():
		check(player.seated_in == null and seat.current_driver == null, "Validated driver capture clears both seat ownership references")
		# The remaining roof must still prevent a vertical lift through the cabin.
		giant.phase_elapsed = .8
		giant._advance_execution()
		player._physics_process(1.0 / 60.0)
		check(not player.is_executing() and not player.is_player_dead and not giant.execution_music.playing, "Remaining roof safely cancels blocked extraction without wall penetration or death")
	giant._cancel_execution("fixture_reset")
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
	check(giant.resolve_smash_hit(physical_hit.get("collider")), "One real production shell panel is destroyed at impact")
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
	check(early_panel.is_destroyed and not blocked_target.is_destroyed, "Windup holds at first actual panel and destroys only that panel at1.8sec instead of panel behind")
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
