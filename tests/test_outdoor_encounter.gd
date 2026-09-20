extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(okay: bool, message: String) -> void:
	if not okay:
		failures.append(message)
		push_error("FAIL: " + message)
func frames(count: int) -> void:
	for i in range(count): await physics_frame

func _run() -> void:
	var main: Node3D = load("res://world/test_world.tscn").instantiate()
	var generator = main.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = WorldProfile.new()
	generator.profile.generation_version = 4 # This fixture exercises the two forest entrances.
	generator.profile.chunks_ahead = 1
	generator.profile.chunks_behind = 1
	root.add_child(main)
	current_scene = main
	# This test explicitly schedules bands and revisits the starting vehicle.
	# Suspend the monotonic streaming controller during those test teleports.
	generator.set_process(false)
	for actor in get_nodes_in_group(Groups.MONSTERS): actor.queue_free()
	while not generator.active_chunks.all(func(c): return c.node.navigation_ready): await process_frame
	await frames(10)
	var site: Dictionary = generator.field.stop(0)
	var player = main.get_node("Player")
	player.in_ui_mode = true
	player.current_player_health = 10000
	var monster: Monster = load("res://enemies/zombie.tscn").instantiate()
	WorldEntities.get_container(main).add_child(monster)
	monster.global_position = site.route[0] + Vector3.UP * 0.1
	monster.detection_range = 90
	monster.lose_interest_range = 110
	# Each target forces a real turn through a staggered gate, no teleporting AI.
	for index in [3, 5, 7, 9, 11]:
		player.global_position = site.route[index] + Vector3.UP * 0.1
		player.velocity = Vector3.ZERO
		var reached := false
		for tick in range(2700):
			await physics_frame
			if monster.global_position.distance_to(player.global_position) < 2.5:
				reached = true
				break
		check(reached, "Monster traverses gate toward %d, actual %s" % [index, monster.global_position])
		if not reached: break
	var remote: Dictionary = generator.field.stop(1)
	for band in generator.protected_bands(remote.route[4]):
		if not generator.active_chunks.any(func(c): return c.index == band): await generator._spawn_band(band, true)
	while not generator.active_chunks.all(func(c): return c.node.navigation_ready): await process_frame
	monster.global_position = remote.route[2] + Vector3.UP * 0.1
	monster.velocity = Vector3.ZERO
	player.global_position = remote.route[3] + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	var crossed := false
	for tick in range(1500):
		await physics_frame
		if monster.global_position.distance_to(player.global_position) < 2.5:
			crossed = true
			break
	check(crossed, "Production monster crosses streamed seam and rotated gate")
	monster.queue_free()
	player.global_position = site.road.origin + Vector3(0, 1, 30)
	var rv: Chassis = main.get_node("NewRv/Chassis")
	rv.global_transform = Transform3D(Basis.looking_at(site.road.basis.x * float(site.side)), site.road.origin + Vector3.UP * 1.1)
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	rv.allow_test_controls = true
	rv.control_override = {"throttle": 0.4}
	rv.handbrake = false
	rv.set_engine_running(true)
	var entered := false
	for tick in range(900):
		await physics_frame
		var p: Vector3 = site.road.affine_inverse() * rv.global_position
		if p.x * float(site.side) > 27:
			entered = true
			break
	check(entered, "Wheel-driven RV reaches parking from road")
	rv.control_override = {"throttle": 0.5}
	await frames(300)
	var position: Vector3 = site.road.affine_inverse() * rv.global_position
	check(position.x * float(site.side) < 44, "Full production RV cannot pass 1.8m gateway")
	rv.control_override = {"brake": 1.0}
	rv.handbrake = true
	await frames(90)
	check(rv.linear_velocity.length() < 1, "Vehicle brakes at obstructed gateway")
	main.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: monster walks staggered gates, wheel-driven RV parking, physical gateway rejection and braking")
	quit(0 if failures.is_empty() else 1)
