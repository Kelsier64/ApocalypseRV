extends SceneTree
## Live controller on actual v10 terrain/trunks, including simplified slope heights.
## Only scenario setup places actors; patrol, perception and giant motion stay live.
const WAIT := preload("res://tests/support/test_wait.gd")
var failures: Array[String] = []
var world: Node3D
var generator: Node
var giant: SlenderSpeaker
var player: CharacterBody3D
var rv: Chassis
var spawn_position := Vector3.ZERO
var first_arrival_position := Vector3.INF

func _init() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func frames(count := 1) -> void:
	for tick in count: await physics_frame

func freeze_actor(actor: Node) -> void:
	if actor is Monster: actor.process_mode = Node.PROCESS_MODE_DISABLED

func terrain_point(point: Vector3) -> Vector3:
	point.y = generator.field.height_at(point.x, point.z) + .05
	return point

func reset_giant(point: Vector3, facing: Vector3) -> void:
	giant.set_physics_process(false)
	giant.global_position = point
	giant.velocity = Vector3.ZERO
	giant.reset_after_restore()
	giant._patrol_index = 0
	var direction := (facing - point).slide(Vector3.UP).normalized()
	giant.rotation.y = atan2(-direction.x, -direction.z)
	giant._sample("idle_play", 0.0)
	giant.set_physics_process(true)

func patrol() -> void:
	var travelled := 0.0
	var previous := giant.global_position
	var height_mismatch_ticks := 0
	var longest_stall := 0
	var stall := 0
	var window_start := previous
	for tick in 3600:
		await frames()
		travelled += giant.global_position.distance_to(previous)
		previous = giant.global_position
		if giant._patrol_index == 1 and first_arrival_position == Vector3.INF:
			first_arrival_position = previous
		var path := giant.nav_agent.get_current_navigation_path()
		var index := giant.nav_agent.get_current_navigation_path_index()
		if giant.is_on_floor() and index < path.size() and absf(path[index].y - previous.y) > giant.nav_agent.path_desired_distance:
			height_mismatch_ticks += 1
		if tick % 60 == 59:
			stall = stall + 60 if previous.slide(Vector3.UP).distance_to(window_start.slide(Vector3.UP)) < .3 else 0
			longest_stall = maxi(longest_stall, stall)
			window_start = previous
	check(giant._patrol_index >= 4, "Actual forest patrol reaches at least four consecutive destinations in 60 seconds")
	check(travelled > 140.0 and longest_stall < 180, "Forest patrol keeps progressing through slope waypoints without prolonged circling")
	check(height_mismatch_ticks > 0, "Actual physical terrain exercises waypoint height errors larger than the path tolerance")
	check(giant.target_player == null and giant.target_vehicle == null, "Distant production player and RV do not seed patrol targets")
	print("FOREST_PATROL index=", giant._patrol_index, " travel=", travelled, " height_mismatch_ticks=", height_mismatch_ticks, " longest_stall_seconds=", float(longest_stall) / 60.0)

func ground_tracking() -> void:
	# The second patrol route includes the exact slope that formerly pinned
	# path index 28 forever, now approached through normal visible-player intent.
	var angle := 2.399963
	player.global_position = terrain_point(spawn_position + Vector3(cos(angle), 0, sin(angle)) * 22.0)
	reset_giant(first_arrival_position if first_arrival_position != Vector3.INF else spawn_position, player.global_position)
	var initial_gap := giant.global_position.slide(Vector3.UP).distance_to(player.global_position.slide(Vector3.UP))
	var minimum_gap := initial_gap
	var acquired := false
	var approach_ticks := 0
	var trunk_contact_ticks := 0
	var recovery_ticks := 0
	var maximum_step := 0.0
	var previous := giant.global_position
	var destroyed_trees: Dictionary = generator.destroyed_trees.duplicate()
	for tick in 2400:
		await frames()
		maximum_step = maxf(maximum_step, giant.global_position.distance_to(previous))
		previous = giant.global_position
		if giant._navigation_recovery_point != Vector3.INF: recovery_ticks += 1
		for index in giant.get_slide_collision_count():
			if giant.get_slide_collision(index).get_collider() is ForestTrunks:
				trunk_contact_ticks += 1
				break
		acquired = acquired or giant.target_player == player
		if giant._encounter_decision.get("intent") == "ground": approach_ticks += 1
		minimum_gap = minf(minimum_gap, giant.global_position.slide(Vector3.UP).distance_to(player.global_position.slide(Vector3.UP)))
		if tick % 300 == 0:
			var path := giant.nav_agent.get_current_navigation_path()
			var index := giant.nav_agent.get_current_navigation_path_index()
			var hits := []
			for i in giant.get_slide_collision_count():
				var hit := giant.get_slide_collision(i)
				hits.append([str(hit.get_collider()), str(hit.get_normal())])
			print("FOREST_PLAYER_TRACE tick=", tick, " position=", giant.global_position, " velocity=", giant.velocity, " next=", path[index] if index < path.size() else Vector3.INF, " index=", index, " target=", giant.nav_agent.target_position, " hits=", hits)
		if minimum_gap < 3.0: break
	check(acquired and approach_ticks > 30, "Real forest sight acquires the on-foot production player and maintains ground pursuit")
	check(initial_gap > 30.0 and minimum_gap < 3.0, "Ground pursuit physically crosses the forest slope and reaches the player")
	check(trunk_contact_ticks > 0 and recovery_ticks > 0, "Ground pursuit recovers from an actual production trunk collision")
	check(maximum_step < .3 and generator.destroyed_trees == destroyed_trees, "Trunk recovery uses continuous body motion and preserves forest obstacles")
	print("FOREST_PLAYER initial_gap=", initial_gap, " minimum_gap=", minimum_gap, " approach_ticks=", approach_ticks, " trunk_contact_ticks=", trunk_contact_ticks, " recovery_ticks=", recovery_ticks, " maximum_step=", maximum_step, " reason=", giant._encounter_decision.get("reason"))
	giant.set_physics_process(false)

