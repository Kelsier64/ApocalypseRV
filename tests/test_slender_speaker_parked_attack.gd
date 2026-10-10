extends SceneTree
## Production RV/player/rig and physical first contact. RV restart is scripted;
## wheel-driven handling and rendered animation remain separate validation.
const GIANT := preload("res://enemies/slender_speaker/slender_speaker.tscn")
const PLAYER := preload("res://player/player.tscn")
const VEHICLE := preload("res://rv/new_rv.tscn")
const ParkedAttack := preload("res://enemies/slender_speaker/slender_speaker_parked_attack.gd")
var failures: Array[String] = []
var world: Node3D
var giant: SlenderSpeaker
var player: CharacterBody3D
var vehicle: Node3D
var chassis: Chassis
var map: RID

func _init() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)
func frames(count := 2) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func reset_fixture() -> void:
	giant._cancel_execution("fixture_reset")
	if player.is_grabbed(): player.grab_control.end("fixture_reset")
	if is_instance_valid(vehicle):
		vehicle.queue_free()
		await frames()
	# Retain fallen equipment for each real smash/grab encounter, and remove
	# fixture-owned world entities only when replacing that entire fixture.
	var previous_drops := world.get_node_or_null(WorldEntities.CONTAINER_NAME)
	if previous_drops != null:
		previous_drops.queue_free()
		await frames()
	# Checkpoint restore is not a respawn and retains the previous death flag.
	# Every autonomous attack needs a fresh, drive-capable production survivor.
	player.queue_free()
	await frames()
	player = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector3(0, .05, 40)
	player.grab_control.immunity = 0.0
	vehicle = VEHICLE.instantiate()
	vehicle.position.y = 1.226
	world.add_child(vehicle)
	chassis = vehicle.get_node("Chassis")
	chassis.freeze = true
	chassis.linear_velocity = Vector3.ZERO
	chassis.angular_velocity = Vector3.ZERO
	chassis._road_speed = 0.0
	giant.reset_after_restore()
	giant.velocity = Vector3.ZERO
	giant._sense_remaining = 0.0
	giant._vehicle_follow.reset()
	giant._follow_plan.clear()
	await frames(5)

func seat_player() -> Node3D:
	var seat: Node3D = chassis.get_node("DriverSeat")
	player.global_position = seat.global_position
	seat.interact_hold(player)
	player._physics_process(1.0 / 60.0)
	await frames(3)
	var locomotion: Node = player.get_node("Visuals/Locomotion")
	locomotion._physics_process(.7)
	player.get_node("Visuals").skeleton.force_update_all_bone_transforms()
	check(player.seated_in == seat and seat.current_driver == player and not player.is_player_dead,
		"Parked fixture seats a living production survivor through the real seat interaction")
	return seat

func face(point: Vector3) -> void:
	var direction := (point - giant.global_position).slide(Vector3.UP).normalized()
	giant.rotation = Vector3(0, atan2(-direction.x, -direction.z), 0)
	giant._sample("idle_play", 0.0)

func parked_plan(seconds := .6) -> Dictionary:
	var plan: Dictionary = {}
	for tick in int(ceil(seconds * 60.0)):
		refresh_encounter()
		if giant._encounter_decision.get("mode") == "cabin":
			var occupant: Node3D = giant._encounter_decision.get("player") if giant._encounter_decision.get("player_visible", false) else null
			plan = giant._parked_attack.update(giant, chassis, 1.0 / 60.0, occupant)
		else:
			plan = {}
	return plan

func refresh_encounter(delta := 1.0 / 60.0) -> void:
	giant._refresh_sight()
	giant._update_encounter(delta)

func track_parked_travel(previous: Vector3, stats: Dictionary) -> void:
	# Measure the swept body's displacement, rather than desired velocity or
	# a waypoint vector. Small stance corrections and braking are not a gait.
	var movement := (giant.global_position - previous).slide(Vector3.UP) * 60.0
	var lateral_speed := absf(movement.dot(giant.global_basis.x.slide(Vector3.UP).normalized()))
	var moving := movement.length() >= 1.2 and (not giant._parked_plan.is_empty() or not giant._parked_approach_memory.is_empty())
	if moving:
		stats.samples += 1
		stats.peak_lateral = maxf(stats.peak_lateral, lateral_speed)
	stats.lateral_ticks = int(stats.lateral_ticks) + 1 if moving and lateral_speed > .8 else 0
	stats.longest_lateral_ticks = maxi(stats.longest_lateral_ticks, stats.lateral_ticks)

