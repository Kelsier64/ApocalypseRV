extends SceneTree
## Autonomous sight -> chase -> physical hand capture -> HOLD on flat ground.
## Both actors keep their production scripts, models, navigation and physics.
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const PLAYER := preload("res://player/player.tscn")
const WAIT := preload("res://tests/support/test_wait.gd")
const START_GAP := 24.0
const CHASE_SECONDS := 30.0
var failures: Array[String] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func frames(count := 1) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func release_input() -> void:
	Input.action_release("move_forward")
	Input.action_release("sprint")

func chase(sprinting: bool) -> void:
	var label := "SPRINT" if sprinting else "NORMAL"
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(160, .2, 1200)
	floor_collision.shape = floor_shape
	floor_collision.position.y = -.1
	floor_body.add_child(floor_collision)
	world.add_child(floor_body)
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-80, 0, -600), Vector3(-80, 0, 600), Vector3(80, 0, 600), Vector3(80, 0, -600)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)
	region.set_navigation_map(map)
	var player: CharacterBody3D = PLAYER.instantiate()
	player.position = Vector3(0, .1, -START_GAP)
	world.add_child(player)
	var giant: SlenderSpeaker = GIANT.instantiate()
	giant.position = Vector3(0, .02, 0)
	world.add_child(giant)
	giant.set_physics_process(false)
	giant.set_giant_navigation_map(map)
	var nav_ready := await WAIT.until(self, func() -> bool:
		return NavigationServer3D.map_get_iteration_id(map) > 0, 10000, true)
	check(nav_ready, label + " flat navigation map publishes")
	await frames(30)
	check(player.is_on_floor(), label + " production Player settles on the physical flat floor")
	check(giant.visual.available, label + " production giant rig and hand sockets load")
	check(giant.phase == SlenderSpeaker.Phase.PATROL and giant.target_player == null,
		label + " begins without a seeded encounter or forced phase")
	var requested_speed: float = player.SPRINT_SPEED if sprinting else player.SPEED
	var proof := {"starts": 0, "swept_player": false, "input_held": false,
		"runner_speed": 0.0, "position": Vector3.ZERO, "sweep": {}, "phase": -1}
	# Observe before begin_execution clears the actual runner velocity. The
	# winning hand probe must independently hit the real production capsule.
	player.grab_started.connect(func() -> void:
		proof.starts += 1
		proof.position = player.global_position
		proof.runner_speed = player.velocity.slide(Vector3.UP).length()
		proof.input_held = Input.is_action_pressed("move_forward") and (not sprinting or Input.is_action_pressed("sprint"))
		proof.phase = giant.phase
		var contact: Dictionary = giant._grab_capture_sweep
		proof.sweep = contact.duplicate()
		if contact.is_empty(): return
		var hit := giant.sweep_hand(contact.from, contact.to, float(contact.radius))
		proof.swept_player = hit.get("collider") == player
	)
	var releases: Array[String] = []
	player.grab_control.released.connect(func(reason: String): releases.append(reason))
	Input.action_press("move_forward")
	if sprinting: Input.action_press("sprint")
	giant.set_physics_process(true)
	var start := player.global_position
	var previous := start
	var acquired := false
	var chase_ticks := 0
	var runner_ticks := 0
	var slow_ticks := 0
	var grab_attempts := 0
	var previous_phase := giant.phase
	var minimum_gap := START_GAP
	var captured := false
	var hold_reached := false
	var capture_tick := -1
	var maximum_lift := 0.0
	var hz := Engine.physics_ticks_per_second
	var deadline := Time.get_ticks_msec() + 90000
	for tick in int(CHASE_SECONDS * hz):
		# Normal stamina permits only five seconds of sprint. Refill stamina
		# alone to regress sustained 8 m/s pursuit; never move either actor,
		# change speed constants, seed targets, advance phases or force capture.
		if sprinting:
			player.current_stamina = player.MAX_STAMINA
		await frames()
		acquired = acquired or giant.target_player == player
		if giant.phase == SlenderSpeaker.Phase.CHASE: chase_ticks += 1
		if giant.phase == SlenderSpeaker.Phase.GRAB and previous_phase != giant.phase: grab_attempts += 1
		minimum_gap = minf(minimum_gap, giant.global_position.slide(Vector3.UP).distance_to(player.global_position.slide(Vector3.UP)))
		if not captured and not player.is_executing() and not player.is_player_dead and tick > 3:
			runner_ticks += 1
			var forward_step := previous.z - player.global_position.z
			if player.velocity.slide(Vector3.UP).length() < requested_speed - .05 or forward_step < requested_speed / hz * .9:
				slow_ticks += 1
		if player.is_executing():
			if not captured:
				captured = true
				capture_tick = tick
			maximum_lift = maxf(maximum_lift, player.global_position.y - float(proof.position.y))
			if giant.phase == SlenderSpeaker.Phase.HOLD:
				hold_reached = true
				break
		if tick % hz == 0 or giant.phase != previous_phase:
			print("GROUND_CHASE_TRACE ", label, " tick=", tick, " phase=", SlenderSpeaker.Phase.keys()[giant.phase],
				" runner=", player.global_position, " giant=", giant.global_position,
				" speed=", player.velocity.slide(Vector3.UP).length(), " intent=", giant._encounter_decision.get("intent"),
				" grab_blocked=", giant._grab_blocked)
		previous = player.global_position
		previous_phase = giant.phase
		if player.is_player_dead or (captured and not player.is_executing()) or Time.get_ticks_msec() > deadline: break
	check(acquired and chase_ticks > hz, label + " real perception autonomously acquires and chases the runner")
	check(runner_ticks > hz and slow_ticks == 0, label + " runner continuously moves straight at %.1f m/s before capture" % requested_speed)
	check(captured and proof.starts == 1 and proof.phase == SlenderSpeaker.Phase.GRAB,
		label + " autonomous grab acquires execution ownership exactly once")
	check(proof.swept_player and not proof.sweep.is_empty() and giant._grab_touched and not giant._grab_hands_touched.is_empty(),
		label + " acquisition comes from an actual palm or finger sweep hitting the player capsule")
	check(proof.input_held and absf(float(proof.runner_speed) - requested_speed) < .05,
		label + " player is still trying to run at full speed when the real hand captures them")
	check(hold_reached and player.is_executing() and player.grab_control.captor == giant and maximum_lift > 2.0 and releases.is_empty(),
		label + " captured player completes the full swept lift to HOLD without losing ownership")
	check(Input.is_action_pressed("move_forward") and (not sprinting or Input.is_action_pressed("sprint")) and not player.is_player_dead,
		label + " input remains held through HOLD and the runner stays alive")
	var capture_position: Vector3 = proof.position
	var run_distance := capture_position.slide(Vector3.UP).distance_to(start.slide(Vector3.UP)) if captured else previous.distance_to(start)
	check(run_distance > START_GAP and absf(capture_position.x - start.x) < .05,
		label + " capture follows a substantial straight run rather than initial proximity or a blocked runner")
	print("GROUND_CHASE_RESULT ", label, " requested_speed=", requested_speed, " capture_seconds=", float(capture_tick) / hz,
		" run_distance=", run_distance, " minimum_gap=", minimum_gap, " grab_attempts=", grab_attempts,
		" runner_ticks=", runner_ticks, " slow_ticks=", slow_ticks, " lift=", maximum_lift, " hold=", hold_reached,
		" winning_sweep=", proof.sweep, " releases=", releases)
	release_input()
	world.free()
	NavigationServer3D.free_rid(map)
	await frames(3)

func run() -> void:
	release_input()
	await chase(false)
	await chase(true)
	release_input()
	if failures.is_empty(): print("PASS: autonomous flat-ground capture and full lift of continuous production Player normal/sprint runners")
	quit(0 if failures.is_empty() else 1)
