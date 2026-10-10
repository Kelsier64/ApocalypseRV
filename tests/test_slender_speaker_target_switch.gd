extends SceneTree
## Fresh production actors, real sight and live physics/navigation. Opening a
## side panel supplies a walkable exit; targets and phases are never seeded.
const Wait := preload("res://tests/support/test_wait.gd")
const PLAYER := preload("res://player/player.tscn")
var failures: Array[String] = []
var stage: Node3D
var capture_review := false

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok and note not in failures:
		failures.append(note)
		push_error("FAIL: " + note)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func frames(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func tap(code: Key) -> void:
	key(code, true)
	await process_frame
	key(code, false)
	await process_frame

func fresh_stage() -> bool:
	await stage.select_mode(0)
	var ready := await Wait.until(self, func() -> bool: return stage.running, 60000, true)
	check(ready, "Production free play becomes ready for a fresh encounter")
	return ready

func fresh_ground_player(point: Vector3) -> CharacterBody3D:
	# Replacing the seated fixture with a new production Player prevents old
	# seat/support/grab metadata from standing in for a fresh ground spawn.
	var old: CharacterBody3D = stage.player
	if old.seated_in != null: old.seated_in.exit_seat(true)
	var player: CharacterBody3D = PLAYER.instantiate()
	player.position = point
	stage.actors.add_child(player)
	stage.player = player
	old.queue_free()
	await frames(30)
	check(player.is_on_floor() and player.seated_in == null and player.rv_support.rv == null,
		"Fresh production ground player has no seat or RV support ownership")
	return player

func observe_capture(label: String, player: CharacterBody3D) -> void:
	var giant: SlenderSpeaker = stage.giant
	var started := giant.global_position
	var grab_at := -1.0
	var capture_at := -1.0
	var lost_priority := false
	for tick in Engine.physics_ticks_per_second * 15:
		await frames(1)
		if giant.phase == SlenderSpeaker.Phase.GRAB and grab_at < 0.0:
			grab_at = float(tick + 1) / Engine.physics_ticks_per_second
		if not player.is_executing() and giant.can_see(player, player.execution_contact_position()) \
				and giant.phase in [SlenderSpeaker.Phase.CHASE, SlenderSpeaker.Phase.GRAB]:
			if giant.target_player != player or giant.target_vehicle != null: lost_priority = true
		if player.is_executing():
			capture_at = float(tick + 1) / Engine.physics_ticks_per_second
			await capture_frame(label, giant, player)
			break
	check(not lost_priority, label + " retains the visible ground survivor over the nearby RV throughout CHASE and GRAB")
	check(grab_at >= 0.0 and capture_at > grab_at and capture_at <= 15.0,
		label + " navigates into GRAB and captures through actual hand contact within 15 seconds")
	check(giant.global_position.distance_to(started) > 5.0, label + " reaches the survivor with actual CharacterBody movement")
	check(capture_at < 0.0 or (player.grab_control.captor == giant and giant._execution_player == player),
		label + " transfers execution ownership to the survivor reached by the live hands")
	print("TARGET_SWITCH ", label, " grab_seconds=", grab_at, " capture_seconds=", capture_at,
		" player=", player.global_position, " giant=", giant.global_position,
		" phase=", giant.phase, " blocked=", giant._grab_blocking_hits)
	stage.set_giant_enabled(false)
	giant._cancel_execution("test_complete")

func capture_frame(label: String, giant: SlenderSpeaker, player: CharacterBody3D) -> void:
	if not capture_review or DisplayServer.get_name() == "headless": return
	var center := giant.global_position.lerp(player.global_position, .5)
	stage.observer.global_position = center + Vector3(-18, 12, 14)
	stage.observer.look_at(center + Vector3.UP * 4.0)
	stage.observer_enabled = true
	stage.observer.make_current()
	# Hold the exact reached contact for rendering without advancing execution.
	var giant_was_processing := giant.is_physics_processing()
	var player_was_processing := player.is_physics_processing()
	var stage_was_processing := stage.is_physics_processing()
	giant.set_physics_process(false)
	player.set_physics_process(false)
	stage.set_physics_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://.godot/slender-target-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory + "/" + label.to_lower() + ".png"
	var error := root.get_texture().get_image().save_png(path)
	check(error == OK, label + " saves the actual native capture frame")
	print("TARGET_REVIEW image=", ProjectSettings.globalize_path(path))
	giant.set_physics_process(giant_was_processing)
	player.set_physics_process(player_was_processing)
	stage.set_physics_process(stage_was_processing)

func check_seat_exit() -> void:
	if not await fresh_stage(): return
	var player: CharacterBody3D = stage.player
	var giant: SlenderSpeaker = stage.giant
	var rv: Chassis = stage.rv
	var seat: Node3D = rv.get_node("DriverSeat")
	stage.set_giant_enabled(true)
	await frames(60)
	check(giant.target_vehicle == rv and not giant._parked_plan.is_empty(),
		"Live sight first acquires the parked RV and builds an approach plan")
	# Freeze sampling during the walk without the F2 toggle's intentional AI
	# reset, so the old parked association must be cleared by the controller.
	giant.set_physics_process(false)
	await tap(KEY_E)
	await frames(3)
	check(player.seated_in == null and seat.current_driver == null and not rv.is_player_driving,
		"Normal E exits the production driver seat into the aisle")
	var local_exit := rv.to_local(player.global_position)
	check(absf(local_exit.x) < 1.6 and local_exit.y > .3 and absf(local_exit.z) < 6.0,
		"Normal seat exit keeps the standing survivor inside the real RV")
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	var opening := slots.panel("left_0")
	opening.take_damage(opening.current_health)
	await frames(3)
	player.rotation.y = rv.rotation.y
	# Walk around the occupied seat body and through the real broken panel.
	key(KEY_S, true)
	await frames(15)
	key(KEY_S, false)
	key(KEY_A, true)
	await frames(72)
	key(KEY_A, false)
	key(KEY_W, true)
	await frames(132)
	key(KEY_W, false)
	await frames(30)
	print("SEAT_EXIT_WALK exit=", local_exit, " ground=", rv.to_local(player.global_position))
	check(player.is_on_floor() and player.global_position.y < .2 and player.rv_support.rv == null,
		"Sustained normal movement walks the survivor out of the RV and onto the ground")
	check(giant.can_see(player, player.execution_contact_position()), "Exited ground survivor is physically visible to the speaker")
	var visible_rv := giant._visible_vehicle_point(rv)
	check(visible_rv != Vector3.INF and giant.global_position.distance_to(visible_rv) < giant.global_position.distance_to(player.execution_contact_position()),
		"Exited survivor competes with a closer physically visible RV")
	check(giant.target_vehicle == rv and not giant._parked_plan.is_empty(),
		"Walking setup preserves the previously acquired parked RV plan until sight refresh")
	giant.set_physics_process(true)
	await frames(12)
	check(giant.target_player == player and giant.target_vehicle == null and giant._parked_plan.is_empty(),
		"Fresh sight after exit discards the old parked plan and pursues the visible ground player")
	await observe_capture("SEAT_EXIT_GROUND", player)

func check_fresh_ground() -> void:
	if not await fresh_stage(): return
	var rv: Chassis = stage.rv
	var point := rv.to_global(Vector3(-4.8, 0, -15))
	point.y = .05
	var player := await fresh_ground_player(point)
	var giant: SlenderSpeaker = stage.giant
	check(giant.target_player == null and giant.target_vehicle == null, "Fresh ground encounter starts without a seeded target")
	check(giant.can_see(player, player.execution_contact_position()), "Fresh ground survivor is visible beside the front of the production RV")
	var visible_rv := giant._visible_vehicle_point(rv)
	check(visible_rv != Vector3.INF and giant.global_position.distance_to(visible_rv) < giant.global_position.distance_to(player.execution_contact_position()),
		"Fresh ground survivor competes with a closer physically visible RV")
	stage.set_giant_enabled(true)
	await observe_capture("FRESH_GROUND", player)

func check_opposite_ground(side_distance: float) -> void:
	if not await fresh_stage(): return
	if side_distance < 3.0:
		# Expose the nearby ground survivor above the chassis while retaining
		# its physical body as a navigation obstacle between the two actors.
		for part in get_nodes_in_group(Groups.MONSTER_DAMAGEABLE):
			if part is RVStructurePanel and part.get_connected_rv() == stage.rv:
				part.take_damage(part.current_health)
	var point: Vector3 = stage.rv.to_global(Vector3(side_distance, 0, 0))
	point.y = .05
	var player := await fresh_ground_player(point)
	var giant: SlenderSpeaker = stage.giant
	stage.set_giant_enabled(true)
	var start := Engine.get_physics_frames()
	var still_ticks := 0
	var longest_still := 0
	var held := false
	var previous_tick := Engine.get_physics_frames()
	var releases: Array[String] = []
	player.grab_control.released.connect(func(reason: String): releases.append(reason))
	while Engine.get_physics_frames() - start < 1500:
		await frames(1)
		var elapsed_ticks := Engine.get_physics_frames() - previous_tick
		previous_tick = Engine.get_physics_frames()
		if giant.phase == SlenderSpeaker.Phase.CHASE and giant.can_see_player(player) \
			and giant.velocity.slide(Vector3.UP).length() < .05 and giant._facing_dot(player.execution_contact_position()) > .99:
			still_ticks += elapsed_ticks
		else: still_ticks = 0
		longest_still = maxi(longest_still, still_ticks)
		if giant.phase == SlenderSpeaker.Phase.HOLD and player.is_executing():
			held = true
			break
		if longest_still > 180: break
	check(longest_still <= 180, "Visible survivor across the RV cannot leave the giant staring into the opposite wall for three seconds")
	check(held and releases.is_empty(), "Ground pursuit routes around the live RV and completes the first physical grab/lift")
	print("OPPOSITE_GROUND side=", side_distance, " held=", held, " seconds=", float(Engine.get_physics_frames() - start) / 60.0,
		" longest_stare_seconds=", float(longest_still) / 60.0, " releases=", releases)
	stage.set_giant_enabled(false)
	giant._cancel_execution("test_complete")

func check_obscured_sight() -> void:
	if not await fresh_stage(): return
	var rv: Chassis = stage.rv
	var point := rv.to_global(Vector3(-4.8, 0, -15))
	point.y = .05
	var player := await fresh_ground_player(point)
	var giant: SlenderSpeaker = stage.giant
	# Enabling the actor registers its body with physics; manual stepping
	# below controls this sight fixture without disabling its collision space.
	stage.set_giant_enabled(true)
	giant.set_physics_process(false)
	await frames(3)
	giant._refresh_sight()
	giant._update_encounter(1.0 / 60.0)
	check(giant.target_player == player and giant.target_vehicle == null, "Fresh real sight prefers a visible survivor before the nearer vehicle")
	var player_seen := giant.last_seen_position
	var chassis_health: float = rv.get_engine().health
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.5, 18, 3.5)
	collision.shape = shape
	wall.add_child(collision)
	stage.add_child(wall)
	wall.global_position = giant.global_position.lerp(player.global_position, .7) + Vector3.UP * 9.0
	await frames(3)
	check(not giant.can_see(player, player.execution_contact_position()), "Real wall blocks the survivor's sight ray")
	giant._refresh_sight()
	giant._update_encounter(1.0 / 60.0)
	check(giant._observation.get("player") == null and giant._observation.get("vehicle") == rv,
		"Wall hides the survivor while the competing RV remains physically visible")
	check(giant.target_player == player and giant.target_vehicle == null
		and giant._encounter_decision.get("intent") == "search",
		"Wall-obscured ground survivor remains the encounter and searches its observed position")
	player.global_position += (player.global_position - giant.global_position).slide(Vector3.UP).normalized() * 8.0
	await frames(3)
	check(not giant.can_see(player, player.execution_contact_position()), "Moving survivor remains behind the real wall")
	giant._refresh_sight()
	giant._update_encounter(1.0 / 60.0)
	var obscured_pose := giant.global_transform
	for tick in int(floor((giant.settings.search_seconds - .1) * Engine.physics_ticks_per_second)):
		await frames(1)
		# Keep this sight fixture behind the same real wall; separate live
		# navigation cases above verify movement and physical capture.
		giant.global_transform = obscured_pose
		giant.velocity = Vector3.ZERO
		giant._refresh_sight()
		giant._physics_process(1.0 / Engine.physics_ticks_per_second)
		check(giant.last_seen_position.distance_to(player_seen) < .1,
			"Persistent search freezes the last observed survivor position through its eight-second memory window")
		check(giant.target_player == player and giant.target_vehicle == null
			and giant._encounter_decision.get("intent") == "search",
			"Visible competing RV cannot replace the hidden ground survivor during persistent search")
	check(rv.get_engine().health == chassis_health and slots.panel("roof_0").can_operate()
		and slots.panel("roof_1").can_operate() and slots.panel("roof_2").can_operate()
		and not player.is_grabbed(), "Persistent ground search cannot authorize chassis assault, roof removal or hidden survivor capture")
	wall.queue_free()
	await frames(2)
	player.global_position = giant.global_position + Vector3(-8, 0, 8)
	player.global_position.y = .05
	await frames(3)
	check(not giant.can_see(player, player.execution_contact_position()), "Survivor behind the actual speaker cone is not visible")
	giant._refresh_sight()
	giant._update_encounter(1.0 / 60.0)
	check(giant._observation.get("player") == null and giant.target_player == player
		and giant.target_vehicle == null and giant.last_seen_position.distance_to(player_seen) < .1,
		"Speaker cone loss keeps the same encounter without reading the rear survivor's live position")

