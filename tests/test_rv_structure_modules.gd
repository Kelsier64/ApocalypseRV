extends SceneTree
var failures: Array[String] = []
var world: Node3D
var rv: Chassis
var player: CharacterBody3D
func _init() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func aim(point: Vector3, offset: Vector3) -> void:
	var camera: Camera3D = player.get_node("Camera3D")
	player.global_position = point + offset - Vector3.UP * camera.position.y
	camera.look_at(point)
	player.get_node("Camera3D/InteractRay").target_position = Vector3(0, 0, -3)
	player.get_node("Camera3D/InteractRay").force_raycast_update()
func click(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	player.placement.handle_input(player, event)
func obstacle(point: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "BlockingCrate"
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.25, 0.8, 0.25)
	collision.shape = box
	body.add_child(collision)
	world.add_child(body)
	body.global_position = point
	return body

func _run() -> void:
	world = Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var shell: Node3D = load("res://rv/new_rv.tscn").instantiate()
	world.add_child(shell)
	rv = shell.get_node("Chassis")
	rv.freeze = true
	rv.set_physics_process(false)
	player = load("res://player/player.tscn").instantiate()
	player.position = Vector3(10, 0, 0)
	world.add_child(player)
	player.set_physics_process(false)
	var ray: RayCast3D = player.get_node("Camera3D/InteractRay")
	ray.set_physics_process(false)
	await physics_frame
	await physics_frame
	var slots: RVStructureSlots = rv.get_node("StructureSlots")
	var side: RVStructurePanel = rv.get_node("RightMiddle")
	var ladder_wall: RVStructurePanel = rv.get_node("LeftMiddle")
	var rear: RVStructurePanel = rv.get_node("RearDoor")
	check(rv.get_structures().filter(func(d): return d.structure_kind == "side").size() == 6, "Six independently owned side modules")
	check(side.has_method("toggle_leaf") and not rv.get_node("LeftMiddle").has_method("toggle_leaf"), "Right wall-door-wall and left wall-wall-wall")
	for slot in RVStructureSlots.layout():
		check(slots.occupant(slot.id) != null, "Default socket occupied: " + slot.id)
	check(RVStructureSlots.layout().size() == 11, "Six side, front, rear and three roof slots; floor remains in the chassis")
	var roofs := rv.get_structures().filter(func(part): return part.structure_kind == "roof")
	check(roofs.size() == 3, "Three independently owned roof panels")
	var roof_weight := 0.0
	for index in range(3):
		var roof_panel := slots.occupant("roof_" + str(index))
		check(roof_panel != null and roof_panel.mass == 50.0 and roof_panel.get_placement_bounds().size.is_equal_approx(Vector3(4, 0.2, 4)), "Four metre roof segment weighs 50 kg: " + str(index))
		if roof_panel != null: roof_weight += roof_panel.mass
	check(roof_weight == 150.0, "Segmenting the roof preserves its total 150 kg")
	# Preserve the original chassis load and moment, whose 3000 kg included
	# the deck, while adding installed shell, engine and Item as before.
	var expected_intact_mass := 3000.0 + rv.get_engine().definition().weight
	var expected_intact_moment := Vector3(0.0, -2400.0, 0.0) + rv.engine_bay.position * rv.get_engine().definition().weight
	for part in rv.get_structures():
		expected_intact_mass += part.mass
		expected_intact_moment += part.position * part.mass
	for device in rv.get_equipment():
		expected_intact_mass += device.mass
		expected_intact_moment += device.position * device.mass
	rv.update_load()
	check(is_equal_approx(rv.mass, expected_intact_mass), "Fixed chassis floor preserves the original 3000 kg base vehicle weight")
	check(rv.center_of_mass.is_equal_approx(expected_intact_moment / expected_intact_mass), "Fixed chassis floor preserves the intact vehicle center of mass")
	var middle_roof: RVStructurePanel = slots.occupant("roof_1")
	var roof_mass_before := rv.mass
	var roof_moment_before := rv.center_of_mass * rv.mass
	middle_roof.take_damage(999.0)
	await physics_frame
	check(slots.occupant("roof_1") == null and slots.occupant("roof_0") != null and slots.occupant("roof_2") != null, "Destroying the middle roof leaves both neighbouring segments intact")
	check(rv.get_node("CabinLightFront").can_operate() and rv.get_node("CabinLightRear").can_operate(), "An unsupported middle roof breach leaves the other roof lamps mounted")
	rv.update_load()
	check(is_equal_approx(rv.mass, roof_mass_before - 50.0), "One roof breach removes exactly one 50 kg segment")
	check(rv.center_of_mass.is_equal_approx((roof_moment_before - middle_roof.position * 50.0) / rv.mass), "One roof breach updates the centre of mass independently")
	middle_roof.set_health(middle_roof.max_health)
	await physics_frame
	# Real short E opens the aimed leaf.
	aim(side.global_position, Vector3(2.5, 0, 0))
	check(ray.get_collider() == side, "Closed side door is ray reachable")
	ray._step_buttons(side, true, false, 0.016)
	ray._step_buttons(side, false, false, 0.016)
	for frame in ceili(75 * Engine.physics_ticks_per_second / 60.0): await physics_frame
	check(side.angles[0] < -1.6, "Short E opens side door outward")
	# Structures expose door use, but never the movable Item lifecycle.
	check(not (side as Node) is Item and not (rear as Node) is Item, "Door frames are independent vehicle structures")
	for device in rv.get_structures():
		check(not device.has_method("start_placement") and not device.has_method("repair_health"), "Structure has no F/H Item entry point: " + device.mount_slot)
		check(not rv.get_equipment().has(device), "Structure is excluded from Item registry: " + device.mount_slot)
		var prompt: String = ray.get_prompt(device)
		check(not prompt.contains("長按 F") and not prompt.contains("長按 H"), "Structure prompt never offers field movement or repair")
	ray._step_buttons(side, false, true, 2.1)
	check(not player.is_placing_equipment(), "Holding F on a door cannot start placement")
	ray._step_buttons(side, false, false, 0.0)
	var previous_health := side.current_health
	var field_repair := RepairOperation.new()
	field_repair.step(player, side, true, 3.0)
	check(side.current_health == previous_health and field_repair.progress == 0.0, "Holding H cannot repair a vehicle structure")
	side.restore_angles([0.0])
	player.position = Vector3(10, 0, 0)
	await physics_frame
	# Both rear leaves remain separate E targets on the fixed frame.
	aim(rear.to_global(Vector3(-0.7, 0, 0)), Vector3(0, 0, 2.1))
	check(rear.aimed_leaf(player) == 0, "Left rear leaf selected by its actual shape")
	check(rear.interact(player) == "開門中", "Left rear leaf begins opening")
	player.position = Vector3(10, 0, 0)
	for frame in ceili(75 * Engine.physics_ticks_per_second / 60.0): await physics_frame
	check(rear.angles[0] < -1.6 and rear.angles[1] == 0.0, "Opening left rear leaf leaves right leaf closed")
	aim(rear.to_global(Vector3(0.7, 0, 0)), Vector3(0, 0, 2.1))
	check(rear.aimed_leaf(player) == 1, "Right rear leaf selected independently")
	rear.interact(player)
	player.position = Vector3(10, 0, 0)
	for frame in ceili(75 * Engine.physics_ticks_per_second / 60.0): await physics_frame
	check(rear.angles[1] > 1.6, "Right rear leaf opens outward")
	# Check the whole swept path, not only its final pose.
	var crate := obstacle(side.to_global(Vector3(0, -0.1, 0.55)))
	await physics_frame
	var result: String = side.toggle_leaf(0)
	check(result.contains("BlockingCrate") and side.targets[0] == 0.0, "Obstacle midway through swing prevents opening")
	crate.free()
	await physics_frame
	side.toggle_leaf(0)
	for frame in ceili(8 * Engine.physics_ticks_per_second / 60.0): await physics_frame
	crate = obstacle(side.to_global(Vector3(0, -0.1, 0.55)))
	await physics_frame
	for frame in ceili(75 * Engine.physics_ticks_per_second / 60.0): await physics_frame
	check(absf(side.angles[0]) < 1.6 and side.blocked_message.contains("BlockingCrate"), "New obstacle during animation stops the moving leaf")
	crate.free()
	# A person entering the closing path stops the leaf; the next E can reopen it.
	side.restore_angles([-deg_to_rad(100.0)])
	side.toggle_leaf(0)
	for frame in ceili(8 * Engine.physics_ticks_per_second / 60.0): await physics_frame
	player.global_position = side.to_global(Vector3(0, -1.0, 0.55))
	await physics_frame
	for frame in ceili(75 * Engine.physics_ticks_per_second / 60.0): await physics_frame
	check(absf(side.angles[0]) > 0.2 and side.blocked_message.contains("角色"), "Closing leaf stops for a character entering the sweep")
	check(side.toggle_leaf(0) == "開門中", "A blocked closing leaf can reverse safely")
	player.position = Vector3(10, 0, 0)
	for frame in ceili(75 * Engine.physics_ticks_per_second / 60.0): await physics_frame
	# A closed door rejects equipment attachment to its moving leaf, but permits fixed jamb contact.
	side.restore_angles([0.0])
	var item: Item = rv.get_node("ItemBox")
	check(PlacementRules.rejection_reason(item, side, Transform3D.IDENTITY, side.to_global(Vector3(0, 0, 0.05))).contains("活動門扇"), "Cannot mount equipment on moving door leaf")
	check(side.allows_mount_at(side.to_global(Vector3(1.5, 0, 0.1))), "Fixed side jamb remains an attachment surface")
	# A destroyed slot keeps its state node while only its dependents drop.
	var support_panel: RVStructurePanel = slots.occupant("right_0")
	var neighbour: RVStructurePanel = slots.occupant("right_2")
	var mounted: Item = load("res://equipment/tablet_screen.tscn").instantiate()
	world.add_child(mounted)
	mounted.confirm_placement(support_panel.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.3)), rv, support_panel)
	check(PlacementRules.valid_target(mounted, support_panel), "Live wall can support general Item")
	check(not mounted.is_in_group(Groups.MONSTER_DAMAGEABLE), "Tablet is excluded from monster attack discovery")
	var tablet_health := mounted.current_health
	mounted.take_damage(100000.0)
	check(mounted.current_health == tablet_health and not mounted.is_destroyed, "Tablet ignores all damage")
	var indirect := Item.new()
	indirect.equipment_name = "Indirect dependent"
	world.add_child(indirect)
	indirect.confirm_placement(mounted.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), rv, mounted)
	check(support_panel.dependent_names().has(indirect.equipment_name), "Structure reports indirect supported Item")
	rv.linear_velocity = Vector3(2.0, 0.0, 0.0)
	rv.angular_velocity = Vector3(0.0, 0.4, 0.0)
	var expected_velocity := ClimbMath.point_velocity(rv, mounted.global_position)
	var released_velocities: Array[Vector3] = []
	mounted.availability_changed.connect(func():
		if mounted.get_connected_rv() == null: released_velocities.append(mounted.linear_velocity))
	var neighbour_health := neighbour.current_health
	support_panel.take_damage(100000.0)
	await physics_frame
	await physics_frame
	check(mounted.get_connected_rv() == null and not mounted.freeze, "Destroyed wall drops its mounted tablet")
	check(indirect.get_connected_rv() == null and not indirect.freeze, "Wall removal cascades through indirect Item support")
	check(not released_velocities.is_empty() and released_velocities[0].is_equal_approx(expected_velocity), "Dropped device inherits the vehicle point velocity")
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	check(slots.panel("right_0") == support_panel and slots.occupant("right_0") == null, "Broken wall retains a persistent empty slot")
	check(support_panel.is_destroyed and not support_panel.visible and support_panel.collision_layer == 0, "Broken structure removes visuals and collision")
	check(not support_panel.is_in_group(Groups.MONSTER_DAMAGEABLE), "Broken structure is no longer monster attackable")
	check(not PlacementRules.valid_target(mounted, support_panel), "Destroyed wall cannot support placement")
	check(neighbour.current_health == neighbour_health and neighbour.get_connected_rv() == rv, "Neighbour damage and support are independent")
	check(CombatTargeting.build_target(support_panel, "Item").is_empty(), "Stale destroyed state node never becomes a combat target")
	var remembered := RVSupport.new()
	remembered.surface = support_panel
	remembered.rv = rv
	check(not remembered.follow(player, 1.0 / 60.0), "Remembered destroyed surface cannot carry an actor")
	var ramp: RearRamp = rv.get_node("RearRamp")
	rear.restore_angles([-deg_to_rad(100.0), deg_to_rad(100.0)])
	check(ramp.doors_open(), "Ramp reads open rear door from structure slots")
	rear.restore_angles([0.0, 0.0])
	check(not ramp.doors_open(), "Closed rear structure blocks ramp deployment")
	rear.take_damage(100000.0)
	check(ramp.doors_open(), "Destroyed rear structure leaves clear ramp access")
	var deck: CollisionShape3D = rv.get_node("DeckCollision")
	check(not rv.has_node("Floor") and RVStructureSlots.slot_info("floor").is_empty() and not rv.get_structures().any(func(part): return part.structure_kind == "floor"), "Fixed floor has no damageable structure state or construction slot")
	check(deck.get_parent() == rv and not deck.disabled and deck.position.is_equal_approx(Vector3(0, .4, 0)) and deck.shape is BoxShape3D and deck.shape.size.is_equal_approx(Vector3(4, .2, 12)), "Original continuous deck collision belongs directly to the chassis")
	check(rv.get_node("Deck").visible, "Original fixed deck remains visible after side and rear breaches")
	var through_floor := PhysicsRayQueryParameters3D.create(rv.to_global(Vector3(0, 1.0, 2.6)), rv.to_global(Vector3(0, -0.4, 2.6)), 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(through_floor)
	check(hit.get("collider") == rv, "Deck ray hits the chassis rather than a separate structure body")
	for node_name in ["DriverSeat", "ItemBox", "Generator", "CraftingStation", "Scrapper"]:
		var preset: Item = rv.get_node(node_name)
		check(preset.get_connected_rv() == rv and preset.freeze and preset.mount_support == rv, "Shell breaches retain stock equipment on fixed chassis support: " + node_name)
	var tablet: Item = rv.get_node("TabletScreen")
	check(tablet.get_connected_rv() == rv and tablet.freeze and tablet.mount_support == rv.get_node("CraftingStation"), "Fixed floor retains indirect workstation tablet support")
	var roof_ladder: Item = rv.get_node("RoofLadder")
	check(roof_ladder.get_connected_rv() == rv and roof_ladder.freeze and roof_ladder.mount_support == ladder_wall, "Shell breaches retain the separately wall-mounted roof ladder")
	rv.update_load()
	var mass_before_chassis_damage := rv.mass
	var moment_before_chassis_damage := rv.center_of_mass * rv.mass
	rv.take_damage(1.0)
	await physics_frame
	rv.update_load()
	hit = world.get_world_3d().direct_space_state.intersect_ray(through_floor)
	check(hit.get("collider") == rv and not deck.disabled and rv.get_node("Deck").visible, "Chassis damage does not destroy or remove the fixed floor")
	check(is_equal_approx(rv.mass, mass_before_chassis_damage) and (rv.center_of_mass * rv.mass).is_equal_approx(moment_before_chassis_damage), "Damage keeps fixed deck weight and centre of mass unchanged")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: independent fixed structures, door obstruction, tablet immunity, support drop and persistent chassis floor")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
