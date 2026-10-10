extends SceneTree
## Actual production rig and chassis. Scripted frozen RV isolates hand contact;
## wheel-driven pursuit is observed separately in the playground.
var failures: Array[String] = []
var world: Node3D
var giant: SlenderSpeaker
var map: RID
var landed: Array[Node] = []
var wheel_chassis_height := 0.7

func _init() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func frames(count := 2) -> void:
	for tick in count: await physics_frame

func shape(body: Node3D, size: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)

func make_vehicle() -> Chassis:
	var rv: Chassis = load("res://rv/chassis.tscn").instantiate()
	rv.freeze = true
	rv.position = Vector3(0, 1, 35)
	world.add_child(rv)
	rv.set_physics_process(false)
	open_roofs.call_deferred(rv)
	return rv

func open_roofs(rv: Chassis) -> void:
	# Direct contact regressions expose the chassis. Autonomous slow RV
	# inspection must search and expire after all roofs are gone.
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	for slot in RVStructureSlots.layout():
		if slot.kind != "roof": continue
		var roof := slots.panel(slot.id)
		check(roof != null, "Exposed chassis fixture contains its production roof slot")
		if roof != null:
			roof.take_damage(roof.current_health)
			check(roof.is_destroyed, "Exposed chassis fixture opens each overhead roof before contact checks")

func panel(rv: Chassis, point: Vector3, size: Vector3) -> RVStructurePanel:
	var shell := RVStructurePanel.new()
	shell.position = point
	shape(shell, size)
	rv.add_child(shell)
	return shell

func prepare(rv: Chassis, speed := 0.0, gap := 4.0, gait_phase := 0.0) -> void:
	giant.position = Vector3(rv.position.x, 0, rv.position.z + 6.0 + gap)
	giant.rotation = Vector3.ZERO
	giant.reset_after_restore()
	rv.linear_velocity = Vector3(0, 0, -speed)
	# Frozen fixture bypasses wheel-integrated speed filtering intentionally.
	rv._road_speed = speed
	giant.velocity = rv.linear_velocity
	giant._vehicle_follow.reset()
	giant._follow_plan.clear()
	giant._parked_attack.reset()
	giant._parked_plan.clear()
	giant._refresh_sight()
	giant._update_encounter(0.0)
	giant._sense_remaining = 0.0
	check(giant.target_vehicle == rv and giant._vehicle_is_observed(rv), "Frozen chassis fixture is acquired through actual sight")
	giant._set_phase(SlenderSpeaker.Phase.CHASE)
	giant._gait_phase = gait_phase
	giant._gait_blend = smoothstep(4.0, 12.0, speed)
	if speed > .1: giant._sample_gait(0.0, speed)
	else: giant._sample("idle_play", 0.0)
	landed.clear()

func check_contact_contract() -> void:
	var rv := make_vehicle()
	var remaining := panel(rv, Vector3(0, 2, -5), Vector3(3.8, 3, .15))
	prepare(rv)
	await frames()
	var health := rv.get_engine().health
	giant._action_context = {"kind": "roof", "player": null, "vehicle": rv, "point": rv.global_position}
	giant._strike_resolved = false
	check(not giant.resolve_smash_hit(rv) and is_equal_approx(rv.get_engine().health, health) and landed.is_empty(), "A roof-removal context hitting chassis cannot pay chassis damage")
	giant._action_context.kind = "vehicle_assault"
	giant._strike_resolved = false
	check(giant.resolve_smash_hit(rv), "Exposed target chassis can be damaged while a distant panel remains intact")
	check(is_equal_approx(rv.get_engine().health, health - 60.0), "Chassis contact pays the configured 60 engine durability damage")
	check(not remaining.is_destroyed, "Exposed chassis contact does not destroy an unrelated shell panel")
	check(not giant.resolve_smash_hit(rv) and landed.size() == 1, "Repeated chassis contact in one strike cannot pay damage twice")
	check(is_equal_approx(rv.get_engine().health, health - 60.0), "Duplicate impact retains one damage payment")
	giant._strike_resolved = false
	check(giant.resolve_smash_hit(remaining) and remaining.current_health == 60.0, "Actual wall contact deals 60 damage")
	check(not giant.resolve_smash_hit(rv), "A surviving wall prevents chassis damage in the same swing")
	giant._strike_resolved = false
	check(giant.resolve_smash_hit(remaining), "The next panel contact destroys the damaged wall")
	check(remaining.is_destroyed and not giant.resolve_smash_hit(rv), "Breaking the last panel never spills into chassis damage in the same swing")
	check(is_equal_approx(rv.get_engine().health, health - 60.0), "Panel destruction leaves engine durability unchanged")
	var other := make_vehicle()
	other.position.x = 40
	giant._strike_resolved = false
	check(not giant.resolve_smash_hit(other) and is_equal_approx(other.get_engine().health, 450.0), "An unrelated vehicle cannot receive the target vehicle's chassis damage")
	rv.get_engine().health = 45.0
	check(rv.set_engine_running(true), "Damaged but live engine can run before fatal chassis strike")
	rv.engine_force = 100.0
	giant._strike_resolved = false
	check(giant.resolve_smash_hit(rv), "A subsequent chassis strike can finish the engine")
	check(rv.get_engine().health == 0.0 and not rv.energy.engine_running and rv.engine_force == 0.0, "Existing Chassis damage contract stops propulsion when engine durability reaches zero")
	check(not rv.set_engine_running(true), "Destroyed engine cannot restart")
	rv.queue_free()
	other.queue_free()
	await frames()

