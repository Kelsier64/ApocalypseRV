extends SceneTree
## One survivor and live mode-0 RV: normal aisle evasion, real seat entry,
## wheel acceleration and service braking. Only the starting cabin layout is
## placed; no actor transforms, velocities, AI phases or targets are then seeded.
const Wait := preload("res://tests/support/test_wait.gd")
var stage: Node3D
var giant: SlenderSpeaker
var player: CharacterBody3D
var rv: Chassis
var failures: Array[String] = []
var replay_step := "approach"
var start_tick := 0
var evasion_tick := -1
var evasion_start := Vector3.ZERO
var evasion_distance := 0.0
var first_miss_tick := -1
var retry_tick := -1
var pursuit_tick := -1
var brake_tick := -1
var cabin_tick := -1
var attempts := 0
var misses := 0
var retained_retry_ticks := 0
var retry_target_losses := 0
var cabin_assault_ticks := 0
var cabin_chassis_hits := 0
var pursuit_action_ticks := 0
var pursuit_hits := 0
var locked_identity_losses := 0
var captures := 0
var handbrake_ticks := 0
var encounter_target_loss_ticks := 0
var unexpected_captures := 0
var final_capture_tick := -1
var final_hold_tick := -1
var final_capture_height := 0.0
var final_execution_releases: Array[String] = []
var maximum_speed := 0.0
var drive_distance := 0.0
var drive_start := Vector3.ZERO
var initial_health := 0.0
var physics_damage := 0.0
var cabin_unexplained_damage := 0.0
var previous_health := 0.0
var previous_physics_damage := 0.0
var previous_phase := -1
var previous_mode := "none"
var previous_action := ""
var high_speed_ticks := 0
var low_speed_ticks := 0
var steering_ticks := 0
var mode_counts: Dictionary = {}
var reason_counts: Dictionary = {}
var events: Array[Dictionary] = []

func _init() -> void: run.call_deferred()

func check(ok: bool, note: String) -> void:
	if not ok and note not in failures:
		failures.append(note)
		push_error("FAIL: " + note)

func frame() -> void:
	# physics_frame resumes before the next physics callbacks. Read the fully
	# completed previous step and submit input for the upcoming step. Waiting
	# for process_frame here would skip physics steps when capture is expensive.
	await physics_frame

func movement(forward := 0.0, back := 0.0, left := 0.0, right := 0.0) -> void:
	var strengths := {"move_forward": forward, "move_back": back, "move_left": left, "move_right": right}
	for action in strengths:
		if float(strengths[action]) > 0.0: Input.action_press(action, strengths[action])
		else: Input.action_release(action)

func mark(kind: String) -> void:
	var event := {"event": kind, "time": float(Engine.get_physics_frames() - start_tick) / 60.0,
		"step": replay_step, "phase": SlenderSpeaker.Phase.keys()[giant.phase],
		"speed_kmh": rv.road_speed() * 3.6, "handbrake": rv.handbrake,
		"player_local": str(rv.to_local(player.global_position)),
		"giant_local": str(rv.to_local(giant.global_position)), "debug": giant.encounter_debug_text()}
	events.append(event)
	print("ENCOUNTER_DRIVE_EVENT ", JSON.stringify(event))

func action_identity(context: Dictionary, decision: Dictionary) -> String:
	if context.is_empty(): return ""
	var survivor: Node = context.get("player")
	var vehicle: Node = context.get("vehicle")
	return "%s/%d/%d/%s/%s/%d" % [context.get("kind", ""),
		survivor.get_instance_id() if is_instance_valid(survivor) else 0,
		vehicle.get_instance_id() if is_instance_valid(vehicle) else 0,
		str(context.get("point", Vector3.ZERO)), decision.get("mode", "none"), decision.get("generation", 0)]

