extends SceneTree
## Intact roofs, actual free-play wheel suspension, autonomous approach and
## physical hand contact. A slow drifting stance must permit a completed turn.
const Wait := preload("res://tests/support/test_wait.gd")
const ParkedAttack := preload("res://enemies/slender_speaker/slender_speaker_parked_attack.gd")
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

func sample(giant: SlenderSpeaker, rv: Chassis) -> Dictionary:
	var plan: Dictionary = giant._parked_plan
	var stance: Vector3 = plan.get("standoff_point", Vector3.INF)
	var longitudinal := -1.0
	if stance != Vector3.INF and plan.has("route_frame"):
		var frame: Transform3D = plan.route_frame
		longitudinal = absf((frame.affine_inverse() * giant.global_position).z - (frame.affine_inverse() * stance).z)
	return {"phase": SlenderSpeaker.Phase.keys()[giant.phase], "rv_speed": rv.road_speed(),
		"speed": giant.velocity.slide(Vector3.UP).length(), "gap": plan.get("gap", -1.0),
		"clearance": plan.get("clearance", -1.0), "longitudinal": longitudinal,
		"facing": giant._facing_dot(plan.surface_point) if plan.has("surface_point") else -1.0,
		"ready": plan.get("can_attack", false), "turn_in_place": plan.get("turn_in_place", false),
		"search_remaining": giant._encounter._remaining, "roof": str(plan.get("roof")),
		"recoveries": giant._parked_recoveries}

func encounter(label: String, x: float) -> void:
	var rv: Chassis = stage.rv
	var giant: SlenderSpeaker = stage.giant
	var player: CharacterBody3D = stage.player
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	check(stage.mode == 0 and not rv.freeze and rv.control_override.is_empty(), label + " uses live free-play wheel physics")
	for id in ["roof_0", "roof_1", "roof_2"]:
		check(not slots.panel(id).is_destroyed, label + " starts with " + id + " intact")
	player.seated_in.exit_seat(true)
	player.global_position = rv.to_global(Vector3(x, .3, 5.2))
	player.rotation.y = rv.rotation.y
	await frames(120)
	rv.set_handbrake(false)
	var initial_health := rv.get_engine().health
	var chassis_hits := [0]
	giant.attack_landed.connect(func(collider: Node, _kind: String) -> void:
		if collider == rv: chassis_hits[0] += 1)
	stage.set_giant_enabled(true)
	var start := Engine.get_physics_frames()
	var reach_tick := -1
	var smash_tick := -1
	var destroy_tick := -1
	var roof: RVStructurePanel
	var peak_rv_speed := 0.0
	var previous_phase := giant.phase
	var deadline_sample := {}
	var roof_action_ticks := 0
	var wrong_action_ticks := 0
	while Engine.get_physics_frames() - start < 1500:
		await frames()
		var now := Engine.get_physics_frames()
		peak_rv_speed = maxf(peak_rv_speed, rv.road_speed())
		var plan: Dictionary = giant._parked_plan
		var observation := sample(giant, rv)
		if giant.phase == SlenderSpeaker.Phase.SMASH:
			if giant._action_context.get("kind", "") == "roof": roof_action_ticks += 1
			else: wrong_action_ticks += 1
		# Read the actual exterior reach geometry, never supply an AI plan.
		if reach_tick < 0 and is_instance_valid(plan.get("roof")) and plan.has("route_frame"):
			var frame: Transform3D = plan.route_frame
			var route: Vector3 = frame.affine_inverse() * Vector3(plan.navigation_point)
			var stance: Vector3 = frame.affine_inverse() * Vector3(plan.standoff_point)
			if route.distance_squared_to(stance) <= .01 and float(observation.clearance) >= 2.55 \
				and float(observation.clearance) <= 3.05 and float(observation.gap) <= 3.5 \
				and float(observation.longitudinal) <= 1.0:
				reach_tick = now
				roof = plan.roof
				print("ROOF_APPROACH_REACH ", label, " t=", float(now - start) / 60.0, " ", JSON.stringify(observation))
		if reach_tick >= 0 and now - reach_tick >= 180 and deadline_sample.is_empty():
			deadline_sample = observation
		if giant.phase == SlenderSpeaker.Phase.SMASH and smash_tick < 0:
			smash_tick = now
		if giant.phase != previous_phase:
			print("ROOF_APPROACH_PHASE ", label, " t=", float(now - start) / 60.0, " ", JSON.stringify(observation))
		previous_phase = giant.phase
		if is_instance_valid(roof) and roof.is_destroyed:
			destroy_tick = now
			break
	var delay := float(smash_tick - reach_tick) / 60.0 if smash_tick >= 0 and reach_tick >= 0 else -1.0
	print("ROOF_APPROACH_RESULT ", label, " reach_to_smash_s=", delay,
		" roof_destroy_s=", float(destroy_tick - start) / 60.0 if destroy_tick >= 0 else -1.0,
		" peak_rv_speed=", peak_rv_speed, " deadline=", JSON.stringify(deadline_sample),
		" final=", JSON.stringify(sample(giant, rv)))
	check(reach_tick >= 0, label + " autonomously reaches the intact roof's exterior hand envelope")
	check(smash_tick >= reach_tick and delay >= 0.0 and delay <= 3.0,
		label + " turns and starts its first roof smash within three seconds of entering reach")
	check(destroy_tick > smash_tick and is_instance_valid(roof) and roof.is_destroyed,
		label + " destroys that actual intact roof through physical hand contact")
	check(roof_action_ticks > 0 and wrong_action_ticks == 0, label + " commits only the roof action during every smash sample")
	for id in ["roof_0", "roof_1", "roof_2"]:
		var other: RVStructurePanel = slots.panel(id)
		if other != roof: check(not other.is_destroyed, label + " preserves unrelated " + id)
	check(not rv.handbrake and peak_rv_speed > (.2 if x > 0.0 else .02), label + " exercises real suspension drift with the brake released")
	check(chassis_hits[0] == 0 and is_equal_approx(rv.get_engine().health, initial_health),
		label + " preserves chassis engine health throughout its low-speed roof encounter")
	stage.set_giant_enabled(false)