func check_parked_travel(stats: Dictionary, label: String) -> void:
	check(stats.samples > 30, label + " checks actual parked navigation at walking speed")
	check(stats.longest_lateral_ticks < 30, label + " never sustains sideways travel above 0.8m/s for half a second")
	print("PARKED_TRAVEL ", label, " samples=", stats.samples,
		" peak_lateral=", stats.peak_lateral, " longest_lateral_seconds=", float(stats.longest_lateral_ticks) / 60.0)

func check_roof_selection() -> void:
	await reset_fixture()
	var seat := await seat_player()
	giant.global_position = chassis.to_global(Vector3(-9, -1.226, -4))
	face(seat.global_position)
	check(not giant.can_see(player, player.execution_contact_position()), "Production seated driver is hidden by intact shell")
	var health_before: float = chassis.get_engine().health
	var plan := parked_plan()
	var slots: RVStructureSlots = chassis.get_node("StructureSlots")
	check(plan.get("roof") == slots.panel("roof_0"), "Unknown parked RV inspection starts with the nearest front roof from the cab side")
	check(plan.get("occupant") == null, "Hidden driver does not become an omniscient parked target")
	check(chassis.get_engine().health == health_before and slots.panel("roof_1").can_operate() and slots.panel("roof_2").can_operate(),
		"Planning preserves chassis and roofs outside the cab")
	# Move the actual occupied seat under the middle roof and expose the posed
	# driver through a real side opening. Roof choice follows visible contact.
	slots.panel("left_1").take_damage(slots.panel("left_1").current_health)
	seat.position.z = 1.0
	player._physics_process(1.0 / 60.0)
	await frames(3)
	# At close range the high speaker's sight ray enters the intact roof;
	# observe through the side aperture from outside that roof silhouette.
	giant.global_position = chassis.to_global(Vector3(-60, -1.226, 1))
	face(player.execution_contact_position())
	giant._parked_attack.reset()
	refresh_encounter()
	var visibility_hit := giant.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
		giant._focus_position(), player.execution_contact_position(), giant.collision_mask, [giant.get_rid()]))
	print("PARKED_MOVED_DRIVER seat=", seat.global_position, " contact=", player.execution_contact_position(), " sight=", visibility_hit)
	check(giant.can_see(player, player.execution_contact_position()), "Moved production driver is visible through its matching side opening")
	check(giant.target_player == player and giant.target_vehicle == chassis, "Actual sight associates visible moved driver with its RV without seeded player target")
	plan = parked_plan()
	check(plan.get("occupant") == player and plan.get("roof") == slots.panel("roof_1"),
		"Roof above visible moved driver takes priority over the giant's nearest unknown roof")
	check(slots.panel("roof_0").can_operate() and slots.panel("roof_2").can_operate(), "Selecting occupant roof requires no blanket roof destruction")
	# A walking interior survivor uses the same actual vertical roof bounds.
	seat.exit_seat(true)
	player.global_position = chassis.to_global(Vector3(0, .55, 4))
	slots.panel("left_2").take_damage(slots.panel("left_2").current_health)
	await frames(3)
	giant.global_position = chassis.to_global(Vector3(-60, -1.226, 4))
	face(player.execution_contact_position())
	giant._parked_attack.reset()
	refresh_encounter()
	check(giant.target_player == player and giant.target_vehicle == chassis, "Actual sight associates visible unseated interior player with current physical RV bounds")
	plan = parked_plan()
	check(plan.get("occupant") == player and plan.get("roof") == slots.panel("roof_2"),
		"Visible interior walking player selects its own overhead roof")
	player.rv_support.clear()
	player.global_position = slots.panel("roof_2").global_position + Vector3(.5, .12, 0)
	player.velocity = Vector3.ZERO
	for tick in 24:
		player._physics_process(1.0 / 60.0)
		await frames(1)
	face(player.execution_contact_position())
	giant._parked_attack.reset()
	refresh_encounter()
	check(player.rv_support.rv == chassis and giant.target_player == player and giant.target_vehicle == chassis,
		"Real supported roof player is associated by fresh sight without seeded targets")
	check(not giant._observation.get("player_in_cabin", true) and not giant._encounter_decision.get("cabin_memory_attack", true),
		"Sight-confirmed roof walker does not authorize the new inside-cabin memory strike")
	plan = parked_plan()
	check(plan.get("occupant") == player and plan.get("roof") == null and slots.panel("roof_2").can_operate(),
		"Visible roof player is grabbed without destroying its supporting roof")
	player.rv_support.clear()
	player.global_position = chassis.to_global(Vector3(-3, -1.176, 4))
	player.velocity = Vector3.ZERO
	await frames(3)
	face(player.execution_contact_position())
	refresh_encounter()
	check(giant.can_see(player, player.execution_contact_position()) and giant.target_player == player
		and giant.target_vehicle == null, "Visible nearby ground player stays an ordinary ground target outside actual RV bounds")