func vehicle_tracking() -> void:
	player.global_position = spawn_position + Vector3(0, 0, 260)
	var road: Transform3D = generator.field.road_frame(-spawn_position.z - 20.0)
	rv.freeze = true
	rv.global_transform = Transform3D(road.basis, road.origin + Vector3.UP * .7)
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	rv.set_handbrake(true)
	rv.freeze = false
	await frames(180)
	rv.allow_test_controls = true
	rv.gear = 1
	check(rv.set_engine_running(true), "Wheel-driven RV starts its actual engine")
	rv.set_handbrake(false)
	rv.control_override = {"throttle": 1.0}
	reset_giant(spawn_position, rv.global_position)
	var start := giant.global_position
	var rv_start := rv.global_position
	var minimum_gap := INF
	var pursuit_ticks := 0
	var observed_ticks := 0
	var maximum_speed := 0.0
	for tick in 1800:
		var speed := rv.road_speed()
		var lookahead: Vector3 = generator.field.road_frame(-rv.global_position.z + 12.0).origin
		var local_target := rv.to_local(lookahead)
		var steering := clampf(-atan2(local_target.x, -local_target.z) * 1.8, -.65, .65)
		rv.control_override = {"throttle": clampf((5.0 - speed) * .6, 0.0, 1.0), "steering": steering}
		await frames()
		maximum_speed = maxf(maximum_speed, rv.road_speed())
		if giant._vehicle_is_observed(rv): observed_ticks += 1
		if giant.target_vehicle == rv and giant._encounter_decision.get("mode") == "pursuit": pursuit_ticks += 1
		minimum_gap = minf(minimum_gap, giant.global_position.slide(Vector3.UP).distance_to(rv.global_position.slide(Vector3.UP)))
	rv.control_override.clear()
	rv.set_handbrake(true)
	check(maximum_speed > 10.0 / 3.6 and rv.global_position.distance_to(rv_start) > 60.0, "Production RV travels on real wheels above pursuit speed on the generated road")
	check(observed_ticks > 600 and pursuit_ticks > 600, "Forest giant repeatedly sees and tracks the moving production RV")
	check(giant.global_position.distance_to(start) > 60.0 and minimum_gap < 15.0, "Giant exits the forest slope and physically closes on the wheel-driven RV")
	print("FOREST_RV maximum_speed_kmh=", maximum_speed * 3.6, " vehicle_travel=", rv.global_position.distance_to(rv_start), " giant_displacement=", giant.global_position.distance_to(start), " minimum_gap=", minimum_gap, " pursuit_ticks=", pursuit_ticks, " observed_ticks=", observed_ticks)

func run() -> void:
	world = load("res://world/main_world.tscn").instantiate()
	generator = world.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = generator.profile.duplicate()
	generator.profile.chunks_ahead = 0
	generator.profile.chunks_behind = 0
	root.add_child(world)
	current_scene = world
	WorldEntities.get_container(world).child_entered_tree.connect(freeze_actor)
	if not await world.wait_for_play(90000) or not await WAIT.generator_idle(self, generator, 90000):
		check(false, "Production startup navigation publishes")
		world.free()
		quit(1)
		return
	generator.set_process(false)
	player = world.get_node("Player")
	player.set_physics_process(false)
	world.get_node("StartRun").restore({"version": 1, "phase": "sealed"})
	var clock: WorldClock = world.get_node("WorldClock")
	clock.weather_running = false
	clock.weather.set_weather(Vector3(0, 0, WorldWeather.FOG_LIGHT), true)
	var plan := SlenderSpeakerSpawns.plan(generator.field, 11)
	player.global_position = plan.candidates[0] + Vector3(0, 0, 260)
	for band in [113, 114, 115]:
		await generator._spawn_band(band, true)
		if not await WAIT.generator_idle(self, generator, 90000):
			check(false, "Forest terrain and giant navigation publish")
			world.free()
			quit(1)
			return
	generator._spawn_giant_segments(player.global_position)
	for actor in get_nodes_in_group("slender_speaker"):
		if WorldEntities.same_world(world, actor): giant = actor
	check(giant != null, "Actual forest planner spawns the regression giant")
	if giant != null:
		rv = world.get_node("NewRv/Chassis")
		spawn_position = giant.global_position
		giant.process_mode = Node.PROCESS_MODE_INHERIT
		await patrol()
		await ground_tracking()
		await vehicle_tracking()
	world.free()
	await frames(3)
	if failures.is_empty(): print("PASS: production forest patrol, ground-player pursuit and wheel-driven RV tracking across real slope waypoints")
	quit(0 if failures.is_empty() else 1)
