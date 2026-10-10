extends SceneTree
## Real mode-0 AI, partial roof opening, normal RV suspension and free rolling.
## The fixture never seeds phases, velocities, target locks or hand contacts.
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

func encounter(label: String, handbrake: bool, all_roofs: bool, walk: bool, require_hold := true, placement := "cabin") -> void:
	var giant: SlenderSpeaker = stage.giant
	var player: CharacterBody3D = stage.player
	var rv: Chassis = stage.rv
	check(stage.mode == 0 and not rv.freeze and rv.control_override.is_empty(), label + " uses live free-play wheel physics")
	rv.set_handbrake(true if require_hold else handbrake)
	if placement != "driver":
		player.seated_in.exit_seat(true)
		player.global_position = rv.to_global(Vector3(-1.4, 2.452 if placement == "roof" else .3, -4))
		player.rotation.y = rv.rotation.y
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	var front_roof: RVStructurePanel = slots.panel("roof_0")
	for roof_id in ((["roof_0", "roof_1", "roof_2"] if all_roofs else ["roof_0"]) if placement == "cabin" else []):
		var roof: RVStructurePanel = slots.panel(roof_id)
		roof.take_damage(roof.current_health)
	# Let the actual spawned suspension settle before releasing its brake,
	# as a player does after parking and opening the roof. Motion stays live.
	var settling_start := Engine.get_physics_frames()
	while Engine.get_physics_frames() - settling_start < (120 if require_hold else 30): await frames()
	if placement == "driver":
		check(player.seated_in == rv.get_node("DriverSeat"), label + " starts in the actual occupied production driver seat")
	elif placement == "roof":
		check(player.rv_support.rv == rv and rv.to_local(player.global_position).y > 2.0 and not front_roof.is_destroyed,
			label + " starts physically supported by the intact production roof")
	rv.set_handbrake(handbrake)
	stage.set_giant_enabled(true)
	var timeline := begin_timeline(giant, rv)
	var previous_phase := giant.phase
	var start := Engine.get_physics_frames()
	var near_visible_ticks := 0
	var longest_near_visible_ticks := 0
	var attempts := 0
	var capture_tick := -1
	var capture_height := 0.0
	var hold_tick := -1
	var peak_rv_speed := 0.0
	var moved := false
	var movement_ticks := 0
	var movement_frame := -1
	var movement_start := Vector3.ZERO
	var movement_distance := 0.0
	var measured_walk := false
	var previous_tick := start
	var releases: Array[String] = []
	var release_contacts: Array[String] = []
	player.grab_control.released.connect(func(reason: String) -> void:
		releases.append(reason)
		if reason != "execution_path_blocked": return
		# Read the real full-body contact at the failed lift endpoint. A 1mm
		# diagnostic margin reveals its touching collider without changing play.
		var query: PhysicsShapeQueryParameters3D = player.grab_control._execution_shape_query(giant)
		query.margin = .001
		for hit in player.get_world_3d().direct_space_state.intersect_shape(query, 8):
			if hit.get("collider") != null: release_contacts.append(String(hit.collider.get_path()))
	)
	while Engine.get_physics_frames() - start < 2400:
		# Normal cabin movement starts after sight/approach, then stops. It does
		# not teleport either actor after the encounter has begun.
		if walk and not moved and giant.can_see_player(player) and giant.global_position.distance_to(player.global_position) < 8.0:
			moved = true
			movement_frame = Engine.get_physics_frames()
			movement_start = rv.to_local(player.global_position)
		if moved: movement_ticks = mini(12, Engine.get_physics_frames() - movement_frame)
		if moved and movement_ticks < 12:
			Input.action_press("move_back")
		else: Input.action_release("move_back")
		await frames()
		sample_timeline(giant, player, rv, timeline)
		if moved and movement_ticks >= 12 and not measured_walk:
			movement_distance = rv.to_local(player.global_position).distance_to(movement_start)
			measured_walk = true
		peak_rv_speed = maxf(peak_rv_speed, rv.road_speed())
		var near_visible := giant.phase == SlenderSpeaker.Phase.CHASE and giant.can_see_player(player) and giant.global_position.slide(Vector3.UP).distance_to(player.execution_contact_position().slide(Vector3.UP)) <= 3.5
		var current_tick := Engine.get_physics_frames()
		near_visible_ticks = near_visible_ticks + current_tick - previous_tick if near_visible else 0
		previous_tick = current_tick
		longest_near_visible_ticks = maxi(longest_near_visible_ticks, near_visible_ticks)
		if giant.phase == SlenderSpeaker.Phase.GRAB and previous_phase != giant.phase: attempts += 1
		if giant.phase != previous_phase:
			print("OPEN_ROOF_PHASE ", label, " t=", float(Engine.get_physics_frames() - start) / 60.0,
				" phase=", SlenderSpeaker.Phase.keys()[giant.phase], " rv_speed=", rv.road_speed(),
				" player=", rv.to_local(player.global_position), " giant=", rv.to_local(giant.global_position))
		previous_phase = giant.phase
		if player.is_executing() and capture_tick < 0:
			capture_tick = Engine.get_physics_frames() - start
			capture_height = player.global_position.y
		if giant.phase == SlenderSpeaker.Phase.HOLD and player.is_executing():
			hold_tick = Engine.get_physics_frames() - start
			break
		if capture_tick >= 0 and not releases.is_empty(): break
	Input.action_release("move_back")
	print("OPEN_ROOF_RESULT ", label, " attempts=", attempts, " capture_s=", float(capture_tick) / 60.0,
		" hold_s=", float(hold_tick) / 60.0, " near_visible_chase_s=", float(longest_near_visible_ticks) / 60.0,
		" peak_rv_speed=", peak_rv_speed, " walk_m=", movement_distance, " releases=", releases,
		" release_contacts_1mm=", release_contacts)
	check(attempts > 0 and capture_tick >= 0, label + " starts an autonomous grab and acquires the survivor through real hand contact")
	if require_hold:
		check(hold_tick > capture_tick and player.grab_control.captor == giant and player.global_position.y > capture_height + 5.0
			and releases.is_empty(), label + " completes its first lift to HOLD without releasing")
	check(longest_near_visible_ticks <= 300, label + " does not stare at a visible survivor within reach for over five seconds")
	if not handbrake: check(not rv.handbrake and peak_rv_speed > .2, label + " exercises actual free rolling with the handbrake released")
	if walk: check(movement_ticks == 12 and movement_distance > .25, label + " walks with sustained normal input before stopping")
	if placement == "driver": check(front_roof.is_destroyed, label + " autonomously opens the roof above its seated driver")
	elif placement == "roof": check(not front_roof.is_destroyed, label + " grabs the roof survivor without smashing their supporting roof")
	check_timeline(label, giant, timeline, not require_hold)
	stage.set_giant_enabled(false)
	giant._cancel_execution("test_complete")

