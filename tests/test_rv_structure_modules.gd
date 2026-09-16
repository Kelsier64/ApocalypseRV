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
	var side: Equipment = rv.get_node("RightMiddle")
	var rear: Equipment = rv.get_node("RearDoor")
	check(rv.get_equipment().filter(func(d): return d.get("structure_kind") == "side").size() == 6, "Six independently owned side modules")
	check(side.has_method("toggle_leaf") and not rv.get_node("LeftMiddle").has_method("toggle_leaf"), "Right wall-door-wall and left wall-wall-wall")
	for slot in RVStructureSlots.layout():
		check(slots.occupant(slot.id) != null, "Default socket occupied: " + slot.id)
	# Real short E opens the aimed leaf.
	aim(side.global_position, Vector3(2.5, 0, 0))
	check(ray.get_collider() == side, "Closed side door is ray reachable")
	ray._step_buttons(side, true, false, 0.016)
	ray._step_buttons(side, false, false, 0.016)
	for frame in range(75): await physics_frame
	check(side.angles[0] < -1.6, "Short E opens side door outward")
	var open_angle: float = side.angles[0]
	# F workflow returns to the persistent socket, independent of a surface ray hit.
	side.start_placement(player)
	check(side.angles[0] == 0.0, "Door folds for whole-frame placement")
	player.placement.update_ghost(player)
	check(player.placement.can_place_equipment, "Removed side door can return to its exact original slot: " + player.placement.message)
	check(player.placement.target_support == rv, "Socket support is chassis, not neighbouring panel")
	click(MOUSE_BUTTON_RIGHT)
	check(is_equal_approx(side.angles[0], open_angle), "Cancel restores previous open angle")
	side.start_placement(player)
	player.placement.update_ghost(player)
	click(MOUSE_BUTTON_LEFT)
	check(side.mount_slot == "right_1" and not side.is_being_placed and side.angles[0] == 0.0, "Reinstall commits one closed door to original slot")
	# Occupied socket and actual obstruction give distinct explanations.
	side.start_placement(player)
	aim(rv.to_global(Vector3(1.9, 1.5, 4)), Vector3(2.5, 0, 0))
	player.placement.update_ghost(player)
	check(not player.placement.can_place_equipment and player.placement.message.contains("槽位已有"), "Occupied socket explains refusal")
	aim(rv.to_global(Vector3(1.9, 1.5, 0)), Vector3(2.5, 0, 0))
	var crate := obstacle(rv.to_global(Vector3(1.9, 1.5, 0)))
	await physics_frame
	player.placement.update_ghost(player)
	check(not player.placement.can_place_equipment and player.placement.message.contains("BlockingCrate"), "Blocked installation identifies obstacle")
	crate.free()
	await physics_frame
	player.placement.update_ghost(player)
	check(player.placement.can_place_equipment, "Removing obstacle immediately restores valid placement")
	click(MOUSE_BUTTON_LEFT)
	var wheel_panel: Equipment = rv.get_node("RightFront")
	# Slots continue to follow tilted vehicles and do not allow installation through walls.
	rv.rotation = Vector3(0.08, 0.3, -0.06)
	await physics_frame
	aim(wheel_panel.global_position, rv.global_basis.x * 2.5)
	wheel_panel.start_placement(player)
	player.placement.update_ghost(player)
	check(player.placement.can_place_equipment, "Slot reinstall works on a tilted RV: " + player.placement.message)
	click(MOUSE_BUTTON_LEFT)
	check(wheel_panel.mount_slot == "right_0", "Tilted reinstall retains socket identity")
	rv.rotation = Vector3.ZERO
	player.position = Vector3(10, 0, 0)
	await physics_frame
	# Both rear leaves are separate E targets while F still owns the frame.
	aim(rear.to_global(Vector3(-0.7, 0, 0)), Vector3(0, 0, 2.1))
	check(rear.aimed_leaf(player) == 0, "Left rear leaf selected by its actual shape")
	check(rear.interact(player) == "開門中", "Left rear leaf begins opening")
	player.position = Vector3(10, 0, 0)
	for frame in range(75): await physics_frame
	check(rear.angles[0] < -1.6 and rear.angles[1] == 0.0, "Opening left rear leaf leaves right leaf closed")
	aim(rear.to_global(Vector3(0.7, 0, 0)), Vector3(0, 0, 2.1))
	check(rear.aimed_leaf(player) == 1, "Right rear leaf selected independently")
	rear.interact(player)
	player.position = Vector3(10, 0, 0)
	for frame in range(75): await physics_frame
	check(rear.angles[1] > 1.6, "Right rear leaf opens outward")
	# Check the whole swept path, not only its final pose.
	crate = obstacle(side.to_global(Vector3(0, -0.1, 0.55)))
	await physics_frame
	var result: String = side.toggle_leaf(0)
	check(result.contains("BlockingCrate") and side.targets[0] == 0.0, "Obstacle midway through swing prevents opening")
	crate.free()
	await physics_frame
	side.toggle_leaf(0)
	for frame in range(8): await physics_frame
	crate = obstacle(side.to_global(Vector3(0, -0.1, 0.55)))
	await physics_frame
	for frame in range(75): await physics_frame
	check(absf(side.angles[0]) < 1.6 and side.blocked_message.contains("BlockingCrate"), "New obstacle during animation stops the moving leaf")
	crate.free()
	# A person entering the closing path stops the leaf; the next E can reopen it.
	side.restore_angles([-deg_to_rad(100.0)])
	side.toggle_leaf(0)
	for frame in range(8): await physics_frame
	player.global_position = side.to_global(Vector3(0, -1.0, 0.55))
	await physics_frame
	for frame in range(75): await physics_frame
	check(absf(side.angles[0]) > 0.2 and side.blocked_message.contains("角色"), "Closing leaf stops for a character entering the sweep")
	check(side.toggle_leaf(0) == "開門中", "A blocked closing leaf can reverse safely")
	player.position = Vector3(10, 0, 0)
	for frame in range(75): await physics_frame
	# A closed door rejects equipment attachment to its moving leaf, but permits fixed jamb contact.
	side.restore_angles([0.0])
	var item: Equipment = rv.get_node("ItemBox")
	check(PlacementRules.rejection_reason(item, side, Transform3D.IDENTITY, side.to_global(Vector3(0, 0, 0.05))).contains("活動門扇"), "Cannot mount equipment on moving door leaf")
	check(side.allows_mount_at(side.to_global(Vector3(1.5, 0, 0.1))), "Fixed side jamb remains an attachment surface")
	# Save actual angles, slot ownership, and validate corrupted structures before mutation.
	var snapshot := VehicleSnapshot.capture(rv)
	check(VehicleSnapshot.validate(snapshot), "New socket and leaf state validates")
	var invalid := snapshot.duplicate(true)
	for entry in invalid.equipment:
		if entry.scene == "res://equipment/rv_rear_door.tscn": entry.service.door_angles = [INF, 0.0]
	check(not VehicleSnapshot.validate(invalid), "Non-finite door angles are rejected")
	var side_id := side.persistent_id
	var rear_id := rear.persistent_id
	check(await VehicleSnapshot.apply(rv, snapshot), "Snapshot reconstructs structure assemblies")
	for d in rv.get_equipment():
		if d.persistent_id == rear_id: rear = d
		if d.persistent_id == side_id: side = d
	check(rear.angles[0] < -1.6 and rear.angles[1] > 1.6 and rear.mount_slot == "rear", "Both rear angles and socket survive reload")
	check(side.mount_slot == "right_1", "Side slot survives reload")
	# Moving and reinstalling the large rear assembly also works when open.
	aim(rear.global_position, Vector3(0, 0, 2.5))
	rear.start_placement(player)
	player.placement.update_ghost(player)
	check(player.placement.can_place_equipment, "Large rear door returns to its slot: " + player.placement.message)
	click(MOUSE_BUTTON_LEFT)
	# A panel's dependencies detach, while other chassis sockets remain independent.
	var support_panel: Equipment = slots.occupant("right_0")
	var neighbour: Equipment = slots.occupant("right_2")
	var mounted: Equipment = load("res://equipment/tablet_screen.tscn").instantiate()
	world.add_child(mounted)
	mounted.confirm_placement(support_panel.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.3)), rv, support_panel)
	support_panel.start_placement(player)
	await physics_frame
	await physics_frame
	check(mounted.get_connected_rv() == null and not mounted.freeze, "Moving one panel drops only its mounted equipment")
	check(neighbour.get_connected_rv() == rv and slots.occupant("roof") != null, "Neighbours and roof remain supported by chassis")
	click(MOUSE_BUTTON_RIGHT)
	support_panel.take_damage(1000)
	await physics_frame
	await physics_frame
	check(slots.occupant("right_0") == null and is_instance_valid(neighbour), "Destroying one segment frees only its own socket")
	# Legacy stock shell upgrades once, preserves IDs/health and leaves custom transforms alone.
	var legacy_shell: Node3D = load("res://rv/legacy/new_rv.tscn").instantiate()
	legacy_shell.position.x = 20
	world.add_child(legacy_shell)
	var old_rv: Chassis = legacy_shell.get_node("Chassis")
	old_rv.freeze = true
	await physics_frame
	var old_snapshot := VehicleSnapshot.capture(old_rv)
	old_snapshot.version = 2
	old_snapshot.health = old_rv.get_engine().health
	for entry in old_snapshot.equipment:
		entry.scene = entry.scene.replace("res://rv/legacy/", "res://equipment/")
	var upgraded := VehicleSnapshot.upgrade(old_snapshot)
	check(VehicleSnapshot.validate(upgraded), "Legacy standard body upgrades to valid modules")
	check(upgraded.equipment.filter(func(e): return e.scene in ["res://equipment/rv_side_panel.tscn", "res://equipment/rv_side_door.tscn"]).size() == 6, "Legacy long sides split into six modules")
	check(VehicleSnapshot.upgrade(upgraded) == upgraded, "Structural migration is idempotent")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: module layout, remove/reinstall, obstruction feedback, moving doors and persistence")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