func check_roof_progress_contract() -> void:
	var rv := make_vehicle()
	var committed := panel(rv, Vector3(0, 2, -5), Vector3(3.8, .15, 3))
	var other := panel(rv, Vector3(0, 2, 5), Vector3(3.8, .15, 3))
	prepare(rv)
	await frames()
	var observed := giant._observation.duplicate()
	for scenario in ["other_panel", "hidden_rv", "zero_damage", "vehicle_assault", "roof_progress"]:
		committed.set_health(committed.max_health)
		other.set_health(other.max_health)
		giant._observation = observed.duplicate()
		giant._encounter.reset()
		giant._encounter.update(observed, 0.0, giant.settings)
		giant._encounter.update({}, 2.0, giant.settings, true)
		var before := giant._encounter._remaining
		giant._action_context = {"kind": "vehicle_assault" if scenario == "vehicle_assault" else "roof", "vehicle": rv, "roof": committed}
		giant._strike_resolved = false
		if scenario == "hidden_rv": giant._observation.clear()
		if scenario == "zero_damage": giant.settings.smash_wall_damage = 0.0
		giant.resolve_smash_hit(other if scenario == "other_panel" else committed)
		giant.settings.smash_wall_damage = 60.0
		var expected := giant.settings.search_seconds if scenario == "roof_progress" else before
		check(is_equal_approx(giant._encounter._remaining, expected), "Only positive committed-roof damage with current RV sight extends inspection: " + scenario)
	# A repeated callback in the same strike cannot extend the new window.
	giant._encounter.update({}, 1.0, giant.settings, true)
	check(not giant.resolve_smash_hit(committed) and is_equal_approx(giant._encounter._remaining, 7.0), "Duplicate roof impact cannot refresh the inspection again")
	check(giant._encounter.update({}, 7.1, giant.settings).mode == "none", "Losing actual RV sight after roof progress still expires the encounter")
	rv.queue_free()
	await frames()

