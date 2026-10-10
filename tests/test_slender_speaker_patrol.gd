extends SceneTree
## Real sight expiry beside a production RV whose live shell is absent from nav.
## After setup, the controller owns every target, phase, turn and body movement.
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const VEHICLE := preload("res://rv/new_rv.tscn")
const Wait := preload("res://tests/support/test_wait.gd")
var failures: Array[String] = []
var world: Node3D
var giant: SlenderSpeaker
var rv: Chassis
var map: RID

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)

func frames(count := 1) -> void:
	for tick in count: await physics_frame

func setup(yaw_degrees: float, blocked_goal := false) -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	# A streamed terrain polygon deliberately does not contain the parked RV.
	mesh.vertices = PackedVector3Array([Vector3(-100, 0, -100), Vector3(-100, 0, 100), Vector3(100, 0, 100), Vector3(100, 0, -100)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)
	region.set_navigation_map(map)
	var vehicle := VEHICLE.instantiate()
	world.add_child(vehicle)
	rv = vehicle.get_node("Chassis")
	rv.freeze = true
	rv.rotation.y = deg_to_rad(yaw_degrees)
	# An empty, already roofless vehicle provides no renewable roof inspection
	# evidence. Real sight starts the encounter and its normal deadline ends it.
	for id in ["roof_0", "roof_1", "roof_2"]:
		var roof: RVStructurePanel = rv.get_node("StructureSlots").panel(id)
		roof.take_damage(roof.current_health)
	giant = GIANT.instantiate()
	giant.position = Vector3(-4.5 if is_zero_approx(yaw_degrees) else -9.0, .02, 0)
	giant.rotation.y = -PI * .5
	world.add_child(giant)
	giant.set_physics_process(false)
	giant.set_giant_navigation_map(map)
	# The usual case starts with a clear goal across the RV. The blocked-goal
	# case starts at the shell centre; patrol must skip it and reach the next.
	giant.home_position = Vector3(-22 if blocked_goal else -12, 0, 0)
	var ready := await Wait.until(self, func() -> bool: return NavigationServer3D.map_get_iteration_id(map) > 0, 10000, true)
	check(ready, "Patrol fixture navigation synchronizes")
	await frames(3)
	var goal := giant.home_position + Vector3(22, 0, 0)
	var direct_path := NavigationServer3D.map_get_path(map, giant.global_position, goal, true)
	check(direct_path.size() == 2, "The terrain map routes straight across the unbaked RV")
	var shell_hit := giant.sweep_hand(giant.global_position + Vector3.UP, goal + Vector3.UP, .1)
	check(RVConnection.resolve(shell_hit.get("collider")) == rv, "The direct patrol path meets the real production RV shell")
	giant._sample("idle_play", 0.0)
	giant.set_physics_process(true)

func patrol_after_expiry(yaw_degrees: float, blocked_goal := false) -> void:
	await setup(yaw_degrees, blocked_goal)
	var label := "RV yaw %.0f%s" % [yaw_degrees, " blocked goal" if blocked_goal else ""]
	var blocked_point := giant.home_position + Vector3(22, 0, 0)
	var second_goal := giant.home_position + Vector3(cos(2.399963), 0, sin(2.399963)) * 22.0
	var first_goal := second_goal if blocked_goal else blocked_point
	var acquired := false
	var expired := false
	var expiry_tick := -1
	var expiry_position := Vector3.ZERO
	var seen_suppressed_ticks := 0
	var reacquisitions := 0
	var attack_ticks := 0
	var minimum_first_gap := INF
	var first_arrival := -1.0
	var second_arrival := -1.0
	var advances := 0
	var previous_index := giant._patrol_index
	var blocked_goal_skipped := false
	var entered_blocked_goal := false
	var stagnant_ticks := 0
	var longest_stagnant := 0
	var maximum_displacement := 0.0
	var previous_position := giant.global_position
	var start := Engine.get_physics_frames()
	var initial_health := rv.get_engine().health
	for tick in 4800:
		await frames()
		var displacement := giant.global_position.distance_to(previous_position)
		maximum_displacement = maxf(maximum_displacement, displacement)
		previous_position = giant.global_position
		if giant.target_vehicle == rv: acquired = true
		if giant.phase in [SlenderSpeaker.Phase.SMASH, SlenderSpeaker.Phase.GRAB]: attack_ticks += 1
		if not expired and acquired and giant._encounter_decision.get("reason") == "search_expired" and giant.phase == SlenderSpeaker.Phase.PATROL:
			expired = true
			expiry_tick = Engine.get_physics_frames()
			expiry_position = giant.global_position
			print("PATROL_EXPIRED ", label, " seconds=", float(expiry_tick - start) / 60.0, " position=", expiry_position)
		if expired:
			if blocked_goal:
				var blocked_gap := giant.global_position.slide(Vector3.UP).distance_to(blocked_point)
				if giant._patrol_index >= 1 and blocked_gap > 2.0: blocked_goal_skipped = true
				if blocked_gap < 2.0: entered_blocked_goal = true
			if giant.target_vehicle == rv or giant.phase != SlenderSpeaker.Phase.PATROL: reacquisitions += 1
			if giant._observation.get("vehicle") == rv and giant._observation.get("vehicle_visible", false): seen_suppressed_ticks += 1
			var gap := giant.global_position.slide(Vector3.UP).distance_to(first_goal)
			minimum_first_gap = minf(minimum_first_gap, gap)
			if gap < 2.0 and first_arrival < 0.0: first_arrival = float(Engine.get_physics_frames() - expiry_tick) / 60.0
			if giant.global_position.slide(Vector3.UP).distance_to(second_goal) < 2.0 and second_arrival < 0.0:
				second_arrival = float(Engine.get_physics_frames() - expiry_tick) / 60.0
			if giant._patrol_index != previous_index:
				advances += giant._patrol_index - previous_index
				previous_index = giant._patrol_index
			stagnant_ticks = stagnant_ticks + 1 if displacement < .002 and advances < 2 else 0
			longest_stagnant = maxi(longest_stagnant, stagnant_ticks)
			if advances >= 2: break
		if tick % 600 == 0:
			print("PATROL_TRACE ", label, " seconds=", float(Engine.get_physics_frames() - start) / 60.0,
				" position=", giant.global_position, " phase=", SlenderSpeaker.Phase.keys()[giant.phase],
				" index=", giant._patrol_index, " target=", giant.nav_agent.target_position,
				" reason=", giant._encounter_decision.get("reason", ""))
	check(acquired and expired, label + " acquires the real visible empty RV and naturally expires into PATROL")
	check(seen_suppressed_ticks >= 6 and reacquisitions == 0, label + " remains in PATROL while repeatedly seeing the suppressed parked RV")
	if blocked_goal:
		check(blocked_goal_skipped and not entered_blocked_goal, label + " skips the physically occupied first goal without entering the shell")
		check(first_arrival >= 0.0 and advances >= 2, label + " reaches the next clear patrol goal after skipping the occupied one")
	else:
		check(first_arrival >= 0.0 and second_arrival > first_arrival and advances >= 2, label + " walks around the physical RV and actually reaches two consecutive clear patrol goals")
	check(expired and giant.global_position.distance_to(expiry_position) > 8.0, label + " walks away from the expired encounter instead of remaining beside the shell")
	check(longest_stagnant < 90, label + " avoids prolonged stalled patrol motion at the vehicle corners")
	check(attack_ticks == 0 and is_equal_approx(rv.get_engine().health, initial_health), label + " never attacks the empty roofless RV")
	check(maximum_displacement < .3, label + " uses continuous swept locomotion throughout the measured encounter and patrol")
	print("PATROL_RESULT ", JSON.stringify({"rv_yaw": yaw_degrees, "blocked_goal": blocked_goal, "acquired": acquired, "expired": expired,
		"blocked_goal_skipped": blocked_goal_skipped, "entered_blocked_goal": entered_blocked_goal,
		"seen_suppressed_ticks": seen_suppressed_ticks, "reacquisitions": reacquisitions, "advances": advances,
		"first_arrival_seconds": first_arrival, "minimum_first_gap": minimum_first_gap,
		"second_arrival_seconds": second_arrival,
		"longest_stagnant_seconds": float(longest_stagnant) / 60.0, "maximum_step_m": maximum_displacement,
		"final_position": str(giant.global_position), "elapsed_seconds": float(Engine.get_physics_frames() - start) / 60.0}))
	giant.set_giant_navigation_map(RID())
	NavigationServer3D.free_rid(map)
	world.queue_free()
	await frames(3)

func run() -> void:
	await patrol_after_expiry(0.0)
	await patrol_after_expiry(90.0)
	await patrol_after_expiry(0.0, true)
	if failures.is_empty(): print("PASS: natural empty-RV encounter expiry resumes progressing patrol around an unbaked physical vehicle")
	quit(0 if failures.is_empty() else 1)
