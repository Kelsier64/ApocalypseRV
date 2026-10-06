extends SceneTree
## Real Item, player input and production RV collision routes.
var failures: Array[String] = []
var world: Node3D
var rv: Node3D
var player: CharacterBody3D
var dt := 1.0 / Engine.physics_ticks_per_second

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)

func movement_detail(ladder: Node3D, frame: int, before_state: int, before_phase: int, before: Vector3, limit: float) -> String:
	return " ladder=%s frame=%d state=%d->%d phase=%d->%d delta=%s distance=%.6f limit=%.6f dt=%.6f" % [ladder.name, frame, before_state, player.locomotion_state, before_phase, player.ladder_transition, player.global_position - before, player.global_position.distance_to(before), limit, dt]

func tick(count: int = 1) -> void:
	for frame in count:
		await physics_frame
		player._physics_process(dt)

func release_inputs() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump"]:
		Input.action_release(action)

func reset(ladder: Node3D, descending: bool = false) -> void:
	release_inputs()
	player._exit_climb_to_normal()
	player.climb_reenter_cooldown_remaining = 0.0
	player.rv_support.clear()
	player.velocity = Vector3.ZERO
	player.released_carrier_velocity = Vector3.ZERO
	var feet: Vector3 = ladder.top_landing_point() if descending else ladder.climb_point(0.0)
	player.global_position = feet - Vector3.UP * .25
	player.global_rotation = Vector3(0, ladder.global_rotation.y, 0)
	await physics_frame

func top_exit_action(ladder: Node3D) -> String:
	var to_floor: Vector3 = (ladder.top_landing_point() - player._climb_feet()).slide(Vector3.UP)
	return "move_forward" if to_floor.dot(-player.global_basis.z) > 0.0 else "move_back"

func traverse(ladder: Node3D, descending: bool = false) -> bool:
	await reset(ladder, descending)
	Input.action_press("move_back" if descending else "move_forward")
	var entered := false
	var finished := false
	var steered := false
	for frame in 240:
		if not descending and not steered and player.ladder_transition == player.LadderTransition.TOP:
			release_inputs()
			await tick()
			Input.action_press(top_exit_action(ladder))
			steered = true
		var before: Vector3 = player.global_position
		var phase: int = player.ladder_transition
		var before_state: int = player.locomotion_state
		await tick()
		var allowed_speed: float = player.SPEED if phase == player.LadderTransition.TOP else (1.4 if phase != player.LadderTransition.NONE else 1.6)
		# Before attachment, the production controller first walks normally.
		if frame == 0 and before_state == player.LocomotionState.NORMAL: allowed_speed = player.SPEED
		var epsilon := .006 if phase == player.LadderTransition.LANDING and player.locomotion_state == player.LocomotionState.NORMAL else .002
		var limit := allowed_speed * dt + epsilon
		check(player.global_position.distance_to(before) <= limit, "Entry, climbing and landing respect the per-frame movement budget:" + movement_detail(ladder, frame, before_state, phase, before, limit))
		entered = entered or player.locomotion_state == player.LocomotionState.CLIMBING
		if entered and player.locomotion_state == player.LocomotionState.NORMAL:
			finished = true
			break
	release_inputs()
	check(entered, str(ladder.name) + " accepts " + ("upper S entry" if descending else "lower W entry"))
	check(finished, str(ladder.name) + " completes " + ("descent" if descending else "ascent") + ": feet=" + str(ladder.to_local(player._climb_feet())))
	check(not player.body_collision_shape.disabled, "Route keeps the player capsule enabled")
	if finished:
		var local_feet: Vector3 = ladder.to_local(player._climb_feet())
		check(absf(local_feet.y - (0.0 if descending else ladder.climb_height)) < .15, "Route ends at the intended standing level")
		if not descending:
			check(steered and player.is_on_floor(), "Manual top exit reaches a real supported floor")
	return finished

