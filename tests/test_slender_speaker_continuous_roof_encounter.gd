extends SceneTree
## Complete live free-play encounters: an intermediate roof removal is not success.
const Wait := preload("res://tests/support/test_wait.gd")
const ParkedAttack := preload("res://enemies/slender_speaker/slender_speaker_parked_attack.gd")
var stage: Node3D
var failures: Array[String] = []

func _init() -> void: run.call_deferred()

func frames(count := 1) -> void:
	for tick in count: await physics_frame

func check(ok: bool, note: String) -> void:
	if not ok:
		failures.append(note)
		push_error("FAIL: " + note)

func observation() -> Dictionary:
	var giant: SlenderSpeaker = stage.giant
	var rv: Chassis = stage.rv
	return {"phase": SlenderSpeaker.Phase.keys()[giant.phase], "speed_kmh": rv.road_speed() * 3.6,
		"player_local": str(rv.to_local(stage.player.global_position)), "roof": str(giant._parked_plan.get("roof")),
		"gap": giant._parked_plan.get("gap", -1.0), "ready": giant._parked_plan.get("can_attack", false),
		"player_visible": giant._encounter_decision.get("player_visible", false),
		"intent": giant._encounter_decision.get("intent", "none"), "memory": giant._encounter._remaining,
		"last_local": str(rv.to_local(giant._encounter_decision.get("point", Vector3.ZERO))),
		"search_local": str(rv.to_local(giant._encounter_decision.get("search_point", Vector3.ZERO))),
		"suppressed": str(giant._encounter._suppressed_vehicle), "contact": str(giant._strike_contact_collider)}

func release_movement() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right"]: Input.action_release(action)

func walk_from_driver_to_middle() -> void:
	await walk_from_driver_to(0.0)

func walk_from_driver_to(target_z: float) -> void:
	# These are normal seat and locomotion inputs; no player transform writes.
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_SPACE
		key.pressed = pressed
		Input.parse_input_event(key)
		await frames(2)
	stage.set_giant_enabled(true)
	await frames(60)
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = "interact"
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)
	# Native rendering may batch several physics ticks before dispatching input.
	# Observe completion of the real event instead of asserting after two ticks.
	var exited := await Wait.until(self, func() -> bool: return stage.player.seated_in == null, 2000)
	check(exited, "Normal interaction exits the real driver seat")
	var waypoints: Array[Vector3] = [Vector3(0, 0, -1.5), Vector3(0, 0, 0)]
	if not is_zero_approx(target_z): waypoints.append(Vector3(0, 0, target_z))
	for target in waypoints:
		for tick in 300:
			var difference: Vector3 = (stage.rv.to_global(target) - stage.player.global_position).slide(Vector3.UP)
			if difference.length() < .15: break
			var local: Vector3 = stage.player.global_basis.inverse() * difference
			release_movement()
			if absf(local.x) > .08: Input.action_press("move_right" if local.x > 0 else "move_left")
			if absf(local.z) > .08: Input.action_press("move_back" if local.z > 0 else "move_forward")
			await frames()
		release_movement()
	var local: Vector3 = stage.rv.to_local(stage.player.global_position)
	check(Vector2(local.x, local.z - target_z).length() < .2, "Normal movement walks from the driver seat to aisle z=" + str(target_z))
	print("CONTINUOUS_ROOF_WALK ", JSON.stringify(observation()))