func check_expired_survivor_roof_inspection() -> void:
	# The old observation is in an already open rear cabin. Only the front
	# production roof remains, so retaining rear search memory cannot select it.
	var rv: Chassis = load("res://rv/chassis.tscn").instantiate()
	rv.freeze = true
	rv.position = Vector3(0, wheel_chassis_height, 35)
	world.add_child(rv)
	rv.set_physics_process(false)
	await frames(3)
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	for id in ["roof_1", "roof_2"]:
		var opened := slots.panel(id)
		opened.take_damage(opened.current_health)
	var remaining := slots.panel("roof_0")
	remaining.set_health(remaining.max_health)
	var survivor: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(survivor)
	survivor.set_physics_process(false)
	survivor.global_position = rv.to_global(Vector3(0, .3, 5.2))
	survivor.velocity = Vector3(0, 0, -1)
	giant.reset_after_restore()
	giant.velocity = Vector3.ZERO
	giant.global_position = rv.to_global(Vector3(-8, -wheel_chassis_height, 5.2))
	giant.rotation.y = -PI / 2.0
	giant._sample("idle_play", 0.0)
	landed.clear()
	await frames(5)
	giant._refresh_sight()
	giant._update_encounter(0.0)
	var remembered: Vector3 = giant._encounter_decision.get("search_point", Vector3.INF)
	check(giant.target_player == survivor and giant.target_vehicle == rv and giant._encounter_decision.get("mode") == "cabin", "Expiry fixture acquires a real visible survivor in the open rear RV cabin")
	check(giant._encounter._has_local, "Real cabin sight records RV-local survivor memory")
	# Enclosing collision geometry hides every posed contact proxy without
	# changing the survivor, target, encounter mode or remaining countdown.
	var occluder := StaticBody3D.new()
	shape(occluder, Vector3(2.0, 4.0, 2.0))
	world.add_child(occluder)
	occluder.global_position = survivor.global_position + Vector3(0, 1.5, 0)
	await frames(3)
	giant._refresh_sight()
	check(not giant.can_see_player(survivor) and giant._vehicle_is_observed(rv), "Actual rear occluder hides the survivor while the same RV remains visible")
	check(giant._observation.get("roof_visible", false), "The remaining front roof is actually visible outside the old rear memory")
	var health := rv.get_engine().health
	# Age the real owner through controller updates with fresh physical sight.
	# Movement is held here to isolate expiry; subsequent navigation and hand
	# strikes use the complete production physics controller without injection.
	for tick in 479:
		await physics_frame
		giant._refresh_sight()
		giant._update_encounter(1.0 / 60.0)
	check(giant.target_player == survivor and giant._encounter_decision.get("intent") == "search", "Known cabin survivor stays remembered until the full eight-second search expires")
	for tick in 2:
		await physics_frame
		giant._refresh_sight()
		giant._update_encounter(1.0 / 60.0)
	check(giant.target_vehicle == rv and giant.target_player == null and giant._encounter_decision.get("intent") == "cabin", "Actual eight-second expiry retains the visibly observed RV and enters unknown-occupant cabin inspection")
	check(not giant._encounter._has_local and giant._encounter._search_offset_local == Vector3.ZERO and giant._encounter._remaining >= giant.settings.search_seconds - .02, "Expiry discards survivor local and motion memory and gives unknown roof inspection its fresh eight seconds")
	var planner_frame := rv.global_transform
	var old_local := planner_frame.affine_inverse() * remembered
	var old_area_covers_front := false
	for entry in giant._parked_attack._roof_bounds(rv, planner_frame):
		if entry.panel == remaining and giant._parked_attack._covers_horizontal(entry.box, old_local): old_area_covers_front = true
	check(not old_area_covers_front, "The only remaining production roof lies outside the old remembered cabin area")
	var blind_grab := false
	var wrong_smash := false
	var saw_front_plan := false
	var previous_health := remaining.current_health
	var physical_hits := 0
	var exact_payments := true
	var hidden_throughout := true
	for tick in 1800:
		await physics_frame
		giant._physics_process(1.0 / 60.0)
		hidden_throughout = hidden_throughout and not giant.can_see_player(survivor)
		if giant.phase == SlenderSpeaker.Phase.GRAB or survivor.is_grabbed(): blind_grab = true
		if giant.phase == SlenderSpeaker.Phase.SMASH and giant._action_context.get("kind") != "roof": wrong_smash = true
		if giant._parked_plan.get("roof") == remaining: saw_front_plan = true
		if remaining.current_health < previous_health:
			physical_hits += 1
			exact_payments = exact_payments and is_equal_approx(previous_health - remaining.current_health, 60.0) and giant._strike_contact_collider == remaining
			previous_health = remaining.current_health
		if remaining.is_destroyed: break
	check(saw_front_plan and remaining.is_destroyed and physical_hits == 2 and exact_payments, "Unknown inspection selects the remaining roof outside old memory and destroys it through two actual 60-point hand contacts")
	check(hidden_throughout and not blind_grab and not wrong_smash and not landed.has(rv) and is_equal_approx(rv.get_engine().health, health), "Expired occupant inspection never sees or blindly grabs the hidden survivor and cannot damage chassis")
	print("CHASSIS_EXPIRED_SURVIVOR_ROOF hits=", physical_hits, " destroyed=", remaining.is_destroyed, " hidden=", hidden_throughout, " front_plan=", saw_front_plan, " blind_grab=", blind_grab, " health=", rv.get_engine().health, " decision=", giant._encounter_decision, " plan=", giant._parked_plan)
	giant.reset_after_restore()
	occluder.queue_free()
	survivor.queue_free()
	rv.queue_free()
	await frames()