func check_grab_target_lock() -> void:
	if not await fresh_stage(): return
	var point: Vector3 = stage.rv.to_global(Vector3(-4.8, 0, -15))
	point.y = .05
	var player := await fresh_ground_player(point)
	var giant: SlenderSpeaker = stage.giant
	stage.set_giant_enabled(true)
	var reached_grab := false
	for tick in Engine.physics_ticks_per_second * 15:
		await frames(1)
		if giant.phase == SlenderSpeaker.Phase.GRAB:
			reached_grab = true
			break
	check(reached_grab, "Fresh sight and navigation enter a real grab before the competing survivor arrives")
	if not reached_grab: return
	giant.set_physics_process(false)
	var other: CharacterBody3D = PLAYER.instantiate()
	# Head tracking moves the eye socket independently from the torso. Place
	# the newcomer ahead of that real socket rather than behind the bent head.
	var eye: Transform3D = giant.visual.bone_world("socket_focus")
	other.position = eye.origin.slide(Vector3.UP) + eye.basis.y.slide(Vector3.UP).normalized() * 1.0 + giant.global_basis.x * .35
	other.position.y = .05
	stage.actors.add_child(other)
	await frames(30)
	check(giant.can_see(other, other.execution_contact_position()) \
			and giant.global_position.distance_to(other.execution_contact_position()) < giant.global_position.distance_to(player.execution_contact_position()),
		"Another actual visible production survivor is closer during the original GRAB")
	check(giant.phase == SlenderSpeaker.Phase.GRAB and giant.target_player == player,
		"Newcomer setup preserves the original committed GRAB and survivor")
	giant.set_physics_process(true)
	var replaced := false
	var recovered := false
	for tick in Engine.physics_ticks_per_second * 2:
		await frames(1)
		if giant.phase == SlenderSpeaker.Phase.GRAB and giant.target_player != player: replaced = true
		if giant.phase == SlenderSpeaker.Phase.RECOVER:
			recovered = true
			break
		if player.is_executing() or other.is_executing(): break
	check(not replaced and not other.is_executing(),
		"An authored GRAB retains its original survivor without giving the closer newcomer stale hand sweeps")
	check(player.is_executing() or recovered,
		"Committed GRAB finishes by actual original-player contact or safe recovery")
	print("GRAB_TARGET_LOCK original_capture=", player.is_executing(), " other_capture=", other.is_executing(),
		" recovered=", recovered, " phase=", giant.phase)
	stage.set_giant_enabled(false)
	giant._cancel_execution("test_complete")
	other.queue_free()
	await frames(2)

func run() -> void:
	capture_review = "--capture-review" in OS.get_cmdline_user_args()
	stage = load("res://tests/slender_speaker_playground.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	var ready := await Wait.until(self, func() -> bool: return stage.running, 60000, true)
	check(ready, "Production playground prepares navigation and real actors")
	if ready:
		await check_seat_exit()
		await check_fresh_ground()
		await check_opposite_ground(4.0)
		await check_opposite_ground(2.8)
		await check_obscured_sight()
		await check_grab_target_lock()
	for code in [KEY_W, KEY_A, KEY_S]: key(code, false)
	stage.queue_free()
	await frames(2)
	if failures.is_empty(): print("PASS: Slender switches from the RV to exited and fresh ground survivors using actual sight, navigation and hand contact")
	quit(0 if failures.is_empty() else 1)