func observe() -> void:
	var decision: Dictionary = giant._encounter_decision
	var action: Dictionary = giant._action_context
	var encounter_mode := String(decision.get("mode", "none"))
	var reason := String(decision.get("reason", ""))
	mode_counts[encounter_mode] = int(mode_counts.get(encounter_mode, 0)) + 1
	reason_counts[reason] = int(reason_counts.get(reason, 0)) + 1
	maximum_speed = maxf(maximum_speed, rv.road_speed())
	if rv.handbrake: handbrake_ticks += 1
	if first_miss_tick >= 0 and (decision.get("player") != player or decision.get("vehicle") != rv):
		encounter_target_loss_ticks += 1
	var high := rv.road_speed() > giant.settings.pursuit_enter_speed
	var low := rv.road_speed() < giant.settings.cabin_enter_speed
	high_speed_ticks = high_speed_ticks + 1 if high else 0
	low_speed_ticks = low_speed_ticks + 1 if low else 0
	if encounter_mode == "cabin" and action.get("kind", "") == "vehicle_assault": cabin_assault_ticks += 1
	if encounter_mode == "pursuit" and action.get("kind", "") == "vehicle_assault": pursuit_action_ticks += 1
	var identity := action_identity(action, decision)
	var was_locked := not previous_action.is_empty()
	if not identity.is_empty() and not previous_action.is_empty() and identity != previous_action:
		locked_identity_losses += 1
	previous_action = identity
	var health: float = rv.get_engine().health
	var unexplained := maxf(0.0, previous_health - health - (physics_damage - previous_physics_damage))
	if encounter_mode == "cabin": cabin_unexplained_damage += unexplained
	previous_health = health
	previous_physics_damage = physics_damage
	if first_miss_tick >= 0 and retry_tick < 0:
		retained_retry_ticks += 1
		if encounter_mode != "cabin" or decision.get("player") != player or decision.get("vehicle") != rv:
			retry_target_losses += 1
	if giant.phase == SlenderSpeaker.Phase.GRAB and previous_phase != giant.phase:
		attempts += 1
		if first_miss_tick >= 0 and retry_tick < 0:
			retry_tick = Engine.get_physics_frames()
			replay_step = "drive"
			mark("autonomous_retry")
			# Use the production interaction and seat-owned relocation, as the
			# existing free-play input test does. The second reach remains live.
			movement()
			rv.get_node("DriverSeat").interact_hold(player)
			check(player.seated_in == rv.get_node("DriverSeat"), "Evading survivor enters the real driver seat before accelerating")
			rv.set_handbrake(false)
			drive_start = rv.global_position
			mark("seat_entry_and_release_brake")
	if previous_phase == SlenderSpeaker.Phase.GRAB and giant.phase == SlenderSpeaker.Phase.RECOVER and not player.is_executing():
		misses += 1
		if first_miss_tick < 0:
			first_miss_tick = Engine.get_physics_frames()
			replay_step = "retry"
			movement()
		mark("physical_grab_miss")
	if player.is_executing() and final_capture_tick < 0:
		captures += 1
		if brake_tick >= 0 and encounter_mode == "cabin":
			final_capture_tick = Engine.get_physics_frames()
			final_capture_height = player.global_position.y
			mark("final_cabin_capture")
		else: unexpected_captures += 1
	if final_capture_tick >= 0 and giant.phase == SlenderSpeaker.Phase.HOLD and player.is_executing():
		final_hold_tick = Engine.get_physics_frames()
	if encounter_mode != previous_mode:
		if previous_mode == "cabin" and encounter_mode == "pursuit":
			check(high_speed_ticks >= 45, "Cabin becomes pursuit only after sustained actual wheel speed above 10 km/h")
			check(not was_locked, "Speed hysteresis does not change the mode during a committed action")
			if pursuit_tick < 0: pursuit_tick = Engine.get_physics_frames()
		elif previous_mode == "pursuit" and encounter_mode == "cabin":
			check(low_speed_ticks >= 30, "Pursuit returns to cabin only after sustained actual wheel speed below 6 km/h")
			check(not was_locked, "Braking preserves any committed attack until recovery completes")
			if brake_tick >= 0: cabin_tick = Engine.get_physics_frames()
		mark("mode_" + encounter_mode)
	if giant.phase != previous_phase: mark("phase_" + SlenderSpeaker.Phase.keys()[giant.phase])
	previous_mode = encounter_mode
	previous_phase = giant.phase