func check_remembered_turn() -> void:
	# Focused boundary check: a valid 1.12m physical clearance lies inside
	# the 1.15m routing envelope. Observed turning must not become navigation.
	var giant: SlenderSpeaker = stage.giant
	var original_yaw := giant.rotation.y
	var original_phase := giant.phase
	var frame := Transform3D(Basis.IDENTITY, giant.global_position + Vector3(3.12, 0, 0))
	var facing := giant.global_position + Vector3.RIGHT * 2.5
	var snapshot := {
		"turn_in_place": true, "surface_point": facing, "facing_point": facing,
		"navigation_point": giant.global_position, "standoff_point": giant.global_position,
		"route_frame": frame, "route_shell": AABB(Vector3(-2, 0, -5), Vector3(4, 0, 10)),
		"body_margin": 1.1,
	}
	giant.rotation.y = 0.0
	var movement := giant._follow_parked_approach(snapshot, .1)
	check(movement == Vector3.ZERO and giant._facing_dot(facing) > .1,
		"Remembered reachable turn at 1.12m clearance faces the observed contact without routing away")
	check(giant.phase == original_phase and not stage.player.is_executing(),
		"Turn-only memory cannot authorize capture or change the combat phase")
	giant.rotation.y = original_yaw

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
	check(ready and stage.mode == 0, "Actual free-play stage starts")
	if not ready:
		quit(1)
		return
	var cases := [["PARTIAL_PARKED", true, false, false], ["PARTIAL_ROLLING", false, false, false],
		["ALL_ROOFS_ROLLING", false, true, false], ["PARTIAL_ROLLING_WALK_STOP", false, false, true],
		["PARTIAL_ROLLING_SPAWN_BOUNCE", false, false, false],
		["DRIVER_PARKED", true, false, false], ["ROOF_SURVIVOR_PARKED", true, false, false]]
	for index in cases.size():
		if index > 0: await stage.select_mode(0)
		var placement := "driver" if index == 5 else "roof" if index == 6 else "cabin"
		await encounter(cases[index][0], cases[index][1], cases[index][2], cases[index][3], index != 4, placement)
	check_remembered_turn()
	stage.queue_free()
	await frames(3)
	if failures.is_empty(): print("PASS: open-roof, rolling, seated driver and roof survivor encounters avoid giant chassis damage and retain player intent through real hand capture; settled cases complete their first lift to HOLD")
	quit(0 if failures.is_empty() else 1)
