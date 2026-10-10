extends SceneTree
## Actual free-play new_rv, live suspension and autonomous AI at all cabin
## corners. No phase seeding, giant movement or forced attack/contact calls.
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

func encounter(label: String, corner: Vector3, walk := false) -> void:
	var giant: SlenderSpeaker = stage.giant
	var player: CharacterBody3D = stage.player
	var rv: Chassis = stage.rv
	check(stage.mode == 0 and not rv.freeze and rv.control_override.is_empty(),
		label + " uses free-play manual controls and live wheel suspension")
	player.seated_in.exit_seat(true)
	player.global_position = rv.to_global(corner)
	player.rotation.y = rv.rotation.y
	stage.set_giant_enabled(true)
	var timeline := begin_timeline(giant, rv)
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	var covering_roof: RVStructurePanel = slots.panel("roof_2" if corner.z > 0.0 else "roof_0")
	var previous_phase := giant.phase
	var grab_attempts := 0
	var visible_ticks := 0
	var capture_tick := -1
	var capture_height := 0.0
	var hold_tick := -1
	var released: Array[String] = []
	player.grab_control.released.connect(func(reason: String) -> void: released.append(reason))
	var moved := false
	var movement_ticks := 0
	var movement_frame := 0
	var movement_start := Vector3.ZERO
	var movement_distance := 0.0
	var start := Engine.get_physics_frames()
	for tick in 3600:
		if Engine.get_physics_frames() - start >= 3600: break
		# After the roof opens, cross part of the rear aisle with normal input.
		# The stationary right-rear case above retains the original spin repro.
		if walk and not moved and covering_roof.is_destroyed:
			moved = true
			movement_start = player.global_position
			movement_frame = Engine.get_physics_frames()
		if moved: movement_ticks = mini(30, Engine.get_physics_frames() - movement_frame)
		if moved and movement_ticks < 30:
			movement("move_left")
		else: movement("")
		await frames()
		sample_timeline(giant, player, rv, timeline)
		if moved and capture_tick < 0:
			movement_distance = maxf(movement_distance, player.global_position.distance_to(movement_start))
		if giant.can_see_player(player): visible_ticks += 1
		if giant.phase == SlenderSpeaker.Phase.GRAB and previous_phase != giant.phase: grab_attempts += 1
		if giant.phase != previous_phase:
			print("PLAYGROUND_CORNER ", label, " t=", float(Engine.get_physics_frames() - start) / 60.0,
				" phase=", SlenderSpeaker.Phase.keys()[giant.phase], " player=", rv.to_local(player.global_position),
				" giant=", rv.to_local(giant.global_position), " roof_destroyed=", covering_roof.is_destroyed)
		previous_phase = giant.phase
		if player.is_executing() and capture_tick < 0:
			capture_tick = Engine.get_physics_frames() - start
			capture_height = player.global_position.y
		if giant.phase == SlenderSpeaker.Phase.HOLD and player.is_executing():
			hold_tick = Engine.get_physics_frames() - start
			break
		if capture_tick >= 0 and not released.is_empty(): break
	print("PLAYGROUND_CORNER_RESULT ", label, " attempts=", grab_attempts, " visible_ticks=", visible_ticks,
		" capture_seconds=", float(capture_tick) / 60.0, " hold_seconds=", float(hold_tick) / 60.0,
		" height_gain_m=", player.global_position.y - capture_height,
		" release=", released, " walking_m=", movement_distance, " recoveries=", giant._parked_recoveries)
	check(covering_roof.is_destroyed, label + " autonomously removes the actual covering roof")
	check(visible_ticks > 30 and grab_attempts > 0, label + " reacquires the corner survivor and starts a physical grab")
	check(capture_tick >= 0 and hold_tick > capture_tick and player.grab_control.captor == giant and released.is_empty()
		and player.global_position.y > capture_height + 5.0,
		label + " maintains capture through the complete lift to HOLD within 60 seconds")
	if walk:
		check(movement_ticks == 30 and movement_distance > .4,
			label + " physically walks across the rear corner with sustained input")
	movement("")
	check_timeline(label, giant, timeline)
	stage.set_giant_enabled(false)
	giant._cancel_execution("test_complete")