func check_animated_attack(speed: float, shield := false, block := false, remaining_shell := true, gap := 4.0, gait_phase := 0.0, chassis_height := 1.0, roof_context := false) -> void:
	var rv := make_vehicle()
	rv.position.y = chassis_height
	var distant: RVStructurePanel
	if remaining_shell: distant = panel(rv, Vector3(0, 2, -5), Vector3(3.8, 3, .15))
	var covering: RVStructurePanel
	if shield: covering = panel(rv, Vector3(0, 1.8, 6.1), Vector3(4.0, 3.5, .2))
	prepare(rv, speed, gap, gait_phase)
	await frames()
	var health := rv.get_engine().health
	giant._follow_vehicle(1.0 / 60.0)
	if gap > 4.3 and not shield:
		check(not giant._follow_plan.get("can_attack", false), "A low exposed chassis beyond actual arm reach requests closer approach instead of a guaranteed miss")
		for approach_tick in 600:
			rv.position += rv.linear_velocity / 60.0
			await physics_frame
			# Isolate following geometry/reach from autonomous target policy.
			giant._refresh_sight()
			var desired := giant._follow_vehicle(1.0 / 60.0)
			giant._move_swept(desired, 1.0 / 60.0)
			if giant._follow_plan.get("can_attack", false): break
		check(giant._follow_plan.get("can_attack", false), "Direct follow control closes the larger entry gap to a reachable chassis surface")
	else:
		check(giant._follow_plan.get("can_attack", false), "Real chassis or shield surface remains attackable at the normal four-metre following gap")
	if roof_context:
		giant._parked_plan = {"surface_point": giant._follow_plan.surface_point}
	giant._begin_smash("roof" if roof_context else "vehicle_assault")
	var blocker: StaticBody3D
	for tick in 109:
		rv.position += rv.linear_velocity / 60.0
		await physics_frame
		giant._physics_process(1.0 / 60.0)
		if giant.phase == SlenderSpeaker.Phase.SMASH and giant.phase_elapsed < giant.settings.smash_windup - .00001:
			check(is_equal_approx(rv.get_engine().health, health), "Animated windup never damages the chassis early")
		if tick == 77 and block:
			blocker = StaticBody3D.new()
			shape(blocker, Vector3(.3, .3, .3))
			world.add_child(blocker)
			blocker.global_position = giant._bone_position("socket_strike_R")
	check(giant.phase == SlenderSpeaker.Phase.RECOVER, "Animated chassis strike completes into recovery")
	if distant != null: check(not distant.is_destroyed, "Far surviving panel is unaffected by the local attack")
	if block:
		check(giant._strike_contact_collider == blocker, "An intervening blocker is the actual first swept contact")
		check(is_equal_approx(rv.get_engine().health, health) and landed.is_empty(), "Physical blocker prevents all chassis damage")
	elif shield:
		check(covering.current_health == 60.0 and giant._strike_contact_collider == covering, "The actual swept first-contact wall takes 60 damage and shields the chassis")
		check(is_equal_approx(rv.get_engine().health, health) and landed.size() == 1, "One swing damages only its panel and never pays chassis damage behind it")
	elif roof_context:
		check(giant._strike_contact_collider == rv, "Actual roof-context hand sweep physically reaches the exposed chassis")
		check(is_equal_approx(rv.get_engine().health, health) and landed.is_empty(), "Actual roof-context chassis contact cannot pay assault damage")
	else:
		check(giant._strike_contact_collider == rv, "Real production animated hand sweep reaches the exposed chassis")
		check(is_equal_approx(rv.get_engine().health, health - 60.0) and landed.size() == 1, "Real animated exposed chassis impact applies exactly one 60-point payment")
	print("CHASSIS_ANIMATED speed=", speed, " gap=", gap, " gait_phase=", gait_phase, " chassis_height=", chassis_height, " shield=", shield, " block=", block, " remaining_shell=", remaining_shell, " health=", health, "->", rv.get_engine().health, " contact=", giant._strike_contact_collider, " events=", landed.size(), " aim=", giant._strike_point, " socket=", giant._bone_position("socket_strike_R"), " root=", giant.global_position, " rv=", rv.global_position)
	if blocker != null: blocker.queue_free()
	rv.queue_free()
	await frames()

