extends SceneTree
## Load actual mode-0 free play: live new_rv suspension, production navigation,
## engine physics callbacks and autonomous sight/roof/grab contact decisions.
const Wait := preload("res://tests/support/test_wait.gd")
var stage: Node3D
var failures: Array[String] = []

func _init() -> void: run.call_deferred()

func frames(count := 1) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)

func movement(action: String) -> void:
	for other in ["move_forward", "move_back", "move_left", "move_right"]:
		if other == action: Input.action_press(other)
		else: Input.action_release(other)

func encounter(walk: bool) -> void:
	var label := "CABIN_WALK" if walk else "CABIN_RELOCATION"
	var giant: SlenderSpeaker = stage.giant
	var player: CharacterBody3D = stage.player
	var rv: Chassis = stage.rv
	check(stage.mode == 0 and not rv.freeze and rv.control_override.is_empty(),
		label + " keeps actual free-play new_rv wheel suspension and manual controls")
	# Relocation models changing the survivor's position inside the real cabin.
	# It does not choose targets, seed phases, call _begin_grab or move the giant.
	player.seated_in.exit_seat(true)
	player.global_position = rv.to_global(Vector3(0, .3, 2.0))
	player.rotation.y = rv.rotation.y
	var start_player := player.global_position
	stage.set_giant_enabled(true)
	var timeline := begin_timeline(giant, rv)
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	var rear_roof: RVStructurePanel = slots.panel("roof_2")
	var moved := false
	var movement_ticks := 0
	var movement_frame := -1
	var movement_start := Vector3.ZERO
	var movement_distance := 0.0
	var previous_phase := giant.phase
	var attempts := 0
	var observed := 0
	var hidden_roof_ticks := 0
	var capture_at := -1.0
	var start := Engine.get_physics_frames()
	for tick in 3300:
		var elapsed := Engine.get_physics_frames() - start
		if elapsed >= 3300: break
		# The second encounter crosses the aisle with sustained normal input
		# after autonomous roof removal, while the production AI stays enabled.
		if walk and not moved and stage._broken_panels() > 0:
			moved = true
			movement_start = player.global_position
			movement_frame = Engine.get_physics_frames()
		if moved: movement_ticks = mini(30, Engine.get_physics_frames() - movement_frame)
		if moved and movement_ticks < 30:
			movement("move_left")
		else: movement("")
		await frames()
		sample_timeline(giant, player, rv, timeline)
		if moved: movement_distance = maxf(movement_distance, player.global_position.distance_to(movement_start))
		if giant.can_see_player(player): observed += 1
		elif giant._visible_target and giant._parked_attack.has_roof: hidden_roof_ticks += 1
		if giant.phase == SlenderSpeaker.Phase.GRAB and previous_phase != giant.phase: attempts += 1
		if giant.phase != previous_phase:
			print("PLAYGROUND_TRACKING ", label, " t=", float(Engine.get_physics_frames() - start) / 60.0,
				" phase=", SlenderSpeaker.Phase.keys()[giant.phase], " local_player=", rv.to_local(player.global_position),
				" local_giant=", rv.to_local(giant.global_position), " roof_rear_destroyed=", rear_roof.is_destroyed)
		previous_phase = giant.phase
		if player.is_executing():
			capture_at = float(Engine.get_physics_frames() - start) / 60.0
			break
	print("PLAYGROUND_TRACKING_RESULT ", label, " attempts=", attempts, " visible_ticks=", observed,
		" hidden_roof_ticks=", hidden_roof_ticks, " roof_rear_destroyed=", rear_roof.is_destroyed,
		" capture_seconds=", capture_at, " walking_m=", movement_distance,
		" player_displacement_m=", player.global_position.distance_to(start_player))
	check(hidden_roof_ticks > 60, label + " exercises a visible RV with a roof-obscured survivor")
	check(rear_roof.is_destroyed, label + " removes the still-visible rear roof despite losing sight of its occupant")
	check(observed > 30 and attempts > 0, label + " reacquires the survivor and autonomously starts a real grab")
	check(capture_at >= 0.0 and player.grab_control.captor == giant,
		label + " captures the repositioned survivor through actual hand contact within 55 seconds")
	if walk: check(movement_ticks == 30 and movement_distance > .4, label + " physically crosses the cabin using sustained player input")
	movement("")
	# Ownership for one frame is not a successful lift. Keep real callbacks
	# running through the handoff and the complete upward motion.
	if player.is_executing():
		var capture_height := player.global_position.y
		var lift_start := Engine.get_physics_frames()
		while player.is_executing() and giant.phase == SlenderSpeaker.Phase.LIFT and Engine.get_physics_frames() - lift_start < 120:
			await frames()
			sample_timeline(giant, player, rv, timeline)
		check(player.is_executing() and giant.phase == SlenderSpeaker.Phase.HOLD
			and player.global_position.y > capture_height + 5.0,
			label + " retains ownership through a complete lift into HOLD without releasing on cabin geometry")
	check_timeline(label, giant, timeline)
	stage.set_giant_enabled(false)
	giant._cancel_execution("test_complete")