func entry_rejections(ladder: Node3D) -> void:
	for local_offset in [Vector3(.4, 0, 0), Vector3(0, 0, .4)]:
		await reset(ladder)
		player.global_position += ladder.global_basis * local_offset
		await physics_frame
		var before: Transform3D = player.global_transform
		check(not ladder.can_enter_from(player._climb_feet(), false), "A distant or sideways approach lies outside the close entry region")
		Input.action_press("move_forward")
		player._try_start_climb()
		check(player.locomotion_state == player.LocomotionState.NORMAL and player.global_transform.is_equal_approx(before), "W cannot magnetically catch a distant or sideways ladder")
		release_inputs()
	await reset(ladder)
	player.rotate_y(PI / 4)
	var before: Transform3D = player.global_transform
	Input.action_press("move_forward")
	player._try_start_climb()
	check(player.locomotion_state == player.LocomotionState.NORMAL and player.global_transform.is_equal_approx(before), "A 45-degree passing approach cannot grab the ladder")
	release_inputs()
	await reset(ladder, true)
	player.global_position += ladder.global_basis.z * .4
	await physics_frame
	before = player.global_transform
	check(not ladder.can_enter_from(player._climb_feet(), true), "Upper entry requires close contact with the authored landing edge")
	Input.action_press("move_back")
	player._try_start_climb()
	check(player.locomotion_state == player.LocomotionState.NORMAL and player.global_transform.is_equal_approx(before), "S cannot grab the ladder from a distant rooftop position")
	release_inputs()
	for descending in [false, true]:
		await reset(ladder, descending)
		before = player.global_transform
		Input.action_press("move_forward")
		Input.action_press("move_back")
		player._try_start_climb()
		check(player.locomotion_state == player.LocomotionState.NORMAL and player.global_transform.is_equal_approx(before), "Opposing W/S input cannot start attachment at either end")
		release_inputs()

func entry_motion(ladder: Node3D, descending: bool = false, lower_height_offset: float = 0.0) -> void:
	await reset(ladder, descending)
	if not descending:
		player.global_position += ladder.global_basis * Vector3(.12, lower_height_offset, .18)
		await physics_frame
	var before: Transform3D = player.global_transform
	check(player.begin_ladder_climb(ladder, descending), "Close deliberate entry is accepted")
	check(player.global_transform.is_equal_approx(before), "Beginning ladder attachment never moves or rotates the player synchronously")
	check(player.ladder_transition == player.LadderTransition.ENTRY, "Attachment queues the entry phase")
	var action := "move_back" if descending else "move_forward"
	Input.action_press(action)
	for frame in 2:
		var position_before: Vector3 = player.global_position
		await tick()
		check(player.global_position.distance_to(position_before) <= 1.4 * dt + .002, "Entry alignment moves at a bounded speed")
	check(player.global_position.distance_to(before.origin) > .005, "Held entry input advances the gradual alignment")
	release_inputs()
	var paused: Vector3 = player.global_position
	await tick(6)
	check(player.global_position.distance_to(paused) < .001, "Releasing entry input pauses attachment motion")
	Input.action_press(action)
	for frame in 120:
		if player.ladder_transition == player.LadderTransition.NONE: break
		var position_before: Vector3 = player.global_position
		await tick()
		check(player.global_position.distance_to(position_before) <= 1.4 * dt + .002, "Resumed entry stays within the per-frame transition budget")
	release_inputs()
	check(player.locomotion_state == player.LocomotionState.CLIMBING and player.ladder_transition == player.LadderTransition.NONE, "Entry finishes on a stable rung without an instantaneous transfer")
	player._abort_climb("entry test complete")