func check_nearest_unknown_roofs() -> void:
	for area in [{"label": "middle", "z": 0.0, "roof": "roof_1"}, {"label": "rear", "z": 4.0, "roof": "roof_2"}]:
		await reset_fixture()
		await seat_player()
		var slots: RVStructureSlots = chassis.get_node("StructureSlots")
		giant.global_position = chassis.to_global(Vector3(-9, -1.226, float(area.z)))
		face(slots.panel(area.roof).global_position)
		await frames(3)
		check(not giant.can_see_player(player), "Nearest " + area.label + " roof fixture keeps the actual driver hidden behind intact shell")
		var planner := ParkedAttack.new()
		var plan: Dictionary = planner.update(giant, chassis, 0.0, player)
		check(plan.get("roof") == slots.panel(area.roof) and plan.get("occupant") == null and plan.get("smash_kind") == "roof", "Unknown " + area.label + " inspection selects its nearest visible physical roof without using hidden driver position")
		if not plan.has("surface_point"): continue
		check(giant.can_see(plan.roof, plan.surface_point), "Nearest " + area.label + " roof target is actually visible")
		var health: float = chassis.get_engine().health
		# A hidden player's current transform cannot replace an observed panel.
		player.global_position = Vector3(1000, 0, 1000)
		giant.global_position = chassis.to_global(Vector3(-9, -1.226, -4))
		face(slots.panel(area.roof).global_position)
		await frames(3)
		plan = planner.update(giant, chassis, .6, player)
		check(plan.get("roof") == slots.panel(area.roof) and plan.get("occupant") == null, "Committed " + area.label + " roof remains selected despite a closer front roof and hidden player movement")
		check(is_equal_approx(chassis.get_engine().health, health), "Nearest roof planning cannot damage chassis")
		for id in ["roof_0", "roof_1", "roof_2"]:
			check(slots.panel(id).can_operate(), "Nearest roof planning preserves intact " + id)
		if area.label != "rear": continue
		giant.global_position = chassis.to_global(Vector3(-9, -1.226, 4))
		for step in [{"removed": "roof_2", "next": "roof_1"}, {"removed": "roof_1", "next": "roof_0"}]:
			var removed := slots.panel(step.removed)
			removed.take_damage(removed.current_health)
			face(slots.panel(step.next).global_position)
			await frames(3)
			plan = planner.update(giant, chassis, .6)
			check(plan.get("roof") == slots.panel(step.next) and plan.get("occupant") == null, "Removing " + step.removed + " selects nearest remaining " + step.next + " without survivor evidence")