func planner_boundaries() -> void:
	# Isolated geometry probes do not run AI, authorize attacks or alter panels.
	var giant: SlenderSpeaker = stage.giant
	var rv: Chassis = stage.rv
	check(not giant.can_process(), "Planner boundary fixture keeps the giant disabled")
	giant.global_position = rv.to_global(Vector3(-8, 0, -4))
	var seed := ParkedAttack.new().update(giant, rv, 0.0)
	var frame: Transform3D = seed.route_frame
	var shell: AABB = seed.route_shell
	var stance: Vector3 = frame.affine_inverse() * Vector3(seed.standoff_point)
	var actor_y := giant.global_position.y
	for case in [["INNER_CLEARANCE", 2.54, 0.0], ["OUTER_CLEARANCE", 3.06, 0.0],
		["LONGITUDINAL", 2.8, 1.01], ["PLANAR_GAP", 3.6, 0.0]]:
		var planner := ParkedAttack.new()
		# Commit the roof area without first entering its turn envelope.
		giant.global_position = frame * Vector3(shell.position.x - 4.0, 0, stance.z)
		giant.global_position.y = actor_y
		planner.update(giant, rv, 0.0)
		var position := Vector3(shell.position.x - float(case[1]), 0, stance.z + float(case[2]))
		giant.global_position = frame * position
		giant.global_position.y = actor_y
		var plan: Dictionary = planner.update(giant, rv, 0.0)
		var direction: Vector3 = (Vector3(plan.surface_point) - giant.global_position).slide(Vector3.UP).normalized()
		giant.rotation.y = atan2(-direction.x, -direction.z)
		plan = planner.update(giant, rv, 0.0)
		print("ROOF_APPROACH_BOUNDARY ", case[0], " gap=", plan.gap, " clearance=", plan.clearance, " turn=", plan.get("turn_in_place", false))
		check(not plan.get("turn_in_place", false) and plan.action == "approach", String(case[0]) + " cannot authorize a roof turn or attack outside physical reach")
		if case[0] == "PLANAR_GAP": check(float(plan.gap) > 3.5, "Planar boundary actually exceeds the roof reach limit")
	roof_turn_hysteresis(giant, rv, frame, shell, stance, actor_y)
	var planner := ParkedAttack.new()
	giant.global_position = frame * stance
	giant.global_position.y = actor_y
	planner.update(giant, rv, 0.0)
	giant.global_position = frame * Vector3(shell.end.x + 2.8, 0, stance.z)
	giant.global_position.y = actor_y
	var routed: Dictionary = planner.update(giant, rv, 0.0)
	check(Vector3(routed.navigation_point).distance_squared_to(Vector3(routed.standoff_point)) > .01 \
		and not routed.get("turn_in_place", false) and routed.action == "approach",
		"An opposite-side route must walk around the RV before turning toward a roof")
	giant.global_position = frame * stance
	giant.global_position.y = actor_y
	var original_map := giant.giant_navigation_map
	giant.giant_navigation_map = RID()
	var unready := ParkedAttack.new().update(giant, rv, 0.0)
	check(not unready.can_attack and unready.action == "approach", "An unready navigation map cannot authorize roof attack inside reach")
	giant.giant_navigation_map = original_map
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	for id in ["roof_0", "roof_1", "roof_2"]: check(not slots.panel(id).is_destroyed, "Planner probes preserve actual " + id)