func reach_top_transition(ladder: Node3D) -> bool:
	await reset(ladder)
	Input.action_press("move_forward")
	for frame in 180:
		var before: Vector3 = player.global_position
		var before_state: int = player.locomotion_state
		var before_phase: int = player.ladder_transition
		await tick()
		var limit: float = (player.SPEED if before_state == player.LocomotionState.NORMAL else 1.6) * dt + .002
		check(player.global_position.distance_to(before) <= limit, "Vertical climb cannot jump directly to the floor:" + movement_detail(ladder, frame, before_state, before_phase, before, limit))
		if player.ladder_transition == player.LadderTransition.TOP: return true
	check(false, "Top fixture reaches the upper rung")
	release_inputs()
	return false

func landing_motion(ladder: Node3D) -> void:
	if not await reach_top_transition(ladder): return
	var top: Vector3 = player.global_position
	await tick(35)
	check(player.ladder_transition == player.LadderTransition.TOP and player.global_position.distance_to(top) < .001, "Continued ascent W stops at the top without any forward shove")
	check(not player.ladder_top_input_ready, "Held ascent input cannot become automatic top walking")
	release_inputs()
	await tick(6)
	check(player.global_position.distance_to(top) < .001 and player.ladder_top_input_ready, "Neutral input holds the top rung and enables deliberate walking")
	Input.action_press(top_exit_action(ladder))
	var settled := false
	var manual_frames := 0
	for frame in 120:
		var before: Vector3 = player.global_position
		var phase: int = player.ladder_transition
		await tick()
		var motion: Vector3 = player.global_position - before
		var limit: float = (player.SPEED if phase == player.LadderTransition.TOP else 1.4) * dt + .006
		check(motion.length() <= limit, "Manual exit and floor settling respect their movement budgets")
		if phase == player.LadderTransition.TOP: manual_frames += 1
		if player.ladder_transition == player.LadderTransition.LANDING:
			settled = true
			release_inputs()
		if phase == player.LadderTransition.LANDING:
			check(motion.slide(Vector3.UP).length() < .001, "Real-floor landing only settles vertically without horizontal attraction")
		if player.locomotion_state == player.LocomotionState.NORMAL: break
	release_inputs()
	check(manual_frames > 3, "Leaving the upper rung requires deliberate walking over multiple frames")
	check(settled and player.locomotion_state == player.LocomotionState.NORMAL and player.is_on_floor(), "Manual steering reaches a real floor and automatic vertical settling finishes even after input release")
	check(absf(ladder.to_local(player._climb_feet()).y - ladder.climb_height) < .15, "Manual exit stands at the actual cabin or roof level")
	await reset(ladder, true)
	check(player.begin_ladder_climb(ladder, true), "Upper entry can be cancelled safely")
	Input.action_press("jump")
	await tick()
	release_inputs()
	check(player.active_climb_ladder == null and player.locomotion_state == player.LocomotionState.NORMAL, "Space detaches during queued entry")

func manual_top_controls(ladder: Node3D) -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		if not await reach_top_transition(ladder): return
		release_inputs()
		await tick()
		player.rotate_y(.2)
		var before: Vector3 = player.global_position
		var input := Vector3.ZERO
		match action:
			"move_forward": input = -player.global_basis.z
			"move_back": input = player.global_basis.z
			"move_left": input = -player.global_basis.x
			"move_right": input = player.global_basis.x
		Input.action_press(action)
		await tick()
		var motion: Vector3 = (player.global_position - before).slide(Vector3.UP)
		check(motion.length() <= player.SPEED * dt + .002, "Manual " + action + " obeys ordinary movement speed")
		check(motion.length() < .001 or (motion.dot(input) > 0.0 and motion.slide(input).length() < .002), "Manual " + action + " follows current player facing without steering toward an authored target")
		if action in ["move_left", "move_right"]:
			check(motion.length() > .03, "Lateral TOP input produces deliberate movement")
		release_inputs()
		var paused: Vector3 = player.global_position
		await tick(6)
		check(player.global_position.distance_to(paused) < .001, "Releasing manual top walking pauses without residual attraction")
	if not await reach_top_transition(ladder): return
	Input.action_press("jump")
	await tick()
	release_inputs()
	check(player.locomotion_state == player.LocomotionState.NORMAL and player.active_climb_ladder == null and player.ladder_transition == player.LadderTransition.NONE, "Space releases the held upper rung and clears attachment")

