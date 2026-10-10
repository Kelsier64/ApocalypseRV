extends "res://tests/test_slender_speaker_cabin_movement.gd"
## Production RV, survivor input, rig hand contact and full swept lift. Shares
## only fixture/step helpers with the continuous cabin movement regression.

func cross_cabin_hold() -> void:
	await fresh_fixture(Vector3(-1.15, .55, 4.7), Vector3(-9, 0, 4))
	var slots: RVStructureSlots = chassis.get_node("StructureSlots")
	var roof: RVStructurePanel = slots.panel("roof_2")
	roof.take_damage(roof.current_health)
	await frames(5)
	var initial_x := chassis.to_local(player.global_position).x
	var crossing_started := false
	var crossing_finished := false
	var movement_ticks := 0
	var opposite_plans := 0
	var body_crossed := false
	var capture_tick := -1
	var capture_y := 0.0
	var hold_tick := -1
	var far_side_x := -INF
	var capture_gap := 0.0
	var capture_probe: Dictionary = {}
	var releases: Array[String] = []
	player.grab_control.released.connect(func(reason: String) -> void: releases.append(reason))
	for tick in 1800:
		var local := chassis.to_local(player.global_position)
		if not crossing_started and giant._parked_plan.get("occupant") == player and giant._parked_plan.get("roof") == null:
			crossing_started = true
			check(chassis.to_local(giant._parked_plan.standoff_point).x < 0.0,
				"Visible near-side survivor first commits the real left exterior approach")
		if crossing_started and not crossing_finished:
			if local.x >= 1.15:
				crossing_finished = true
				movement("")
			else:
				movement("move_right")
				movement_ticks += 1
		else: movement("")
		await step()
		if not player.is_executing(): far_side_x = maxf(far_side_x, chassis.to_local(player.global_position).x)
		body_crossed = body_crossed or chassis.to_local(giant.global_position).x > 0.0
		if giant._parked_plan.get("occupant") == player and giant._parked_plan.get("roof") == null:
			if chassis.to_local(giant._parked_plan.standoff_point).x > 0.0: opposite_plans += 1
		if player.is_executing() and capture_tick < 0:
			capture_tick = tick
			capture_y = player.global_position.y
			capture_gap = giant.global_position.slide(Vector3.UP).distance_to(player.execution_contact_position().slide(Vector3.UP))
			capture_probe = giant._grab_capture_sweep.duplicate()
		if giant.phase == SlenderSpeaker.Phase.HOLD and player.is_executing():
			hold_tick = tick
			break
		if capture_tick >= 0 and not releases.is_empty(): break
	movement("")
	check(crossing_finished and movement_ticks >= 24 and far_side_x - initial_x > 2.2,
		"Survivor physically crosses left to right using sustained production movement")
	check(capture_gap > 4.3 and capture_gap < 5.5,
		"Actual far-side hand capture lies beyond 4.3m while remaining inside the bounded cabin reach")
	check(opposite_plans == 0 and not body_crossed,
		"Reachable far-side survivor retains the left exterior stance without circling the RV")
	check(capture_tick >= 0 and not capture_probe.is_empty() and giant._grab_touched,
		"Far-side survivor is acquired by an actual recorded palm or finger sweep")
	check(hold_tick > capture_tick and player.grab_control.captor == giant
		and player.global_position.y > capture_y + 5.0 and releases.is_empty(),
		"Same-side cross-cabin reach completes the full swept lift to HOLD without releasing")
	check(slots.panel("roof_0").can_operate() and slots.panel("roof_1").can_operate(),
		"Cross-cabin grab preserves roofs outside its real opening")
	print("CROSS_CABIN_REACH move_ticks=", movement_ticks, " range=", far_side_x - initial_x,
		" far_x=", far_side_x, " capture_gap=", capture_gap, " opposite_plans=", opposite_plans,
		" capture_s=", float(capture_tick) / 60.0, " hold_s=", float(hold_tick) / 60.0,
		" giant=", chassis.to_local(giant.global_position), " phase=", giant.phase,
		" sweep=", capture_probe, " blocked=", giant._grab_blocking_hits, " releases=", releases)

func longitudinal_reposition() -> void:
	await fresh_fixture(Vector3(-.85, .55, 4.7), Vector3(-3.24, 0, 4.7))
	var slots: RVStructureSlots = chassis.get_node("StructureSlots")
	slots.panel("roof_2").take_damage(slots.panel("roof_2").current_health)
	slots.panel("roof_1").take_damage(slots.panel("roof_1").current_health)
	await frames(5)
	check(giant.can_see_player(player), "Bounded reach fixture starts with actual rear-opening sight")
	var observed: Dictionary = giant._parked_attack.update(giant, chassis, STEP, player)
	var initial_stance: Vector3 = observed.standoff_point
	var initial_body := giant.global_position
	var initial_player := player.global_position
	# Leave the giant's controller disabled while the real survivor walks out
	# of its observed area. No planner reads the intermediate target positions.
	movement("move_forward")
	for tick in 68:
		await frames()
		player._physics_process(STEP)
	movement("")
	var target_delta := player.global_position - initial_player
	var observed_gap := initial_stance.slide(Vector3.UP).distance_to(player.execution_contact_position().slide(Vector3.UP))
	check(absf(target_delta.z) > 5.2 and observed_gap > 5.5,
		"Survivor physically walks beyond the finite 5.5m reach of the observed rear stance")
	# Turn the actual speaker toward the new observation. The target left its
	# original sight cone as well as its old reach area during the long walk.
	var direction := (player.global_position - giant.global_position).slide(Vector3.UP).normalized()
	giant.rotation.y = atan2(-direction.x, -direction.z)
	giant._sample("idle_play", 0.0)
	check(giant.can_see_player(player), "Out-of-range survivor remains genuinely visible through real roof openings")
	var changed := false
	for tick in 1200:
		await step()
		if giant._parked_plan.get("occupant") == player:
			var stance: Vector3 = giant._parked_plan.get("standoff_point", initial_stance)
			changed = changed or absf(stance.z - initial_stance.z) > .75
		if changed and absf(giant.global_position.z - initial_body.z) > .8: break
	movement("")
	check(changed and absf(giant.global_position.z - initial_body.z) > .8,
		"Visible survivor beyond the bounded reach changes the stance and moves the actual body longitudinally")
	print("CROSS_CABIN_REPOSITION player_delta=", target_delta, " stale_stance_gap=", observed_gap,
		" body_delta=", giant.global_position - initial_body, " changed=", changed,
		" plan=", giant._parked_plan)

func run() -> void:
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
	await cross_cabin_hold()
	await longitudinal_reposition()
	giant._cancel_execution("test_complete")
	giant.set_giant_navigation_map(RID())
	NavigationServer3D.free_rid(map)
	world.queue_free()
	await frames(3)
	if failures.is_empty(): print("PASS: same-side physical cross-cabin grab reaches HOLD and sustained out-of-area movement still repositions")
	quit(0 if failures.is_empty() else 1)