func check_remembered_open_cabin_plan() -> void:
	await reset_fixture()
	var slots: RVStructureSlots = chassis.get_node("StructureSlots")
	for id in ["roof_0", "roof_1", "roof_2"]:
		var roof := slots.panel(id)
		roof.take_damage(roof.current_health)
	giant.global_position = chassis.to_global(Vector3(-9, -1.226, 0))
	var remembered := chassis.to_global(Vector3(-1, 1.2, 0))
	face(remembered)
	player.global_position = Vector3(1000, 0, 1000)
	await frames(3)
	var planner := ParkedAttack.new()
	var plan: Dictionary = planner.update(giant, chassis, 0.0, player, remembered)
	check(plan.get("smash_kind") == "cabin_memory" and plan.get("roof") == null and plan.get("occupant") == null and plan.get("surface_point", Vector3.INF).is_equal_approx(remembered), "An open cabin memory plan aims at the exact supplied last observed point without a hidden occupant")
	check(plan.get("action") == "approach", "Distant cabin memory plan approaches before a physical strike")
	check(ParkedAttack.new().update(giant, chassis, 0.0).get("status") == "waiting", "Unknown roofless inspection cannot use the vehicle centre as survivor attack evidence")

func check_restart() -> void:
	await reset_fixture()
	await seat_player()
	giant.global_position = chassis.to_global(Vector3(-9, -1.226, -4))
	face(chassis.global_position)
	check(not parked_plan().is_empty(), "Stopped production RV enters parked attack after settling")
	chassis.linear_velocity = Vector3(0, 0, -4)
	chassis._road_speed = 4.0
	refresh_encounter(.7)
	check(giant._encounter_decision.get("mode") == "cabin",
		"Road speed above 10km/h for less than 0.75 seconds retains cabin hysteresis")
	refresh_encounter(.06)
	check(giant._encounter_decision.get("mode") == "pursuit",
		"Road speed above 10km/h for 0.75 seconds exits cabin through the encounter owner")
	for tick in 60:
		giant._physics_process(1.0 / 60.0)
		if giant.phase == SlenderSpeaker.Phase.CHASE and not giant._follow_plan.is_empty(): break
	check(giant.phase == SlenderSpeaker.Phase.CHASE and not giant._follow_plan.is_empty()
		and giant._parked_plan.is_empty(), "Restart resumes ordinary moving RV follow through controller CHASE")
	check(not player.is_grabbed(), "Restart cannot capture a player away from the vehicle")

func check_fresh_physical_path() -> void:
	await reset_fixture()
	var seat := await seat_player()
	giant._sense_remaining = 0.0
	giant.global_position = chassis.to_global(Vector3(-9, -1.226, -4))
	face(chassis.to_global(Vector3(0, 2.6, -4)))
	var slots: RVStructureSlots = chassis.get_node("StructureSlots")
	var roof := slots.panel("roof_0")
	var cabin_light: Item = chassis.get_node("CabinLightFront")
	var chassis_health: float = chassis.get_engine().health
	var smashed: Array[Node] = []
	var landed := func(target: Node, kind: String):
		if kind == "slender_speaker_smash": smashed.append(target)
	giant.attack_landed.connect(landed)
	var roof_open_time := -1.0
	var capture_time := -1.0
	var lift_completed := false
	var travel := {"samples": 0, "peak_lateral": 0.0, "lateral_ticks": 0, "longest_lateral_ticks": 0}
	for tick in 1800:
		await frames(1)
		var body_before: Transform3D = player.global_transform
		var view_before: Basis = seat.seat_camera.global_basis if player.seated_in == seat else player.camera.global_basis
		var giant_before := giant.global_position
		giant._physics_process(1.0 / 60.0)
		track_parked_travel(giant_before, travel)
		if roof.is_destroyed and roof_open_time < 0.0:
			roof_open_time = float(tick) / 60.0
			check(slots.panel("roof_1").can_operate() and slots.panel("roof_2").can_operate(), "Actual parked smash opens only roof above cab")
			check(chassis.get_engine().health == chassis_health, "Parked roof smash preserves exposed chassis health")
		if player.is_executing():
			player.set_physics_process(false)
			if capture_time < 0.0:
				capture_time = float(tick) / 60.0
				check(player.global_transform.is_equal_approx(body_before) and player.camera.global_basis.is_equal_approx(view_before),
					"Fresh parked ownership transfer preserves actual seated body and view before swept lift")
				check(roof.is_destroyed and slots.panel("left_0").can_operate(), "Actual grab reaches driver through opened roof with side shell intact")
				check(player.seated_in == null and seat.current_driver == null
					and player.camera.current and player.grab_control.execution_observer == null
					and not player.body_collision_shape.disabled, "Fresh parked capture transfers production seat, camera and full-body collision")
			player._physics_process(1.0 / 60.0)
			if giant.phase == SlenderSpeaker.Phase.HOLD and player.is_executing():
				lift_completed = true
		if player.is_player_dead: break
	check(roof_open_time >= 0.0 and smashed.has(roof), "Fresh CHASE approach reaches and destroys actual cab roof through physical smash sweep")
	check(capture_time > roof_open_time, "Fresh CHASE resumes after roof smash and captures driver through actual hand path")
	check(lift_completed and player.is_player_dead, "Fresh parked path collision-sweeps the survivor through lift, hold and fatal crush with fallen equipment present")
	check(is_instance_valid(cabin_light) and cabin_light.support_lost and cabin_light.collision_layer != 0
		and player.inventory.items.is_empty(), "Fresh parked execution retains real fallen equipment collision without fixture pickup")
	check(not smashed.has(slots.panel("roof_1")) and not smashed.has(slots.panel("roof_2")), "Actual parked sequence does not sweep unrelated roofs for access")
	check_parked_travel(travel, "fresh seated driver")
	print("PARKED_PHYSICAL_PATH roof_seconds=", roof_open_time, " capture_seconds=", capture_time,
		" giant=", giant.global_position, " phase=", giant.phase, " blocked=", giant._grab_blocking_hits)
	giant.attack_landed.disconnect(landed)
	giant._cancel_execution("fixture_reset")