func unsupported_top_exit(ladder: Node3D) -> void:
	if not await reach_top_transition(ladder): return
	var top_height: float = player._climb_feet().y
	release_inputs()
	await tick()
	# The short ladder's backward direction leads outside the cabin into air.
	Input.action_press("move_back")
	for frame in 40:
		await tick()
		if player.locomotion_state == player.LocomotionState.NORMAL: break
	release_inputs()
	check(player.locomotion_state == player.LocomotionState.NORMAL and player.active_climb_ladder == null and not player.ladder_landed, "Walking beyond top reach without a floor releases the ladder instead of choosing a distant landing")
	await tick(25)
	check(player._climb_feet().y < top_height - .2, "Unsupported manual top exit falls under actual gravity")

func aim_at(contact: Vector3, normal: Vector3, distance: float = 2.0) -> void:
	player.camera.rotation = Vector3.ZERO
	if absf(normal.dot(Vector3.UP)) < .95:
		player.global_basis = Basis.looking_at(-normal, Vector3.UP)
	player.global_position = contact + normal * distance - player.global_basis * player.camera.position
	player.camera.look_at(contact, Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > .95 else Vector3.UP)
	await physics_frame

func aimed_hit(ladder: Node3D) -> Dictionary:
	var start: Vector3 = player.camera.global_position
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, start - player.camera.global_basis.z * player.placement.max_place_distance, 0xFFFFFFFF, [player.get_rid(), ladder.get_rid()]))

func preview_preserves_contact(ladder: Node3D, hit: Dictionary) -> void:
	check(not hit.is_empty(), "Placement camera intersects an actual support")
	if hit.is_empty(): return
	var normal: Vector3 = hit.normal
	var bounds: AABB = ladder.get_placement_bounds()
	var center: Vector3 = ladder.global_transform * bounds.get_center()
	check((center - hit.position).slide(normal).length() < .001, "Free placement preserves the actual aimed contact in both wall directions")
	check(ladder.global_basis.y.dot(rv.global_basis.y) > .99 and ladder.global_basis.z.dot(normal) > .99, "Ladder is upright with its climb plane parallel to the actual wall")
	var back: Vector3 = ladder.to_global(Vector3(bounds.get_center().x, bounds.get_center().y, bounds.position.z))
	check(absf((back - hit.position).dot(normal) - .012) < .001, "Ladder back clears the actual wall surface by the ordinary placement margin")

func fixed_ladder(identity: String) -> Node3D:
	for item in get_nodes_in_group(Groups.ITEMS):
		if item is RVLadder and item.persistent_id == identity and item.is_fixed and not item.is_queued_for_deletion(): return item
	return null