func measure_wheel_stance() -> void:
	var vehicle: Node3D = load("res://rv/new_rv.tscn").instantiate()
	vehicle.position = Vector3(40, 1.8, 35)
	world.add_child(vehicle)
	var chassis: Chassis = vehicle.get_node("Chassis")
	chassis.handbrake = true
	await frames(180)
	wheel_chassis_height = chassis.global_position.y
	check(chassis.get_installed_wheel_count() == 4, "Height calibration uses the production RV on all four real wheels")
	check(wheel_chassis_height > .4 and wheel_chassis_height < 1.8, "Production wheel suspension settles to a plausible floor-relative chassis height")
	print("CHASSIS_WHEEL_STANCE height=", wheel_chassis_height, " speed=", chassis.linear_velocity.length())
	vehicle.queue_free()
	await frames()

func check_repeated_follow_attacks(initial_speed: float) -> void:
	var rv := make_vehicle()
	rv.position.y = wheel_chassis_height
	var distant := panel(rv, Vector3(0, 2, -5), Vector3(3.8, 3, .15))
	prepare(rv, initial_speed, 5.4, .51)
	await frames()
	var health := rv.get_engine().health
	var actual_speed := initial_speed
	var parked_hits := 0
	var attack_entries := 0
	var previous_phase := giant.phase
	var previous_hits := 0
	for tick in 2400:
		rv.linear_velocity = Vector3(0, 0, -actual_speed)
		rv._road_speed = actual_speed
		rv.position += rv.linear_velocity / 60.0
		await physics_frame
		giant._physics_process(1.0 / 60.0)
		if giant.phase == SlenderSpeaker.Phase.SMASH and previous_phase != giant.phase: attack_entries += 1
		previous_phase = giant.phase
		if landed.size() > previous_hits:
			if is_zero_approx(actual_speed): parked_hits += 1
			previous_hits = landed.size()
			actual_speed = 0.0
	check(landed.size() == (1 if initial_speed > giant.settings.pursuit_enter_speed else 0), "Autonomous exposed chassis receives only the initial fast assault; a parked RV cannot start subsequent chassis attacks")
	check(parked_hits == 0, "No new chassis damage is authorized after the RV parks")
	check(giant._encounter_decision.get("intent") == "none" and giant.target_vehicle == null, "Bare parked RV inspection expires and clears its target")
	check(not distant.is_destroyed, "Repeated exposed-chassis attacks preserve the remote intact panel")
	check(is_equal_approx(rv.get_engine().health, health - landed.size() * 60.0), "Repeated attacks each pay exactly one chassis damage event")
	print("CHASSIS_REPEAT initial_speed=", initial_speed, " entries=", attack_entries, " hits=", landed.size(), " parked_hits=", parked_hits, " health=", rv.get_engine().health, " final_phase=", giant.phase, " facing=", giant._facing_dot(giant._attack_surface()), " aim=", giant._strike_point, " socket=", giant._bone_position("socket_strike_R"), " plan=", giant._follow_plan)
	rv.queue_free()
	await frames()