func check_stop_from_approach(start: Vector3, label: String) -> void:
	await reset_fixture()
	await seat_player()
	giant.global_position = chassis.to_global(start)
	giant.reset_after_restore()
	giant._sense_remaining = 0.0
	giant._set_phase(SlenderSpeaker.Phase.PATROL)
	face(chassis.global_position)
	var acquired := false
	# Move actual production geometry and publish its contact-point velocity;
	# perception, navigation, collision and damage remain production behaviour.
	for tick in 120:
		chassis.linear_velocity = Vector3(0, 0, -4)
		chassis._road_speed = 4.0
		chassis.global_position += chassis.linear_velocity / 60.0
		# The survivor has fixture-owned physics; preserve the production seat
		# pose as the real vehicle transforms instead of leaving it behind.
		player._physics_process(1.0 / 60.0)
		await frames(1)
		giant._physics_process(1.0 / 60.0)
		acquired = acquired or (giant._visible_target and giant.target_vehicle == chassis)
	check(acquired, label + " moving RV is acquired through actual vision")
	chassis.linear_velocity = Vector3.ZERO
	chassis._road_speed = 0.0
	var roof: RVStructurePanel = chassis.get_node("StructureSlots").panel("roof_0")
	var opened := false
	var captured := false
	var roof_time := -1.0
	var capture_time := -1.0
	var search_ticks := 0
	var lost_vehicle := false
	var searched_attack := false
	var travel := {"samples": 0, "peak_lateral": 0.0, "lateral_ticks": 0, "longest_lateral_ticks": 0}
	for tick in 4200:
		await frames(1)
		var giant_before := giant.global_position
		giant._physics_process(1.0 / 60.0)
		track_parked_travel(giant_before, travel)
		lost_vehicle = lost_vehicle or giant.target_vehicle != chassis
		if giant.phase == SlenderSpeaker.Phase.SEARCH:
			search_ticks += 1
			searched_attack = searched_attack or not giant._action_context.is_empty()
		opened = opened or roof.is_destroyed
		if opened and roof_time < 0.0: roof_time = float(tick) / 60.0
		if player.is_executing():
			captured = true
			capture_time = float(tick) / 60.0
			break
	check(opened, label + " moving-to-stopped RV reaches physical cab roof attack with live sensing")
	check(captured, label + " moving-to-stopped RV reaches actual seated hand capture after opening its roof")
	check(not lost_vehicle, label + " moving-to-stopped encounter retains the same RV throughout the physical approach")
	check(not searched_attack, label + " brief sight loss searches observed geometry without authorizing a hidden attack")
	check_parked_travel(travel, label)
	print("STOP_RESULT ", label, " opened=", opened, " captured=", captured, " search_ticks=", search_ticks,
		" roof_seconds=", roof_time, " capture_seconds=", capture_time,
		" giant=", giant.global_position, " phase=", giant.phase, " plan=", giant._parked_plan,
		" blocked=", giant._grab_blocking_hits, " chassis=", chassis.global_position,
		" player_contact=", player.execution_contact_position(), " visible=", giant._visible_target,
		" player_target=", giant.target_player, " memory=", giant._parked_approach_memory)