func exercise_free_wall_placement(ladder: Node3D, contact: Vector3, normal: Vector3, support: Node3D) -> Node3D:
	await aim_at(contact, normal)
	var identity: String = ladder.persistent_id
	check(ladder.pickup(player).contains("已拾取"), "Wall ladder transfers to large inventory")
	check(player.enter_equipment_placement(), "Wall ladder enters ordinary Item placement")
	ladder = player.placement.placing_equipment
	check(ladder.presentation_only and ladder.is_being_placed, "Wall ladder preview is separate from inventory-owned hands")
	for mode in range(2):
		await aim_at(contact, normal)
		var first_hit := aimed_hit(ladder)
		check(first_hit.get("collider") == support, "Camera targets the intended real mounting wall")
		player.placement.update_ghost(player)
		check(player.placement.can_place_equipment, "Wall preview is valid in placement mode " + str(mode) + ": " + player.placement.message)
		preview_preserves_contact(ladder, first_hit)
		var first_position: Vector3 = ladder.global_position
		await aim_at(contact + rv.global_basis.z * .1, normal)
		var second_hit := aimed_hit(ladder)
		player.placement.update_ghost(player)
		check(player.placement.can_place_equipment, "Nearby wall hit remains freely placeable")
		preview_preserves_contact(ladder, second_hit)
		if not first_hit.is_empty() and not second_hit.is_empty():
			var contact_delta: Vector3 = second_hit.position - first_hit.position
			check(contact_delta.length() > .09 and (ladder.global_position - first_position).distance_to(contact_delta) < .001, "Two nearby camera hits produce corresponding continuous placement positions")
		var before_nudge: Vector3 = ladder.global_position
		var nudge := InputEventKey.new()
		nudge.pressed = true
		nudge.physical_keycode = KEY_RIGHT
		player.placement.handle_input(player, nudge)
		player.placement.update_ghost(player)
		check(player.placement.can_place_equipment and is_equal_approx(ladder.global_position.distance_to(before_nudge), .05), "Arrow input fine-tunes the actual wall placement by 5 cm")
		nudge.physical_keycode = KEY_LEFT
		player.placement.handle_input(player, nudge)
		player.placement.update_ghost(player)
		if mode == 0:
			var toggle := InputEventAction.new()
			toggle.action = "toggle_placement_mode"
			toggle.pressed = true
			player.placement.handle_input(player, toggle)
	await aim_at(contact, normal)
	var confirm := InputEventMouseButton.new()
	confirm.button_index = MOUSE_BUTTON_LEFT
	confirm.pressed = true
	player.placement.handle_input(player, confirm)
	ladder = fixed_ladder(identity)
	check(not player.is_placing_equipment() and ladder != null and ladder.can_climb() and ladder.mount_support == support, "Mouse confirmation keeps the actual wall as ladder support")
	player.camera.rotation = Vector3.ZERO
	return ladder

func reject_preview(ladder: Node3D, contact: Vector3, normal: Vector3, support: Node3D) -> Node3D:
	var original: Transform3D = ladder.global_transform
	var original_support: Node3D = ladder.mount_support
	var identity: String = ladder.persistent_id
	await aim_at(contact, normal, 1.0)
	check(ladder.pickup(player).contains("已拾取"), "Rejected-placement fixture picks up ladder first")
	check(player.enter_equipment_placement(), "Rejected-placement fixture starts held preview")
	ladder = player.placement.placing_equipment
	await physics_frame
	await process_frame
	var hit := aimed_hit(ladder)
	check(hit.get("collider") == support, "Rejected preview intersects the actual requested surface")
	var confirm := InputEventMouseButton.new()
	confirm.button_index = MOUSE_BUTTON_LEFT
	confirm.pressed = true
	for mode in range(2):
		player.placement.update_ghost(player)
		check(not player.placement.can_place_equipment, "Unsupported mounting surface is rejected in mode " + str(mode) + ": " + str(support.name))
		check(player.placement.target_support == support, "Rejected placement never redirects the actual support")
		player.placement.handle_input(player, confirm)
		check(player.is_placing_equipment(), "Invalid wall placement cannot be confirmed")
		if mode == 0:
			var toggle := InputEventAction.new()
			toggle.action = "toggle_placement_mode"
			toggle.pressed = true
			player.placement.handle_input(player, toggle)
	player.cancel_equipment_placement()
	check(player.inventory.active_item().state.id == identity, "Rejected preview cancellation retains inventory-owned ladder")
	check(player.enter_equipment_placement(), "Retained ladder can be placed again")
	player.placement.placing_equipment.global_transform = original
	player.placement.target_support = original_support
	player.placement.can_place_equipment = true
	var restored: bool = player.placement.commit(player)
	check(restored, "Rejected preview fixture reinstalls retained ladder at its valid original pose")
	if not restored:
		push_error("Reinstall reason: " + PlacementRules.rejection_reason(player.placement.placing_equipment, original_support, original) + " distance=" + str(player.camera.global_position.distance_to(original.origin)))
		quit(1)
		return null
	player.camera.rotation = Vector3.ZERO
	return fixed_ladder(identity)