func encounter(label: String, z: float, normal_walk := false) -> void:
	var player: CharacterBody3D = stage.player
	var rv: Chassis = stage.rv
	var giant: SlenderSpeaker = stage.giant
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	check(stage.mode == 0 and not rv.freeze and rv.control_override.is_empty(), label + " uses production free-play suspension")
	for id in ["roof_0", "roof_1", "roof_2"]:
		check(not slots.panel(id).is_destroyed, label + " starts with intact " + id)
	var initial_engine_health := rv.get_engine().health
	var contacts := {"roofs": {}, "chassis": 0, "pending_roof": null, "lost_after_hit": false}
	giant.attack_landed.connect(func(collider: Node, _kind: String) -> void:
		if collider == rv: contacts.chassis += 1
		if collider is RVStructurePanel and collider.mount_slot.begins_with("roof_"):
			contacts.roofs[collider.mount_slot] = int(contacts.roofs.get(collider.mount_slot, 0)) + 1
			contacts.pending_roof = collider if not collider.is_destroyed else null)
	if normal_walk:
		await walk_from_driver_to(z)
	else:
		player.seated_in.exit_seat(true)
		player.global_position = rv.to_global(Vector3(0, .3, z))
		player.rotation.y = rv.rotation.y
		await frames(120)
		rv.set_handbrake(false)
	stage.set_giant_enabled(true)
	var start := Engine.get_physics_frames()
	var previous := -1
	var reached_hold := false
	var wrong_smash := false
	while Engine.get_physics_frames() - start < 3600:
		await frames()
		if is_instance_valid(contacts.pending_roof) and not contacts.pending_roof.is_destroyed and giant.target_vehicle != rv:
			contacts.lost_after_hit = true
		if giant.phase == SlenderSpeaker.Phase.SMASH and giant._action_context.get("kind") != "roof": wrong_smash = true
		if previous != giant.phase or (Engine.get_physics_frames() - start) % 300 == 0:
			print("CONTINUOUS_ROOF ", label, " t=", float(Engine.get_physics_frames() - start) / 60.0, " ", JSON.stringify(observation()))
		previous = giant.phase
		if giant.phase == SlenderSpeaker.Phase.HOLD:
			reached_hold = true
			break
	print("CONTINUOUS_ROOF_RESULT ", label, " hold=", reached_hold, " physical_contacts=", contacts, " ", JSON.stringify(observation()))
	check(reached_hold and player.is_executing(), label + " completes physical roof removal, capture and lift to HOLD within sixty seconds")
	check(not contacts.lost_after_hit, label + " retains the encounter after a first 60-damage hit while that roof remains intact")
	check(not wrong_smash and contacts.chassis == 0 and is_equal_approx(rv.get_engine().health, initial_engine_health), label + " never falls back to chassis assault")
	check(not contacts.roofs.is_empty(), label + " removes a roof through actual hand contact")
	for id in ["roof_0", "roof_1", "roof_2"]:
		if slots.panel(id).is_destroyed: check(int(contacts.roofs.get(id, 0)) >= 2, label + " removes each 120-health roof through at least two physical 60-damage hits: " + id)
	if is_zero_approx(z):
		check(not slots.panel("roof_0").is_destroyed and not slots.panel("roof_2").is_destroyed, label + " preserves roofs unrelated to the central survivor")
	check(not rv.handbrake, label + " keeps the handbrake released throughout")
	finish_encounter()

func finish_encounter() -> void:
	stage.set_giant_enabled(false)

func face(point: Vector3) -> void:
	var giant: SlenderSpeaker = stage.giant
	var direction := (point - giant.global_position).slide(Vector3.UP).normalized()
	giant.rotation.y = atan2(-direction.x, -direction.z)
	giant._sample("idle_play", 0.0)

func point_on_roof(roof: RVStructurePanel, point: Vector3) -> bool:
	for node in roof.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		if shape.disabled or not shape.shape is BoxShape3D: continue
		var local: Vector3 = shape.to_local(point)
		var half: Vector3 = shape.shape.size * .5
		if absf(local.x) <= half.x + .01 and absf(local.z) <= half.z + .01 and absf(local.y) <= half.y + .01: return true
	return false