func check_vehicle_sight_contract() -> void:
	await reset_fixture()
	await seat_player()
	giant.global_position = Vector3(-10, 0, 0)
	face(chassis.global_position)
	giant.reset_after_restore()
	refresh_encounter()
	check(giant._visible_target and giant.target_vehicle == chassis,
		"Forgotten parked RV is reacquired through actual visible shell")
	giant.rotation.y += PI
	giant._sample("idle_play", 0.0)
	refresh_encounter()
	check(not giant._visible_target and giant._observation.get("vehicle") == null
		and giant.target_vehicle == chassis,
		"Vehicle surface sampling loses RV behind the cone while persistent identity remains")
	face(chassis.global_position)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 30, 30)
	collision.shape = box
	wall.add_child(collision)
	wall.position = Vector3(-5, 15, 0)
	world.add_child(wall)
	await frames(3)
	refresh_encounter()
	check(not giant._visible_target and giant._observation.get("vehicle") == null
		and giant.target_vehicle == chassis,
		"Vehicle surface sampling cannot see through real opaque wall while retaining encounter identity")
	wall.queue_free()
	await frames(3)
	refresh_encounter()
	check(giant._visible_target and giant.target_vehicle == chassis,
		"Opening actual line of sight reacquires parked RV without engine motion or seeded lock")

func check_parked_approach_memory() -> void:
	await reset_fixture()
	await seat_player()
	giant.global_position = Vector3(-12, 0, 0)
	face(chassis.global_position)
	giant._sense_remaining = 0.0
	for tick in 60:
		await frames(1)
		giant._physics_process(1.0 / 60.0)
		if not giant._parked_approach_memory.is_empty(): break
	check(giant._visible_target and not giant._parked_approach_memory.is_empty(),
		"Real visible parked pursuit records an observed approach waypoint")
	if giant._parked_approach_memory.is_empty(): return
	var remembered: Dictionary = giant._parked_approach_memory.duplicate()
	var seen_before := giant.last_seen_position
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 30, 100)
	collision.shape = box
	wall.add_child(collision)
	wall.position = Vector3(-5, 15, 0)
	world.add_child(wall)
	await frames(3)
	# Publish a changed real parked RV/player transform entirely behind the
	# wall. The remembered route must retain only its last observed geometry.
	chassis.global_position.z += 20.0
	player._physics_process(1.0 / 60.0)
	await frames(3)
	refresh_encounter()
	giant._physics_process(1.0 / 60.0)
	check(not giant._visible_target and giant.target_vehicle == chassis and giant._parked_plan.is_empty(),
		"Opaque wall removes live parked perception and attack plan")
	for tick in 30:
		await frames(1)
		giant._physics_process(1.0 / 60.0)
	check(giant.phase == SlenderSpeaker.Phase.SEARCH and not giant._parked_approach_memory.is_empty()
		and giant._encounter_decision.get("intent") == "search",
		"Short parked sight loss searches through the bounded observed approach")
	check(giant._parked_approach_memory.get("navigation_point") == remembered.navigation_point
		and giant._parked_approach_memory.get("surface_point") == remembered.surface_point
		and giant._parked_approach_memory.get("standoff_point") == remembered.standoff_point
		and giant._parked_approach_memory.get("route_frame") == remembered.route_frame
		and giant._parked_approach_memory.get("route_shell") == remembered.route_shell
		and giant.last_seen_position == seen_before,
		"Hidden moved RV cannot update the remembered route geometry, stance, surface or last seen position")
	var slots: RVStructureSlots = chassis.get_node("StructureSlots")
	for tick in int(ceil((giant.settings.search_seconds + 1.0) * 60.0)):
		await frames(1)
		giant._physics_process(1.0 / 60.0)
	check(giant.phase == SlenderSpeaker.Phase.PATROL and not giant._visible_target
		and giant._encounter_decision.get("intent") == "none",
		"Unseen parked encounter expires its search and returns to ordinary patrol")
	check(not player.is_grabbed() and slots.panel("roof_0").can_operate(),
		"Frozen approach memory cannot authorize a hidden roof strike or occupant capture")
	wall.queue_free()
	await frames(3)
	giant.reset_after_restore()
	check(giant._parked_approach_memory.is_empty(), "Restore clears parked approach memory")