func _run() -> void:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	floor_body.position.y = .4
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	rv.position.y = 1.2
	player = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	await physics_frame
	await process_frame
	var side: Node3D = rv.get_node("SideDoorLadder")
	var roof: Node3D = rv.get_node("RoofLadder")
	check(side is Item and roof is Item, "Both production ladders use movable Item")
	check(side.can_climb() and roof.can_climb(), "Installed ladders are available")
	for path in ["res://equipment/side_door_ladder.tscn", "res://equipment/roof_ladder.tscn"]:
		check(SaveSceneCatalog.resolve(path, "Item") != null, "Trusted Item catalog accepts " + path)

	# Retained geometric helpers cannot grant access to a bare RV wall.
	player.global_position = rv.to_global(Vector3(-2.65, -.2, -3.0))
	player.rotation.y = -PI / 2.0
	await physics_frame
	player.climb_wall_probe.force_raycast_update()
	check(player.climb_wall_probe.is_colliding(), "Bare-wall fixture ray hits the real RV")
	Input.action_press("move_forward")
	player._try_start_climb()
	check(player.locomotion_state == player.LocomotionState.NORMAL, "Empty-handed W against a bare RV wall cannot climb")
	release_inputs()

	# Both preview modes retain real contact points and continuous adjustment.
	side = await exercise_free_wall_placement(side, rv.to_global(Vector3(1.98, -.15, 0)), rv.global_basis.x, rv)
	var roof_bounds: AABB = roof.get_placement_bounds()
	var roof_normal: Vector3 = roof.global_basis.z.normalized()
	var wall_contact: Vector3 = roof.to_global(Vector3(roof_bounds.get_center().x, roof_bounds.get_center().y, roof_bounds.position.z)) - roof_normal * .012
	roof = await exercise_free_wall_placement(roof, wall_contact, roof_normal, roof.mount_support)
	var landing: Vector3 = roof.top_landing_point()
	var ceiling_hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(landing - Vector3.UP * .5, landing + Vector3.UP * .2, 1, [player.get_rid(), roof.get_rid()]))
	check(not ceiling_hit.is_empty() and ceiling_hit.collider is RVStructurePanel and ceiling_hit.collider.structure_kind == "roof", "Roof landing has an actual solid roof panel beneath it")
	for index in range(2):
		var ladder: Node3D = side if index == 0 else roof
		ladder = await reject_preview(ladder, rv.to_global(Vector3(2.0, 1.5, 0)), rv.global_basis.x, rv.get_node("RightMiddle"))
		ladder = await reject_preview(ladder, rv.to_global(Vector3(0, .5, 3)), Vector3.UP, rv.get_node("Floor"))
		if not ceiling_hit.is_empty():
			ladder = await reject_preview(ladder, ceiling_hit.position, Vector3.DOWN, ceiling_hit.collider)
		if index == 0: side = ladder
		else: roof = ladder

	# Closed leaf may allow the first rungs, but never a transfer through it.
	await reset(side)
	Input.action_press("move_forward")
	await tick(150)
	release_inputs()
	await tick()
	Input.action_press("move_forward")
	await tick(30)
	release_inputs()
	check(rv.to_local(player._climb_feet()).x > 1.9, "Closed side door keeps the climber outside the cabin")
	var door: Node3D = rv.get_node("RightMiddle")
	player._exit_climb_to_normal()
	player.global_position = Vector3(15, 3, 0)
	await physics_frame
	var open_result: String = door.toggle_leaf(0)
	check(door.open_requested[0], "Installed short ladder leaves the real door swing clear: " + open_result)
	await tick(90)
	check(absf(door.angles[0]) > deg_to_rad(90.0), "The side door completes its collision-checked opening")
	for ladder in [side, roof]:
		await entry_rejections(ladder)
		await entry_motion(ladder)
		await entry_motion(ladder, true)
		await landing_motion(ladder)
		await manual_top_controls(ladder)
	await unsupported_top_exit(side)
	floor_body.position.y = 0.0
	await physics_frame
	await entry_motion(side, false, -.4)
	floor_body.position.y = .4
	await physics_frame
	await traverse(side)
	await traverse(side, true)
	await traverse(roof)
	await traverse(roof, true)

	# A real overhead body blocks upward travel through the hatch.
	var obstacle := StaticBody3D.new()
	var obstacle_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, .2, 1.7)
	obstacle_shape.shape = box
	obstacle.add_child(obstacle_shape)
	world.add_child(obstacle)
	obstacle.global_position = roof.climb_point(roof.climb_height) + Vector3.UP * .4
	await reset(roof)
	Input.action_press("move_forward")
	await tick(150)
	release_inputs()
	check(roof.to_local(player._climb_feet()).y < roof.climb_height - .3, "A blocked hatch prevents capsule tunneling onto the roof")
	obstacle.queue_free()
	await physics_frame

	# Relative anchor includes both rotation and translation while holding.
	await reset(roof)
	Input.action_press("move_forward")
	await tick(8)
	release_inputs()
	check(player.active_climb_ladder == roof, "Player explicitly attaches to the selected ladder")
	var anchor: Vector3 = rv.to_local(player.global_position)
	for frame in 60:
		rv.position += -rv.basis.z * 4.0 * dt
		rv.rotate_y(.12 * dt)
		await tick()
	check(rv.to_local(player.global_position).distance_to(anchor) < .08, "Holding a ladder follows RV translation and turns")
	Input.action_press("move_left")
	await tick(8)
	release_inputs()
	check(rv.to_local(player.global_position).distance_to(anchor) < .08, "Lateral input cannot sidestep off the ladder")
	Input.action_press("move_back")
	await tick(2)
	release_inputs()
	check(player.locomotion_state == player.LocomotionState.CLIMBING, "S descends instead of detaching mid-ladder")
	check(rv.to_local(player.global_position).y < anchor.y, "S produces downward ladder motion")

	# Cancellation retains held ownership without a stale climb attachment.
	var roof_id: String = roof.persistent_id
	var original: Transform3D = roof.transform
	var original_support: Node3D = roof.mount_support
	var moved := roof.global_transform
	check(roof.pickup(player).contains("已拾取") and not roof.can_climb(), "Picking up a ladder makes it unavailable")
	check(player.enter_equipment_placement(), "Picked-up ladder starts a separate preview")
	check(player.locomotion_state == player.LocomotionState.NORMAL and player.active_climb_ladder == null, "Placement releases the active ladder attachment")
	player.cancel_equipment_placement()
	check(player.inventory.active_item().state.id == roof_id and not player.held_item_node.can_climb(), "Cancel retains an inactive held ladder instead of restoring the old world actor")
	moved.origin -= rv.global_basis.z * .12
	check(player.enter_equipment_placement(), "Held ladder can reopen relocation preview")
	player.placement.placing_equipment.global_transform = moved
	player.placement.target_support = original_support
	player.placement.can_place_equipment = true
	await physics_frame
	check(player.placement.commit(player), "Confirmed relocation fixes the inventory-owned ladder")
	roof = fixed_ladder(roof_id)
	check(roof.can_climb() and not roof.transform.is_equal_approx(original), "Confirmed relocation preserves ladder functionality")
	await traverse(roof)
	var saved := VehicleSnapshot.capture(rv)
	check(not saved.is_empty() and VehicleSnapshot.validate(saved), "Moved ladder has a valid vehicle snapshot")
	var ladder_id: String = roof.persistent_id
	var moved_local: Transform3D = roof.transform
	check(await VehicleSnapshot.apply(rv, saved), "Vehicle snapshot restores movable ladders")
	await physics_frame
	for device in rv.get_equipment():
		if device.persistent_id == ladder_id:
			roof = device
	check(is_instance_valid(roof) and roof.transform.is_equal_approx(moved_local), "Ladder ID and relocated transform survive roundtrip")
	check(roof.can_climb(), "Restored ladder retains climb availability")
	await reset(roof)
	Input.action_press("move_forward")
	await tick(5)
	release_inputs()
	roof.set_enabled(false)
	await tick()
	check(player.active_climb_ladder == null and player.locomotion_state == player.LocomotionState.NORMAL, "Disabled ladder releases its climber")
	roof.set_enabled(true)
	await reset(roof)
	Input.action_press("move_forward")
	await tick(5)
	release_inputs()
	var floor_support: Node3D = rv.get_node("Floor")
	var wall_support: Node3D = roof.mount_support
	floor_support.take_damage(floor_support.max_health)
	await process_frame
	await tick()
	check(player.active_climb_ladder == roof and roof.can_climb() and roof.mount_support == wall_support, "Floor removal retains the wall-mounted ladder and its active climber")
	roof.take_damage(roof.max_health)
	await tick()
	check(player.active_climb_ladder == null and player.locomotion_state == player.LocomotionState.NORMAL, "Destroyed ladder clears the active climb safely")
	roof = load("res://equipment/roof_ladder.tscn").instantiate()
	rv.add_child(roof)
	roof.confirm_placement(moved, rv, wall_support)
	await reset(roof)
	Input.action_press("move_forward")
	await tick(5)
	release_inputs()
	wall_support.take_damage(wall_support.max_health)
	await process_frame
	await tick()
	check(player.active_climb_ladder == null and not roof.can_climb(), "Support loss releases the climber and loose ladder cannot climb")
	check(roof.get_connected_rv() == null and not roof.freeze, "Destroying the actual mounting wall detaches its ladder")
	# Portable ladders placed on streamed walls are world actors, so removing
	# that chunk drops the device instead of deleting player-owned Item.
	var chunk := Node3D.new()
	world.add_child(chunk)
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(4, 4, .2)
	ground_shape.shape = ground_box
	ground.add_child(ground_shape)
	chunk.add_child(ground)
	ground.position = Vector3(25, 2.4, 0)
	var loose: Node3D = load("res://equipment/side_door_ladder.tscn").instantiate()
	world.add_child(loose)
	await physics_frame
	var ground_pose := Transform3D(Basis.IDENTITY, Vector3(25, .5, .262))
	check(PlacementRules.can_place(loose, ground, ground_pose), "Loose ladder back has an actual supported vertical mounting surface")
	loose.confirm_placement(ground_pose, ground, ground)
	var container := WorldEntities.get_container(loose)
	check(loose.get_parent() == container and loose.mount_support == ground, "Static wall placement keeps world ownership and actual wall support")
	check(loose.freeze and loose.can_climb(), "Placed static-wall ladder is frozen and usable")
	var loose_saved := WorldActorSnapshot.capture(loose)
	check(loose_saved.get("kind") == "item" and WorldActorSnapshot.validation_error(loose_saved, "ladder").is_empty(), "Loose ladder has a trusted world-actor snapshot")
	var restored_loose: Node3D = WorldActorSnapshot.restore(loose_saved, container)
	check(restored_loose.global_transform.is_equal_approx(ground_pose) and restored_loose.persistent_id == loose.persistent_id and restored_loose.current_health == loose.current_health and restored_loose.freeze, "Loose ladder roundtrip preserves pose, ID, durability and frozen state")
	restored_loose.queue_free()
	chunk.queue_free()
	await process_frame
	await physics_frame
	await process_frame
	check(is_instance_valid(loose) and loose.get_parent() == container and not loose.freeze and not loose.can_climb(), "Chunk removal preserves the loose ladder and releases its vanished support")
	world.queue_free()
	await process_frame
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: production RV ladders, routes, blocking, carrier, lifecycle and save roundtrip")
	quit(0 if failures.is_empty() else 1)