func begin_timeline(giant: SlenderSpeaker, rv: Chassis) -> Dictionary:
	var timeline := {"samples": 0, "vehicle_assault_ticks": 0, "cabin_assault_ticks": 0,
		"chassis_damage_ticks": 0, "initial_engine_health": rv.get_engine().health,
		"minimum_engine_health": rv.get_engine().health, "missed_grabs": 0,
		"retry_ticks": 0, "retry_target_loss_ticks": 0, "committed_target_loss_ticks": 0, "pending_retry": false,
		"last_visible_tick": -1, "previous_phase": giant.phase, "modes": {}, "reasons": {},
		"physics_impact_damage": 0.0, "physics_impacts": [], "giant_chassis_hits": 0,
		"roof_contacts": [], "roof_plan_samples": [], "roof_turn_ticks": 0,
		"roof_turn_switches": 0, "previous_roof_turn": false}
	rv.vehicle_impact.connect(func(kind: String, speed_loss: float, damage: float) -> void:
		timeline.physics_impact_damage += damage
		timeline.physics_impacts.append({"kind": kind, "speed_loss": speed_loss, "damage": damage,
			"phase": SlenderSpeaker.Phase.keys()[giant.phase], "tick": Engine.get_physics_frames()})
	)
	giant.attack_landed.connect(func(collider: Node, _kind: String) -> void:
		if collider == rv: timeline.giant_chassis_hits += 1
		if collider is RVStructurePanel and String(collider.mount_slot).begins_with("roof_"):
			var planned: Node = giant._action_context.get("roof")
			timeline.roof_contacts.append({"slot": collider.mount_slot, "health": collider.current_health,
				"planned_slot": planned.mount_slot if is_instance_valid(planned) else "",
				"sample": timeline.samples, "destroyed": collider.is_destroyed})
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
	# Preserve evidence of the live roof approach when a corner cannot finish.
	# These are observations only: no planner calls, pose changes or contacts.
	var plan: Dictionary = giant._parked_plan
	var roof_turn := plan.get("roof") != null and bool(plan.get("turn_in_place", false))
	if roof_turn: timeline.roof_turn_ticks += 1
	if roof_turn != bool(timeline.previous_roof_turn): timeline.roof_turn_switches += 1
	timeline.previous_roof_turn = roof_turn
	if int(timeline.samples) % 300 == 0:
		var roof: RVStructurePanel = plan.get("roof")
		var roof_health := {}
		var slots: RVStructureSlots = rv.get_node("StructureSlots")
		for slot in ["roof_0", "roof_1", "roof_2"]:
			var panel := slots.panel(slot)
			roof_health[slot] = panel.current_health if panel != null else -1.0
		timeline.roof_plan_samples.append({"sample": timeline.samples, "phase": SlenderSpeaker.Phase.keys()[giant.phase],
			"status": plan.get("status", "empty"), "reason": plan.get("reason", ""),
			"selected_roof": roof.mount_slot if is_instance_valid(roof) else "", "roof_health": roof_health,
			"giant_local": rv.to_local(giant.global_position), "clearance": plan.get("clearance"),
			"gap": plan.get("gap"), "turn_in_place": roof_turn,
			"facing_dot": giant._facing_dot(plan.facing_point) if plan.has("facing_point") else null,
			"velocity": giant.velocity, "strike_obstruction": str(giant._strike_contact_collider)})
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
	check(ready and stage.mode == 0, "Actual playground starts in free play")
	if not ready:
		quit(1)
		return
	var cases := [
		["RIGHT_REAR", Vector3(1.4, .3, 5.2), false],
		["LEFT_REAR", Vector3(-1.4, .3, 5.2), false],
		["RIGHT_FRONT", Vector3(1.4, .3, -5.2), false],
		["LEFT_FRONT", Vector3(-1.4, .3, -5.2), false],
		["RIGHT_REAR_WALK", Vector3(1.4, .3, 5.2), true],
	]
	for index in cases.size():
		if index > 0: await stage.select_mode(0)
		await encounter(cases[index][0], cases[index][1], cases[index][2])
	movement("")
	stage.queue_free()
	await frames(3)
	if failures.is_empty(): print("PASS: actual free-play cabin corners and sustained corner walking reach HOLD through autonomous physical contact")
	quit(0 if failures.is_empty() else 1)