func check_cached_occupant_cone_loss() -> void:
	await reset_fixture()
	await seat_player()
	var slots: RVStructureSlots = chassis.get_node("StructureSlots")
	slots.panel("roof_0").take_damage(slots.panel("roof_0").current_health)
	giant.global_position = chassis.to_global(Vector3(-9, -1.226, -4))
	face(player.execution_contact_position())
	await frames(3)
	refresh_encounter()
	check(giant.can_see_player(player) and giant.target_player == player,
		"Cached sight fixture observes the real seated survivor through its roof opening")
	# Classify the stationary RV before this single-frame perception race.
	parked_plan()
	for tick in 60:
		giant._physics_process(1.0 / 60.0)
		if not giant._parked_approach_memory.is_empty(): break
	var remembered: Dictionary = giant._parked_approach_memory.duplicate()
	check(not remembered.is_empty() and remembered.get("occupant_id") == player.get_instance_id(),
		"Observed survivor records a real parked grab approach")
	if remembered.is_empty(): return
	var last_observed: Vector3 = giant._encounter_decision.point
	# Body turning changes the real cone immediately, between the controller's
	# normal 0.1s perception samples. Its cached target is intentionally valid.
	giant.rotation.y += PI
	giant._sample("idle_play", 0.0)
	giant._sense_remaining = .1
	check(giant._visible_target and giant.target_player == player and not giant.can_see_player(player),
		"Body turn loses the survivor's actual cone while its previous sight sample is still cached")
	giant._physics_process(1.0 / 60.0)
	check(giant._parked_plan.get("smash_kind") == "cabin_memory" and giant._parked_plan.get("occupant") == null
		and giant._parked_plan.get("roof") == null
		and giant._parked_plan.get("surface_point", Vector3.INF).is_equal_approx(last_observed),
		"Between sight samples, lost cabin occupant cone approaches its exact last observed point without selecting another roof or a hidden grab")
	check(giant.phase == SlenderSpeaker.Phase.CHASE and not player.is_grabbed()
		and slots.panel("roof_1").can_operate(), "Cached sight race approaches cabin memory without blind capture or unrelated roof removal")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_collision)
	world.add_child(floor_body)
	giant = GIANT.instantiate()
	world.add_child(giant)
	giant.set_physics_process(false)
	player = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-100, 0, -100), Vector3(-100, 0, 100), Vector3(100, 0, 100), Vector3(100, 0, -100)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)
	region.set_navigation_map(map)
	giant.set_giant_navigation_map(map)
	await frames(3)
	NavigationServer3D.map_force_update(map)
	await check_roof_selection()
	await check_nearest_unknown_roofs()
	await check_remembered_open_cabin_plan()
	await check_restart()
	await check_fresh_physical_path()
	await check_vehicle_sight_contract()
	await check_parked_approach_memory()
	await check_cached_occupant_cone_loss()
	await check_stop_from_approach(Vector3(0, -1.226, 16), "rear")
	await check_stop_from_approach(Vector3(10, -1.226, 8), "right")
	giant.set_giant_navigation_map(RID())
	NavigationServer3D.free_rid(map)
	world.queue_free()
	await frames()
	if failures.is_empty(): print("PASS: Slender Speaker parked roof selection, occupant access, restart and fresh physical attack path")
	quit(0 if failures.is_empty() else 1)