func run() -> void:
	stage = load("res://tests/slender_speaker_playground.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	var ready := await Wait.until(self, func() -> bool: return stage.running, 60000, true)
	check(ready and stage.mode == 0, "Actual free-play playground becomes ready")
	if not ready:
		await finish()
		return
	giant = stage.giant
	player = stage.player
	rv = stage.rv
	check(not rv.freeze and not rv.allow_test_controls and rv.control_override.is_empty(), "Replay uses normal controls and live wheel suspension")
	player.seated_in.exit_seat(true)
	player.global_position = rv.to_global(Vector3(0, .3, 2))
	player.rotation.y = rv.rotation.y
	for roof_id in ["roof_0", "roof_1", "roof_2"]:
		var roof: RVStructurePanel = rv.get_node("StructureSlots").panel(roof_id)
		roof.take_damage(roof.current_health)
	for tick in 120: await frame()
	giant.global_position = rv.to_global(Vector3(-18, 0, 4))
	giant.global_position.y = .02
	var facing: Vector3 = (player.execution_contact_position() - giant.global_position).slide(Vector3.UP).normalized()
	giant.rotation.y = atan2(-facing.x, -facing.z)
	initial_health = rv.get_engine().health
	previous_health = initial_health
	player.grab_control.released.connect(func(reason: String) -> void:
		if final_capture_tick >= 0: final_execution_releases.append(reason)
	)
	rv.vehicle_impact.connect(func(kind: String, loss: float, damage: float) -> void:
		physics_damage += damage
		print("ENCOUNTER_DRIVE_PHYSICS kind=", kind, " loss=", loss, " damage=", damage)
	)
	giant.attack_landed.connect(func(collider: Node, _kind: String) -> void:
		var mode := String(giant._encounter_decision.get("mode", "none"))
		if collider == rv and mode == "cabin": cabin_chassis_hits += 1
		if mode == "pursuit" and RVConnection.resolve(collider) == rv: pursuit_hits += 1
		mark("actual_attack_contact")
	)
	start_tick = Engine.get_physics_frames()
	previous_phase = giant.phase
	rv.set_handbrake(false)
	stage.set_giant_enabled(true)
	mark("live_start")
	while Engine.get_physics_frames() - start_tick < 4800:
		if replay_step == "approach" and giant.phase == SlenderSpeaker.Phase.GRAB and giant.phase_elapsed >= .05:
			replay_step = "evade"
			evasion_tick = Engine.get_physics_frames()
			evasion_start = rv.to_local(player.global_position)
			mark("normal_aisle_evasion")
		if replay_step == "evade":
			movement(1.0 if Engine.get_physics_frames() - evasion_tick < 32 else 0.0)
		elif replay_step == "drive":
			var throttle := clampf(.65 + (6.0 - rv.road_speed()) * .3, 0.0, 1.0)
			var steering := 1.0 if pursuit_tick >= 0 and steering_ticks < 15 else 0.0
			if steering > 0.0: steering_ticks += 1
			movement(throttle, 0.0, steering)
			if pursuit_hits > 0 and steering_ticks == 15:
				replay_step = "brake"
				brake_tick = Engine.get_physics_frames()
				mark("normal_service_braking")
		elif replay_step == "brake":
			movement(0.0, 1.0)
			if cabin_tick >= 0 and rv.road_speed() < .5:
				replay_step = "final_cabin"
				movement()
				mark("service_brake_released_for_final_cabin_grab")
		await frame()
		if evasion_tick >= 0 and first_miss_tick < 0:
			evasion_distance = maxf(evasion_distance, rv.to_local(player.global_position).distance_to(evasion_start))
		if retry_tick >= 0: drive_distance = maxf(drive_distance, rv.global_position.distance_to(drive_start))
		observe()
		if unexpected_captures > 0 or final_hold_tick >= 0: break
	check(evasion_distance > 1.0 and first_miss_tick >= 0 and misses > 0, "Sustained normal aisle movement causes a real first grab miss")
	check(retry_tick > first_miss_tick and retained_retry_ticks >= 180 and retry_target_losses == 0,
		"Missed grab retains the same cabin survivor and RV through complete recovery and an autonomous retry")
	check(maximum_speed > giant.settings.pursuit_enter_speed and drive_distance > 10.0 and steering_ticks == 15,
		"The real seated driver accelerates and steers the wheel-powered RV")
	check(pursuit_tick > retry_tick and pursuit_action_ticks > 0 and pursuit_hits > 0,
		"Sustained high speed becomes pursuit and produces actual vehicle-assault contact")
	check(brake_tick > pursuit_tick and cabin_tick > brake_tick and rv.road_speed() < giant.settings.cabin_enter_speed,
		"Normal service braking returns the same encounter to cabin mode")
	check(cabin_assault_ticks == 0 and cabin_chassis_hits == 0 and cabin_unexplained_damage < .001,
		"Every cabin segment avoids vehicle assault and giant chassis damage after measured physics impacts")
	check(locked_identity_losses == 0 and unexpected_captures == 0,
		"Every committed action retains its identity and actual evasions prevent capture before the final stop")
	check(handbrake_ticks == 0 and not rv.handbrake and encounter_target_loss_ticks == 0,
		"The entire live encounter leaves the handbrake released and retains the same survivor and RV")
	check(final_capture_tick > cabin_tick and final_hold_tick > final_capture_tick and player.grab_control.captor == giant
		and player.global_position.y > final_capture_height + 5.0 and final_execution_releases.is_empty(),
		"After service braking the giant autonomously grabs its seated survivor and completes the full lift to HOLD")
	print("ENCOUNTER_DRIVE_RESULT ", JSON.stringify({"attempts": attempts, "misses": misses,
		"evasion_m": evasion_distance, "retained_retry_ticks": retained_retry_ticks, "retry_target_losses": retry_target_losses,
		"maximum_kmh": maximum_speed * 3.6, "drive_m": drive_distance, "steering_ticks": steering_ticks,
		"pursuit_action_ticks": pursuit_action_ticks, "pursuit_hits": pursuit_hits,
		"cabin_assault_ticks": cabin_assault_ticks, "cabin_chassis_hits": cabin_chassis_hits,
		"cabin_unexplained_damage": cabin_unexplained_damage, "physics_damage": physics_damage,
		"initial_engine_health": initial_health, "final_engine_health": rv.get_engine().health,
		"locked_identity_losses": locked_identity_losses, "captures": captures, "unexpected_captures": unexpected_captures,
		"handbrake_ticks": handbrake_ticks, "final_handbrake": rv.handbrake, "encounter_target_loss_ticks": encounter_target_loss_ticks,
		"final_capture_tick": final_capture_tick, "final_hold_tick": final_hold_tick,
		"final_execution_releases": final_execution_releases,
		"modes": mode_counts, "reasons": reason_counts, "events": events}))
	await finish()

func finish() -> void:
	movement()
	if is_instance_valid(stage): stage.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty(): print("PASS: live wheel replay retains a missed cabin grab through retry, accelerates to physical pursuit attack and brakes back to cabin capture with full HOLD")
	quit(0 if failures.is_empty() else 1)