func check_braking_overshoot_recovery(initial_gap: float) -> void:
	var rv := make_vehicle()
	rv.position.y = wheel_chassis_height
	if not rv.is_in_group(Groups.RV): rv.add_to_group(Groups.RV)
	var distant := panel(rv, Vector3(0, 2, -5), Vector3(3.8, 3, .15))
	prepare(rv, 0.0, initial_gap, .41)
	giant.velocity = Vector3(0, 0, -6.0)
	giant._sample_gait(0.0, 6.0)
	giant._sense_remaining = 0.0
	await frames()
	var body_contacts := 0
	var hidden_frames := 0
	var search_frames := 0
	var backstep_frames := 0
	var reverse_gait_frames := 0
	var wrong_gait_frames := 0
	var min_facing := 1.0
	var closest_z := giant.global_position.z
	var max_retreat := 0.0
	for tick in 1800:
		var previous_phase := giant.phase
		var previous_gait := giant._gait_phase
		await physics_frame
		giant._physics_process(1.0 / 60.0)
		var inspecting: bool = giant._encounter_decision.get("intent", "none") != "none"
		if inspecting:
			closest_z = minf(closest_z, giant.global_position.z)
			max_retreat = maxf(max_retreat, giant.global_position.z - closest_z)
		if inspecting and not giant._visible_target: hidden_frames += 1
		if inspecting and giant.phase == SlenderSpeaker.Phase.SEARCH: search_frames += 1
		if inspecting:
			for index in giant.get_slide_collision_count():
				if RVConnection.resolve(giant.get_slide_collision(index).get_collider()) == rv: body_contacts += 1
		if inspecting and giant.velocity.z > .15:
			backstep_frames += 1
			min_facing = minf(min_facing, giant._facing_dot(rv.global_position))
			if previous_phase == giant.phase and giant.phase in [SlenderSpeaker.Phase.CHASE, SlenderSpeaker.Phase.SMASH, SlenderSpeaker.Phase.RECOVER]:
				var gait_delta := fposmod(giant._gait_phase - previous_gait + .5, 1.0) - .5
				if gait_delta < -.00001: reverse_gait_frames += 1
				elif gait_delta > .00001: wrong_gait_frames += 1
	check(body_contacts == 0, "Braking overshoot never collides the giant body with the parked RV")
	check(hidden_frames == 0 and search_frames == 0, "Live visual sensing retains initial parked inspection while backing away")
	check(backstep_frames > 5 and max_retreat > .5 and min_facing > .85, "The giant visibly backs away toward its safe following slot while facing the RV")
	check(reverse_gait_frames > 0 and wrong_gait_frames == 0, "Backward pursuit and moving attack travel advance the walking cycle in reverse")
	check(landed.is_empty() and is_equal_approx(rv.get_engine().health, 450.0), "Braking recovery cannot convert roofless slow inspection into damaging chassis attacks")
	check(giant._encounter_decision.get("intent") == "none" and giant.target_vehicle == null, "Roofless parked inspection expires after braking recovery")
	check(not distant.is_destroyed, "Braking recovery does not redirect damage to an unrelated intact panel")
	print("CHASSIS_BRAKE_OVERSHOOT gap=", initial_gap, " hits=", landed.size(), " contacts=", body_contacts, " hidden_frames=", hidden_frames, " search_frames=", search_frames, " backstep_frames=", backstep_frames, " reverse_gait=", reverse_gait_frames, " wrong_gait=", wrong_gait_frames, " retreat=", max_retreat, " min_facing=", min_facing, " health=", rv.get_engine().health)
	rv.queue_free()
	await frames()