func begin_timeline(giant: SlenderSpeaker, rv: Chassis) -> Dictionary:
	var timeline := {"samples": 0, "vehicle_assault_ticks": 0, "cabin_assault_ticks": 0,
		"chassis_damage_ticks": 0, "initial_engine_health": rv.get_engine().health,
		"minimum_engine_health": rv.get_engine().health, "missed_grabs": 0,
		"retry_ticks": 0, "retry_target_loss_ticks": 0, "committed_target_loss_ticks": 0, "pending_retry": false,
		"last_visible_tick": -1, "previous_phase": giant.phase, "modes": {}, "reasons": {},
		"physics_impact_damage": 0.0, "physics_impacts": [], "giant_chassis_hits": 0}
	rv.vehicle_impact.connect(func(kind: String, speed_loss: float, damage: float) -> void:
		timeline.physics_impact_damage += damage
		timeline.physics_impacts.append({"kind": kind, "speed_loss": speed_loss, "damage": damage,
			"phase": SlenderSpeaker.Phase.keys()[giant.phase], "tick": Engine.get_physics_frames()})
	)
	giant.attack_landed.connect(func(collider: Node, _kind: String) -> void:
		if collider == rv: timeline.giant_chassis_hits += 1
	)
	return timeline

func sample_timeline(giant: SlenderSpeaker, player: CharacterBody3D, rv: Chassis, timeline: Dictionary) -> void:
	# Observe every phase, including missed reaches and recovery. This never
	# supplies an AI target or advances a combat phase.
	var decision: Dictionary = giant._encounter_decision
	var action: Dictionary = giant._action_context
	var encounter_mode := String(decision.get("mode", "none"))
	var reason := String(decision.get("reason", ""))
	timeline.samples += 1
	timeline.modes[encounter_mode] = int(timeline.modes.get(encounter_mode, 0)) + 1
	timeline.reasons[reason] = int(timeline.reasons.get(reason, 0)) + 1
	if action.get("kind", "") == "vehicle_assault":
		timeline.vehicle_assault_ticks += 1
		if encounter_mode == "cabin": timeline.cabin_assault_ticks += 1
	if action.get("kind", "") == "grab":
		if (encounter_mode != "cabin" or decision.get("player") != player or decision.get("vehicle") != rv
			or action.get("player") != player or action.get("vehicle") != rv):
			timeline.committed_target_loss_ticks += 1
	var engine_health: float = rv.get_engine().health
	timeline.minimum_engine_health = minf(timeline.minimum_engine_health, engine_health)
	if engine_health < float(timeline.initial_engine_health) - .001: timeline.chassis_damage_ticks += 1
	var now := Engine.get_physics_frames()
	if giant.can_see_player(player): timeline.last_visible_tick = now
	if timeline.previous_phase == SlenderSpeaker.Phase.GRAB and giant.phase != SlenderSpeaker.Phase.GRAB and not player.is_executing():
		timeline.missed_grabs += 1
		timeline.pending_retry = true
	if giant.phase == SlenderSpeaker.Phase.GRAB or player.is_executing(): timeline.pending_retry = false
	# A failed hand contact is not permission to forget a recently observed
	# cabin survivor. Continue checking across RECOVER and the next approach.
	if timeline.pending_retry and int(timeline.last_visible_tick) >= 0 and now - int(timeline.last_visible_tick) <= 480:
		timeline.retry_ticks += 1
		if encounter_mode != "cabin" or decision.get("player") != player or decision.get("vehicle") != rv:
			timeline.retry_target_loss_ticks += 1
	timeline.previous_phase = giant.phase

func check_timeline(label: String, giant: SlenderSpeaker, timeline: Dictionary, allow_physics_impacts := false) -> void:
	print("CABIN_ENCOUNTER_TIMELINE ", label, " counters=", JSON.stringify(timeline),
		" final=", giant.encounter_debug_text())
	check(timeline.samples > 0 and timeline.vehicle_assault_ticks == 0 and timeline.cabin_assault_ticks == 0
		and timeline.giant_chassis_hits == 0,
		label + " never commits a vehicle assault throughout its low-speed cabin encounter")
	if allow_physics_impacts:
		check(absf(float(timeline.initial_engine_health) - float(timeline.minimum_engine_health) - float(timeline.physics_impact_damage)) < .001,
			label + " attributes engine health loss only to measured ordinary vehicle physics impacts")
	else:
		check(timeline.chassis_damage_ticks == 0 and is_equal_approx(timeline.minimum_engine_health, timeline.initial_engine_health),
			label + " preserves chassis engine health throughout roof removal, grab and lift")
	check(timeline.retry_target_loss_ticks == 0,
		label + " retains the observed cabin player and RV after every missed grab through recovery and retry")
	check(timeline.committed_target_loss_ticks == 0,
		label + " keeps the committed cabin player and RV throughout grab, recovery and execution")

func run() -> void:
	stage = load("res://tests/slender_speaker_playground.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	var ready := await Wait.until(self, func() -> bool: return stage.running, 60000, true)
	check(ready and stage.mode == 0, "Actual default playground becomes ready in free play")
	if not ready:
		quit(1)
		return
	await encounter(false)
	await stage.select_mode(0)
	await encounter(true)
	movement("")
	stage.queue_free()
	await frames(3)
	if failures.is_empty(): print("PASS: actual free-play RV roof approach, cabin relocation and walking reach autonomous live grab contact")
	quit(0 if failures.is_empty() else 1)
