extends SceneTree
## Production rig, navigation and swept motion through sharp parked turns.
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const PLAYER := preload("res://player/player.tscn")
var failures: Array[String] = []
var world: Node3D
var giant: SlenderSpeaker
var player: CharacterBody3D
var map: RID

func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)
func frames(count := 1) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func check_turn(degrees: float) -> void:
	giant.global_position = Vector3.ZERO
	giant.reset_after_restore()
	giant.velocity = Vector3.ZERO
	giant.rotation.y = 0.0
	player.global_position = Vector3(0, .05, -12)
	giant._sample("idle_play", 0.0)
	await frames(3)
	giant._refresh_sight()
	giant._update_encounter(1.0 / 60.0)
	check(giant.target_player == player and giant._encounter_decision.get("player_visible", false),
		"Sharp-turn fixture acquires a real visible survivor before preserving its approach")
	player.global_position = Vector3(1000, 0, 1000)
	giant.rotation.y = deg_to_rad(degrees)
	giant._sample("idle_play", 0.0)
	await frames(3)
	giant._refresh_sight()
	giant._update_encounter(1.0 / 60.0)
	giant._set_phase(SlenderSpeaker.Phase.SEARCH)
	check(giant.target_player == player and giant._encounter_decision.get("intent") == "search",
		"Sharp-turn fixture keeps owner identity after actual perception loss")
	giant._sense_remaining = 100.0
	giant._parked_approach_remaining = giant.settings.search_seconds
	giant._parked_facing_waypoint = Vector3.INF
	var point := Vector3(0, 0, -10)
	var plan := {"navigation_point": point, "standoff_point": point, "surface_point": Vector3(0, 0, -12)}
	giant._parked_approach_memory = plan.duplicate(true)
	var start := giant.global_position
	var early_distance := 0.0
	var stationary_ticks := 0
	var longest_stationary := 0
	var lateral_ticks := 0
	var longest_lateral := 0
	var travel := 0.0
	var arrival := -1.0
	var authored_turn_ticks := 0
	for tick in 720:
		await frames()
		var before := giant.global_position
		giant._physics_process(1.0 / 60.0)
		var movement := (giant.global_position - before).slide(Vector3.UP) * 60.0
		var gap := giant.global_position.slide(Vector3.UP).distance_to(point)
		travel += movement.length() / 60.0
		if tick == 29: early_distance = travel
		stationary_ticks = stationary_ticks + 1 if gap > 1.0 and movement.length() < .12 else 0
		longest_stationary = maxi(longest_stationary, stationary_ticks)
		lateral_ticks = lateral_ticks + 1 if movement.length() >= 1.2 and absf(movement.dot(giant.global_basis.x)) > .8 else 0
		longest_lateral = maxi(longest_lateral, lateral_ticks)
		if giant._animation_clip in ["turn_left", "turn_right"]: authored_turn_ticks += 1
		if tick % 30 == 0:
			print("PARKED_TURN_TRACE degrees=", degrees, " seconds=", float(tick) / 60.0,
				" position=", giant.global_position, " yaw=", giant.rotation_degrees.y,
				" speed=", movement.length(), " gap=", gap,
				" clip=", giant._animation_clip)
		if giant._parked_facing_waypoint != Vector3.INF:
			arrival = float(tick) / 60.0
			break
	print("PARKED_TURN degrees=", degrees, " early_distance=", early_distance,
		" longest_stationary_seconds=", float(longest_stationary) / 60.0,
		" longest_lateral_seconds=", float(longest_lateral) / 60.0, " arrival_seconds=", arrival,
		" authored_turn_ticks=", authored_turn_ticks,
		" travel=", travel, " displacement=", giant.global_position.distance_to(start))
	check(arrival >= 0.0, "Parked turn %.0f degrees reaches the centimetre stance without orbiting" % degrees)
	check(longest_lateral < 30, "Parked turn %.0f degrees never sustains sideways movement" % degrees)
	if degrees == 90.0:
		check(early_distance > .15, "Quarter turn keeps walking through the first half second")
		check(longest_stationary < 10, "Quarter turn avoids a stationary alignment gate")
	else:
		check(authored_turn_ticks > 10, "A behind-body route uses the authored stepping turn until forward travel is possible")