func roof_turn_hysteresis(giant: SlenderSpeaker, rv: Chassis, frame: Transform3D, shell: AABB, stance: Vector3, actor_y: float) -> void:
	var planner := ParkedAttack.new()
	giant.global_position = frame * Vector3(shell.position.x - 2.54, 0, stance.z)
	giant.global_position.y = actor_y
	var plan: Dictionary = planner.update(giant, rv, 0.0)
	check(not plan.get("turn_in_place", false), "A fresh roof approach cannot enter the turn hold outside 2.55 metres")
	giant.global_position = frame * stance
	giant.global_position.y = actor_y
	plan = planner.update(giant, rv, 0.0)
	var direction := (Vector3(plan.surface_point) - giant.global_position).slide(Vector3.UP).normalized()
	giant.rotation.y = atan2(-direction.x, -direction.z) + PI * .5
	plan = planner.update(giant, rv, 0.0)
	check(plan.get("turn_in_place", false) and not plan.can_attack, "Entering roof reach permits a body turn while still requiring attack facing")
	var retained_ticks := 0
	for tick in 24:
		var clearance := 2.55 + (.005 if tick % 2 == 0 else -.005)
		giant.global_position = frame * Vector3(shell.position.x - clearance, 0, stance.z)
		giant.global_position.y = actor_y
		plan = planner.update(giant, rv, 1.0 / 60.0)
		if plan.get("turn_in_place", false) and not plan.can_attack: retained_ticks += 1
	print("ROOF_TURN_NOISE retained_ticks=", retained_ticks, " samples=24 clearance=2.545..2.555")
	check(retained_ticks == 24, "Suspension-sized noise across 2.55 metres retains the unfinished roof turn without authorizing a smash")
	for case in [["INNER_RELEASE", 2.44, 0.0], ["OUTER_RELEASE", 3.16, 0.0],
		["LONGITUDINAL_RELEASE", 2.8, 1.01], ["RANGE_RELEASE", 3.6, 0.0]]:
		giant.global_position = frame * stance
		giant.global_position.y = actor_y
		plan = planner.update(giant, rv, 0.0)
		check(plan.get("turn_in_place", false), String(case[0]) + " begins with an entered roof turn")
		giant.global_position = frame * Vector3(shell.position.x - float(case[1]), 0, stance.z + float(case[2]))
		giant.global_position.y = actor_y
		plan = planner.update(giant, rv, 0.0)
		check(not plan.get("turn_in_place", false) and plan.action == "approach", String(case[0]) + " releases an existing roof turn outside its physical envelope")
	giant.global_position = frame * stance
	giant.global_position.y = actor_y
	planner.update(giant, rv, 0.0)
	giant.global_position = frame * Vector3(shell.end.x + 2.8, 0, stance.z)
	giant.global_position.y = actor_y
	plan = planner.update(giant, rv, 0.0)
	check(not plan.get("turn_in_place", false) and plan.action == "approach", "An entered roof turn cannot bypass a newly required opposite-side route")
	for reset_kind in ["invalidate", "reset"]:
		giant.global_position = frame * stance
		giant.global_position.y = actor_y
		planner.update(giant, rv, 0.0)
		if reset_kind == "invalidate": planner.invalidate_approach()
		else: planner.reset()
		giant.global_position = frame * Vector3(shell.position.x - 2.54, 0, stance.z)
		giant.global_position.y = actor_y
		plan = planner.update(giant, rv, 0.0)
		check(not plan.get("turn_in_place", false), reset_kind + " clears the previously entered roof turn")
	# Select a different, actually visible covering roof without damaging any
	# panel. The new area must enter its own envelope before inheriting a turn.
	planner = ParkedAttack.new()
	giant.global_position = frame * stance
	giant.global_position.y = actor_y
	var previous_roof: RVStructurePanel = planner.update(giant, rv, 0.0).roof
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	var next_roof: RVStructurePanel = slots.panel("roof_2")
	var remembered := Vector3.INF
	for entry in planner._roof_bounds(rv, frame):
		if entry.panel != next_roof: continue
		remembered = entry.box.get_center()
		remembered.y = entry.box.position.y - .5
		break
	check(remembered != Vector3.INF and previous_roof != next_roof, "Roof-change probe selects a different real covering panel")
	if remembered == Vector3.INF: return
	giant.global_position = frame * Vector3(shell.position.x - 2.54, 0, remembered.z)
	giant.global_position.y = actor_y
	direction = (frame * remembered - giant.global_position).slide(Vector3.UP).normalized()
	giant.rotation.y = atan2(-direction.x, -direction.z)
	plan = planner.update(giant, rv, 0.0, null, frame * remembered)
	check(plan.get("roof") == next_roof and not plan.get("turn_in_place", false) and plan.action == "approach", "A newly selected visible roof cannot inherit the previous panel's turn hold outside entry")

func run() -> void:
	stage = load("res://tests/slender_speaker_playground.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	var ready := await Wait.until(self, func() -> bool: return stage.running, 60000, true)
	check(ready and stage.mode == 0, "Production playground starts in manual free play")
	if ready:
		await encounter("RIGHT_REAR_UNBRAKED_INTACT", 1.4)
		await stage.select_mode(0)
		await encounter("LEFT_REAR_UNBRAKED_INTACT", -1.4)
		await stage.select_mode(0)
		await frames(120)
		planner_boundaries()
	stage.queue_free()
	await frames(3)
	if failures.is_empty(): print("PASS: intact-roof free-play approaches complete facing promptly during real RV suspension drift and physically remove roofs without chassis damage")
	quit(0 if failures.is_empty() else 1)