func check_parked_approach_from_side(approach: String, offset: Vector3) -> void:
	var rv := make_vehicle()
	rv.position.y = wheel_chassis_height
	if not rv.is_in_group(Groups.RV): rv.add_to_group(Groups.RV)
	var distant := panel(rv, Vector3(0, 2, 5 if approach == "front" else -5), Vector3(3.8, 3, .15))
	prepare(rv)
	giant.position = Vector3(rv.position.x, 0, rv.position.z) + offset
	var direction := -offset.normalized()
	giant.rotation.y = atan2(-direction.x, -direction.z)
	giant.target_vehicle = null
	giant.target_player = null
	giant._visible_target = false
	giant._sense_remaining = 0.0
	giant._set_phase(SlenderSpeaker.Phase.PATROL)
	await frames()
	var body_contacts := 0
	var search_frames := 0
	var saw_vehicle := false
	var reached_chase := false
	var attack_entries := 0
	var previous_phase := giant.phase
	for tick in 2400:
		await physics_frame
		giant._physics_process(1.0 / 60.0)
		if giant.target_vehicle == rv and giant._visible_target: saw_vehicle = true
		if giant.phase == SlenderSpeaker.Phase.CHASE: reached_chase = true
		if giant.phase == SlenderSpeaker.Phase.SEARCH: search_frames += 1
		if giant.phase == SlenderSpeaker.Phase.SMASH and previous_phase != giant.phase: attack_entries += 1
		previous_phase = giant.phase
		if giant._encounter_decision.get("intent", "none") != "none":
			for index in giant.get_slide_collision_count():
				if RVConnection.resolve(giant.get_slide_collision(index).get_collider()) == rv: body_contacts += 1
	check(saw_vehicle and reached_chase, "A parked RV is naturally acquired from its " + approach + " without injected target or visibility")
	check(landed.is_empty() and is_equal_approx(rv.get_engine().health, 450.0), "A parked " + approach + " inspection cannot damage exposed chassis without a vehicle-assault action")
	check(attack_entries == 0 and giant._encounter_decision.get("intent") == "none" and giant.target_vehicle == null, "A parked " + approach + " inspection expires instead of repeatedly attacking bare chassis")
	check(body_contacts == 0, "A parked " + approach + " approach routes without giant body collisions")
	check(not distant.is_destroyed, "A parked " + approach + " approach keeps the remote intact panel undamaged")
	print("CHASSIS_PARKED_APPROACH side=", approach, " acquired=", saw_vehicle, " chased=", reached_chase, " entries=", attack_entries, " hits=", landed.size(), " contacts=", body_contacts, " search_frames=", search_frames, " health=", rv.get_engine().health, " phase=", giant.phase, " position=", giant.global_position, " facing=", giant._facing_dot(rv.global_position), " plan=", giant._follow_plan)
	rv.queue_free()
	await frames()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	shape(floor_body, Vector3(400, .2, 400))
	floor_body.position.y = -.1
	world.add_child(floor_body)
	giant = load("res://enemies/slender_speaker/slender_speaker.tscn").instantiate()
	world.add_child(giant)
	giant.set_physics_process(false)
	giant.attack_landed.connect(func(target: Node, _kind: String): landed.append(target))
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-190, 0, -190), Vector3(-190, 0, 190), Vector3(190, 0, 190), Vector3(190, 0, -190)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)
	region.set_navigation_map(map)
	giant.set_giant_navigation_map(map)
	await frames()
	NavigationServer3D.map_force_update(map)
	check(giant.visual.available, "Production rig and hand sockets loaded")
	check(is_equal_approx(giant.settings.smash_chassis_damage, 60.0), "First-version chassis damage defaults to 60")
	await measure_wheel_stance()
	await check_expired_survivor_roof_inspection()
	await check_contact_contract()
	await check_roof_progress_contract()
	await check_animated_attack(0.0)
	await check_animated_attack(0.0, false, false, true, 4.0, 0.0, 1.0, true)
	await check_animated_attack(8.0)
	await check_animated_attack(8.0, false, false, false)
	await check_animated_attack(8.0, true)
	await check_animated_attack(8.0, false, true)
	for speed in [0.0, .1, .5, 1.0, 2.0, 3.0, 5.0, 8.0]:
		for entry in [Vector2(4.0, .23), Vector2(5.4, .71)]:
			await check_animated_attack(speed, false, false, true, entry.x, entry.y, wheel_chassis_height)
	for speed in [0.0, 3.0]:
		await check_animated_attack(speed, true, false, true, 4.0, .51, wheel_chassis_height)
		await check_animated_attack(speed, false, true, true, 4.0, .51, wheel_chassis_height)
	await check_repeated_follow_attacks(0.0)
	await check_repeated_follow_attacks(3.0)
	await check_braking_overshoot_recovery(1.5)
	await check_braking_overshoot_recovery(2.0)
	await check_parked_approach_from_side("front", Vector3(0, 0, -12))
	await check_parked_approach_from_side("side", Vector3(8, 0, 0))
	giant.set_giant_navigation_map(RID())
	NavigationServer3D.free_rid(map)
	world.queue_free()
	await frames()
	if failures.is_empty(): print("PASS: Slender Speaker chassis smash")
	else: print("FAIL Slender Speaker chassis smash: ", failures.size())
	quit(0 if failures.is_empty() else 1)