func check_running_turn(sign_value: float, hz: int) -> void:
	Engine.physics_ticks_per_second = hz
	giant.reset_after_restore()
	giant.global_position = Vector3(-30, .02, 30)
	giant.rotation.y = 0.0
	giant.velocity = Vector3.FORWARD * giant.settings.chase_speed
	giant._set_phase(SlenderSpeaker.Phase.CHASE)
	var delta := 1.0 / float(hz)
	var maximum_lateral := 0.0
	var maximum_angle := 0.0
	var travel := 0.0
	var start := giant.global_position
	var maximum_distance := 0.0
	for tick in hz * 4:
		await physics_frame
		var point := giant.global_position + Vector3.FORWARD.rotated(Vector3.UP, giant.rotation.y + sign_value * deg_to_rad(15.0)) * 25.0
		var desired := giant._navigate(point, giant.settings.chase_speed, delta)
		var before := giant.global_position
		giant._move_swept(desired, delta)
		var movement := (giant.global_position - before).slide(Vector3.UP) / delta
		travel += movement.length() * delta
		maximum_distance = maxf(maximum_distance, giant.global_position.distance_to(start))
		maximum_lateral = maxf(maximum_lateral, absf(movement.dot(giant.global_basis.x)))
		if movement.length() > .5:
			maximum_angle = maxf(maximum_angle, absf(rad_to_deg(movement.signed_angle_to(-giant.global_basis.z, Vector3.UP))))
	check(travel > 15.0 and maximum_distance > 5.0, "Running turn physically advances along its curved route at %d Hz" % hz)
	check(maximum_lateral < .02 and maximum_angle < .5, "Running turn cannot slide sideways while its body steers at %d Hz" % hz)
	print("RUNNING_TURN sign=", sign_value, " hz=", hz, " travel=", travel, " maximum_lateral=", maximum_lateral, " maximum_angle=", maximum_angle)
	# Opposite travel brakes to rest before the authored backwards retreat.
	var forward := -giant.global_basis.z.normalized()
	giant.velocity = forward * 4.0
	await physics_frame
	giant._move_swept(-forward * 3.0, delta)
	check(giant.velocity.dot(forward) > 0.0 and is_equal_approx(giant.velocity.slide(Vector3.UP).length(), 4.0 - giant.settings.braking * delta), "Reverse request brakes existing forward motion before changing direction at %d Hz" % hz)
	for tick in hz:
		await physics_frame
		giant._move_swept(-forward * 3.0, delta)
	check(giant.velocity.dot(forward) < 0.0 and absf(giant.velocity.dot(giant.global_basis.x)) < .02, "Braked actor can resume an aligned backwards retreat at %d Hz" % hz)
	giant.velocity = forward * .01
	await physics_frame
	giant._move_swept(-forward, delta)
	check(giant.velocity.slide(Vector3.UP).length() < .001, "Reversal finishes braking at rest rather than accelerating backwards at the braking rate")
	await physics_frame
	giant._move_swept(-forward, delta)
	check(is_equal_approx(-giant.velocity.dot(forward), giant.settings.acceleration * delta), "Reverse motion accelerates at the normal rate after braking to rest")
	Engine.physics_ticks_per_second = 60

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
	giant = GIANT.instantiate()
	world.add_child(giant)
	giant.set_physics_process(false)
	player = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	giant.set_giant_navigation_map(map)
	await frames(3)
	NavigationServer3D.map_force_update(map)
	await check_turn(90.0)
	await check_turn(135.0)
	for sign_value in [-1.0, 1.0]:
		for hz in [30, 60, 120]: await check_running_turn(sign_value, hz)
	giant.set_giant_navigation_map(RID())
	NavigationServer3D.free_rid(map)
	world.queue_free()
	await frames(3)
	if failures.is_empty(): print("PASS: parked and running giant turns preserve forward travel without lateral drift and brake before reversing")
	quit(0 if failures.is_empty() else 1)