func hatch_geometry() -> void:
	var rv: Chassis = stage.rv
	var giant: SlenderSpeaker = stage.giant
	var player: CharacterBody3D = stage.player
	player.seated_in.exit_seat(true)
	player.global_position = rv.to_global(Vector3(0, .3, 0))
	await frames(120)
	player.set_physics_process(false)
	var roofs: RVStructureSlots = rv.get_node("StructureSlots")
	for side in [-1.0, 1.0]:
		giant.global_position = rv.to_global(Vector3(side * 4.8, 0, 0))
		giant.global_position.y = .02
		face(player.execution_contact_position())
		var planner := ParkedAttack.new()
		var seed: Dictionary = planner.update(giant, rv, 0.0)
		var frame: Transform3D = seed.route_frame
		var shell: AABB = seed.route_shell
		planner._side = side
		# Right-side roof sight can hide this torso. Probe observed physical roof
		# geometry directly without inventing survivor visibility or AI intent.
		var surface: Vector3 = planner._roof_surface(roofs.panel("roof_1"), planner._roof_bounds(rv, frame), shell, 0.0)
		check(surface != Vector3.INF, "Hatch has a reachable physical strike surface on side " + str(side))
		if surface == Vector3.INF: continue
		var edge: float = shell.position.x if side < 0 else shell.end.x
		var stance := Vector3(edge + side * 2.8, 0, surface.z)
		var distance := stance.distance_to(surface.slide(Vector3.UP))
		print("CONTINUOUS_HATCH_GEOMETRY side=", side, " stance_gap=", distance, " surface=", frame * surface)
		check(distance <= 3.5, "Hatch target remains reachable from its committed exterior stance on side " + str(side))
		check(point_on_roof(roofs.panel("roof_1"), frame * surface), "Hatch target lies on a real collider rather than its empty opening on side " + str(side))
	# A survivor through the roof aperture, and a walker above the roof, have no
	# roof over their torso. Neither may trigger removal of unrelated support.
	for location in [Vector3(-1.1, .3, 0), Vector3(0, 3.1, 0)]:
		player.global_position = rv.to_global(location)
		await frames(2)
		giant.global_position = rv.to_global(Vector3(-3.3, 0, 0))
		giant.global_position.y = .02
		face(player.execution_contact_position())
		check(giant.can_see_player(player), "Geometry probe observes aperture/roof survivor " + str(location))
		var plan: Dictionary = ParkedAttack.new().update(giant, rv, 0.0, player)
		check(plan.get("roof") == null, "Aperture/roof survivor does not authorize unrelated roof removal " + str(location))
	# Isolated suspension-roll geometry checks retain one committed middle roof
	# across updates. Small rolls must refresh its true solid top-face target.
	rv.freeze = true
	rv.rotation.z = 0.0
	await frames(2)
	giant.global_position = rv.to_global(Vector3(-4.8, 0, 0))
	giant.global_position.y = .02
	face(rv.to_global(Vector3(0, 3, 0)))
	var cached := ParkedAttack.new()
	cached.update(giant, rv, 0.0)
	cached._roof_id = roofs.panel("roof_1").get_instance_id()
	cached._committed_stance = Vector3.INF
	var initial: Dictionary = cached.update(giant, rv, 0.0)
	check(initial.get("roof") == roofs.panel("roof_1") and point_on_roof(roofs.panel("roof_1"), initial.surface_point), "Committed hatch plan begins on a solid physical surface")
	for degrees in [.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
		rv.rotation.z = deg_to_rad(degrees)
		await frames(2)
		var plan: Dictionary = cached.update(giant, rv, 0.0)
		check(plan.get("roof") == roofs.panel("roof_1"), "Small suspension roll preserves committed physical hatch roof at " + str(degrees) + " degrees")
		if plan.has("surface_point"):
			check(point_on_roof(roofs.panel("roof_1"), plan.surface_point), "Cached roof target follows its actual solid shape during " + str(degrees) + " degree suspension roll")
		else:
			check(false, "Committed hatch plan retains a physical surface through small suspension roll")
	# A static pitch must not accumulate projection corrections into a moving
	# longitudinal target. Repeated planner updates keep the same physical roof
	# and body stance while continuing to aim at solid geometry.
	rv.rotation.z = 0.0
	for degrees in [-3.0, 3.0]:
		rv.rotation.x = deg_to_rad(degrees)
		await frames(2)
		cached._committed_stance = Vector3.INF
		var pitched: Dictionary = cached.update(giant, rv, 0.0)
		check(pitched.get("roof") == roofs.panel("roof_1") and pitched.has("surface_point"), "Static pitch starts with the committed middle roof at " + str(degrees) + " degrees")
		if not pitched.has("surface_point"): continue
		var original_surface: Vector3 = pitched.surface_point
		var original_stance: Vector3 = pitched.standoff_point
		var frame: Transform3D = pitched.route_frame
		var max_longitudinal_drift := 0.0
		var max_stance_drift := 0.0
		var solid := true
		var retained := true
		for tick in 600:
			pitched = cached.update(giant, rv, 1.0 / 60.0)
			if pitched.get("roof") != roofs.panel("roof_1") or not pitched.has("surface_point"):
				retained = false
				break
			var local_drift: Vector3 = frame.basis.inverse() * (Vector3(pitched.surface_point) - original_surface)
			max_longitudinal_drift = maxf(max_longitudinal_drift, absf(local_drift.z))
			max_stance_drift = maxf(max_stance_drift, Vector3(pitched.standoff_point).distance_to(original_stance))
			solid = solid and point_on_roof(roofs.panel("roof_1"), pitched.surface_point)
		print("CONTINUOUS_HATCH_PITCH degrees=", degrees, " longitudinal_drift=", max_longitudinal_drift, " stance_drift=", max_stance_drift)
		check(retained and solid, "Repeated cached pitch updates retain a solid target on the same middle roof at " + str(degrees) + " degrees")
		check(max_longitudinal_drift <= .02 and max_stance_drift <= .001, "Ten seconds of cached static pitch cannot move the roof target or body stance at " + str(degrees) + " degrees")
	for id in ["roof_0", "roof_1", "roof_2"]: check(not roofs.panel(id).is_destroyed, "Geometry probes preserve " + id)

func run() -> void:
	stage = load("res://tests/slender_speaker_playground.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	var ready := await Wait.until(self, func() -> bool: return stage.running, 60000, true)
	check(ready, "Production playground starts")
	if ready:
		await encounter("MIDDLE", 0.0)
		await stage.select_mode(0)
		await encounter("REAR", 4.0)
		await stage.select_mode(0)
		await encounter("DRIVER_WALK_MIDDLE", 0.0, true)
		await stage.select_mode(0)
		await encounter("DRIVER_WALK_REAR", 4.0, true)
		await stage.select_mode(0)
		await hatch_geometry()
	stage.queue_free()
	await frames(3)
	if failures.is_empty(): print("PASS: complete middle and rear free-play roof encounters reach HOLD through physical contact, with reachable solid hatch targets")
	quit(0 if failures.is_empty() else 1)
