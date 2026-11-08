extends RefCounted
## Exercise physical route adapters and independent manifests through one visit.

const SCRAP := preload("res://props/scrap.tscn")
const WAIT := preload("res://tests/support/test_wait.gd")

class FailedChild extends PoiInterior:
	func build(_seed: int, _saved: Dictionary = {}) -> bool:
		for _frame in 3:
			await get_tree().process_frame
			if cancelled: return false
		return false

class DirectInterior extends PoiInterior:
	func _init() -> void:
		room_count = 2
		target_floors = 1
		populate_content = false

static func run(tree: SceneTree, arena: Node3D, manager: PoiInstanceManager, player: CharacterBody3D, check: Callable) -> void:
	player.inventory.items.clear()
	player.inventory.active_slot = 0
	player.refresh_inventory()
	manager.interior_factory = Callable()
	var id := "megashelter-chain"
	var site := {"id": id, "seed": 913, "definition_id": "modular_megashelter", "placement": "off_road", "building": Transform3D(Basis.IDENTITY, Vector3(350, 0, 0)), "exterior_plan": MegashelterPlan.generate(913)}
	var building := POISpawner.new().spawn_site(site, arena, false)
	check.call(building != null, "Chain fixture uses a production megashelter entrance")
	if building == null: return
	await manager.enter(player, building, id, site.seed)
	if not _inside(manager, player, id, &"megashelter", check): return
	var shelter := manager.interior
	var shelter_world := shelter.get_world_3d()
	for actor in shelter.entities.get_children():
		if actor is Item: actor.freeze = true
	var picked := shelter.entities.get_child(0) as Item
	check.call(picked != null, "Chained shelter starts with a real loose supply")
	if picked == null: return
	var picked_id := picked.persistent_id
	picked.interact(player)
	await tree.process_frame
	shelter.explored.assign([str(shelter.layout.rooms[0].id), str(shelter.layout.rooms[1].id)])
	var shelter_drop := _drop(shelter, "Shelter chain drop")
	var shelter_drop_id := shelter_drop.persistent_id
	var shelter_commit := shelter.snapshot()
	var shelter_return: Transform3D = shelter.link_return_transforms.get(&"megashelter_stairwell", Transform3D.IDENTITY)
	var door := shelter.link_doors.get(&"megashelter_stairwell") as PoiEntrance
	check.call(door != null, "Shelter service doorway targets the isolated stairwell")
	if door == null: return
	var shelter_door_pose := door.global_transform
	_check_shelter_access(shelter, door, check)
	await tree.physics_frame
	_check_door_ray(shelter, player, door, shelter_return.origin, "Seeded shelter stair access", check)
	await _interact_key(tree, manager, player, door, shelter_return, false, check)
	if not _inside(manager, player, id + ":stairs", &"megashelter_stairwell", check): return
	check.call(manager.interior.get_world_3d() != shelter_world, "Stairwell owns a separate World3D from the shelter")
	check.call(manager.saved_instances.get(id, {}) == shelter_commit, "Entering stairs commits the shelter manifest before transfer")
	check.call(manager.interior.entities.get_child_count() == 0 and manager.interior.caches.is_empty(), "Stairwell does not populate bunker rewards or shelter supplies")
	_check_stairwell_schema(manager.interior, shelter_commit.caches[0], check)
	var stairs_layout := manager.interior.layout.duplicate(true)
	var stairs_return: Transform3D = manager.interior.link_return_transforms.get(&"bunker", Transform3D.IDENTITY)
	door = manager.interior.link_doors.get(&"bunker") as PoiEntrance
	check.call(door != null, "Lower stairwell door targets the bunker")
	if door == null: return
	var lower_shape := door.get_child(0) as CollisionShape3D
	var lower_box := lower_shape.shape as BoxShape3D if lower_shape != null else null
	check.call(lower_box != null and is_equal_approx(lower_box.size.x, 1.06) and is_equal_approx(lower_box.size.y, 2.32), "Lower bunker interaction opening fits the small pedestrian door")
	check.call(manager.interior.rooms[0].has_node("Visuals/BunkerDoor"), "Lower bunker entrance has its own pedestrian door model")
	await tree.physics_frame
	_check_door_ray(manager.interior, player, manager.interior.exit_door, manager.interior.spawn_transform().origin, "Upper stairwell exit", check)
	_check_door_ray(manager.interior, player, door, stairs_return.origin, "Lower stairwell bunker door", check)
	await _interact_key(tree, manager, player, door, stairs_return, false, check)
	if not _inside(manager, player, id + ":bunker", &"bunker", check): return
	var bunker := manager.interior
	for actor in bunker.entities.get_children():
		if actor is Monster: actor.process_mode = Node.PROCESS_MODE_DISABLED
		elif actor is Item: actor.freeze = true
	bunker.explored.assign([str(bunker.layout.rooms[0].id), str(bunker.layout.rooms[1].id)])
	var bunker_drop := _drop(bunker, "Bunker chain drop")
	var bunker_drop_id := bunker_drop.persistent_id
	var bunker_commit := bunker.snapshot()
	await _interact(tree, manager, player, bunker.exit_door, check)
	if not _inside(manager, player, id + ":stairs", &"megashelter_stairwell", check): return
	check.call(manager.interior.layout == stairs_layout, "Bunker return restores the same stairwell manifest")
	check.call(player.global_transform.is_equal_approx(stairs_return), "Bunker exit arrives at the lower stair landing")
	check.call(manager.saved_instances.get(id, {}) == shelter_commit, "Bunker visit does not overwrite the shelter snapshot")
	check.call(manager.saved_instances.get(id + ":bunker", {}).get("explored", []) == bunker_commit.explored, "Bunker exploration commits under its own child instance ID")
	await _interact(tree, manager, player, manager.interior.exit_door, check)
	if not _inside(manager, player, id, &"megashelter", check): return
	check.call(player.global_transform.is_equal_approx(shelter_return), "Stairwell exit returns to the selected room landing facing away from its door")
	check.call(manager.interior.link_doors[&"megashelter_stairwell"].global_transform.is_equal_approx(shelter_door_pose) and manager.interior.link_return_transforms[&"megashelter_stairwell"].is_equal_approx(shelter_return), "Shelter revisit restores the same seeded stair doorway and return landing")
	var shelter_revisit := manager.interior.snapshot()
	check.call(shelter_revisit.layout == shelter_commit.layout and shelter_revisit.explored == shelter_commit.explored, "Returning upstairs preserves shelter layout and exploration")
	var shelter_ids := _item_ids(shelter_revisit)
	check.call(shelter_drop_id in shelter_ids and picked_id not in shelter_ids and bunker_drop_id not in shelter_ids, "Shelter return keeps its drop once without respawning pickup or importing bunker props")
	check.call(player.inventory.items.any(func(item): return item.state.id == picked_id), "Picked shelter supply remains owned by player through both child instances")
	# Revisit the child domain too: a return stack must retain the child save.
	await _interact_key(tree, manager, player, manager.interior.link_doors[&"megashelter_stairwell"], manager.interior.link_return_transforms[&"megashelter_stairwell"], true, check)
	if not _inside(manager, player, id + ":stairs", &"megashelter_stairwell", check): return
	await _interact_key(tree, manager, player, manager.interior.link_doors[&"bunker"], manager.interior.link_return_transforms[&"bunker"], true, check)
	if not _inside(manager, player, id + ":bunker", &"bunker", check): return
	var bunker_revisit := manager.interior.snapshot()
	var bunker_ids := _item_ids(bunker_revisit)
	check.call(bunker_revisit.layout == bunker_commit.layout and bunker_revisit.explored == bunker_commit.explored, "Bunker revisit keeps its own authoritative layout and exploration")
	check.call(bunker_ids.count(bunker_drop_id) == 1 and shelter_drop_id not in bunker_ids, "Bunker drop persists exactly once and never imports shelter props")
	check.call(CheckpointSchema.poi_error(manager.saved_instances).is_empty(), "Checkpoint schema accepts independently saved shelter, stairwell and bunker manifests")
	await manager.leave()
	await manager.leave()
	await manager.leave()
	check.call(manager.state == PoiInstanceManager.State.OUTDOOR and player.get_parent() == arena and manager.active_id.is_empty(), "Complete child return chain eventually restores the original outdoor player owner")
	await _failed_child(tree, arena, manager, player, building, id, shelter_door_pose, shelter_return, check)
	building.queue_free()
	await _direct_bunker(tree, arena, manager, player, check)

static func _drop(interior: PoiInterior, label: String) -> Item:
	var item := SCRAP.instantiate() as Item
	item.item_name = label
	item.freeze = true
	interior.entities.add_child(item)
	item.global_position = interior.navigation_anchor(0) + Vector3.UP
	return item

static func _check_stairwell_schema(interior: PoiInterior, cache: Dictionary, check: Callable) -> void:
	var saved := interior.snapshot()
	var invalid := saved.duplicate(true)
	invalid.content.cargo_id = "forbidden-stairwell-cargo"
	invalid.content.cargo_room = str(saved.layout.rooms[0].id)
	check.call(CheckpointSchema.poi_error({"stairs": invalid}).ends_with(".content.cargo"), "Stairwell checkpoint rejects an injected bunker cargo objective")
	invalid = saved.duplicate(true)
	invalid.caches.append(cache.duplicate(true))
	check.call(CheckpointSchema.poi_error({"stairs": invalid}).ends_with(".caches"), "Stairwell checkpoint rejects an injected supply cache")
	invalid = saved.duplicate(true)
	invalid.actors.append({"kind": "monster"})
	check.call(CheckpointSchema.poi_error({"stairs": invalid}).ends_with(".actors.monster"), "Stairwell checkpoint rejects monster actors before restoration")
	_drop(interior, "Allowed stairwell drop")
	check.call(CheckpointSchema.poi_error({"stairs": interior.snapshot()}).is_empty(), "Stairwell checkpoint still accepts a real loose Item")

static func _item_ids(snapshot: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for actor: Dictionary in snapshot.actors:
		if actor.kind == "item": ids.append(str(actor.state.id))
	return ids

static func _check_shelter_access(interior: PoiInterior, door: PoiEntrance, check: Callable) -> void:
	var access_rooms: Array[int] = []
	var unused_socket := false
	for i in interior.rooms.size():
		var room := interior.rooms[i]
		if not room.has_node("Visuals/StairAccess"): continue
		access_rooms.append(i)
		for socket: PoiDoorSocket in room.get_node("DoorSockets").get_children():
			if InteriorLayout.used(interior.layout, i, str(socket.socket_id)): continue
			# The door skin and interaction body sit just inside a sealed port.
			if socket.global_position.distance_to(door.global_position) < 0.75:
				unused_socket = true
	check.call(access_rooms.size() == 1 and access_rooms[0] > 0, "Seeded stairs occupy exactly one room beyond reception")
	check.call(unused_socket, "Seeded stair doorway uses an unused wall socket without replacing a room connection")

static func _check_door_ray(interior: PoiInterior, player: CharacterBody3D, door: PoiEntrance, landing: Vector3, label: String, check: Callable) -> void:
	var from := landing + Vector3.UP * 1.5
	var to := door.to_global(Vector3(0, 1.5, -0.2))
	var ray := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [player.get_rid()])
	var hit := interior.get_world_3d().direct_space_state.intersect_ray(ray)
	check.call(not hit.is_empty() and hit.get("collider") == door, label + " is the first standing-height interaction target from its real landing")

static func _inside(manager: PoiInstanceManager, player: CharacterBody3D, id: String, profile: StringName, check: Callable) -> bool:
	var ok := manager.state == PoiInstanceManager.State.INDOOR and manager.interior != null and manager.active_id == id
	check.call(ok, "Route arrives at " + id + ": " + manager.last_error)
	if not ok: return false
	ok = manager.interior.profile_id == profile and player.get_parent() == manager.interior and not manager.busy and not player.in_ui_mode
	check.call(ok, "Route restores controls and correct profile/ownership for " + id)
	check.call(manager._status.text.is_empty(), "Route clears passive title and return instructions for " + id)
	return ok

static func _interact(tree: SceneTree, manager: PoiInstanceManager, player: CharacterBody3D, door: PoiEntrance, check: Callable) -> void:
	var previous := manager.active_id
	door.interact(player)
	await tree.process_frame
	var deadline := Time.get_ticks_msec() + 90000
	while (manager.busy or manager.active_id == previous) and Time.get_ticks_msec() < deadline:
		if manager.state == PoiInstanceManager.State.FAILED: return
		if is_instance_valid(manager._retained_viewport): _check_retained(manager, player, check)
		await tree.process_frame

static func _interact_key(tree: SceneTree, manager: PoiInstanceManager, player: CharacterBody3D, door: PoiEntrance, landing: Transform3D, physical: bool, check: Callable) -> void:
	# Exercise the real camera ray and viewport keyboard forwarding. A virtual
	# keyboard can report E without a physical scan code.
	var previous := manager.active_id
	player.complete_world_transition(landing)
	player.look_at(Vector3(door.global_position.x, player.global_position.y, door.global_position.z))
	player.camera.look_at(door.global_position + Vector3.UP * 1.5)
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.set_physics_process(false)
	for _frame in 3: await tree.physics_frame
	var ray := player.get_node("Camera3D/InteractRay") as RayCast3D
	ray.force_raycast_update()
	var destination := str(door.destination_id)
	check.call(ray.get_collider() == door and not ray.prompt_label.text.is_empty(), destination + " door is targeted by the real player interaction ray")
	var event := InputEventKey.new()
	event.keycode = 0 if physical else KEY_E
	if physical: event.physical_keycode = KEY_E
	event.pressed = true
	Input.parse_input_event(event)
	for _frame in 3: await tree.physics_frame
	event.pressed = false
	Input.parse_input_event(event)
	var arrived := await WAIT.until(tree, func(): return manager.active_id != previous and not manager.busy, 10000)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	check.call(arrived and manager.state == PoiInstanceManager.State.INDOOR, "%s E key enters %s through the player input path" % ["Physical" if physical else "Logical", destination])

static func _check_retained(manager: PoiInstanceManager, player: CharacterBody3D, check: Callable) -> void:
	var source := manager._retained_viewport
	check.call(player.get_parent() == manager._retained_interior and source.process_mode == Node.PROCESS_MODE_DISABLED and source.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Destination build keeps player in the frozen source World3D")
	check.call(manager._display.visible and manager._display.texture == source.get_texture(), "Destination build retains the source frame until the new interior is ready")

static func _failed_child(tree: SceneTree, arena: Node3D, manager: PoiInstanceManager, player: CharacterBody3D, building: Node3D, id: String, shelter_door_pose: Transform3D, shelter_return: Transform3D, check: Callable) -> void:
	for mode in ["build failure", "timeout"]:
		manager.interior_factory = Callable()
		# Restore an existing manifest with a different caller seed: saved layout
		# remains authoritative for the chosen access as well as the room plan.
		await manager.enter(player, building, id, 10101 if mode == "build failure" else 20202)
		if not _inside(manager, player, id, &"megashelter", check): return
		check.call(manager.interior.link_doors[&"megashelter_stairwell"].global_transform.is_equal_approx(shelter_door_pose) and manager.interior.link_return_transforms[&"megashelter_stairwell"].is_equal_approx(shelter_return), "Saved layout seed keeps stair access stable when the caller seed changes")
		var source := manager.interior.snapshot()
		var child: Dictionary = manager.saved_instances[id + ":stairs"].duplicate(true)
		manager.interior_factory = func(): return FailedChild.new()
		manager.enter_link(&"megashelter_stairwell")
		var retained: bool = await WAIT.until(tree, func(): return is_instance_valid(manager._retained_viewport), 5000)
		check.call(retained, mode + " reaches a child build while retaining the source")
		if retained: _check_retained(manager, player, check)
		if mode == "timeout":
			manager._deadline = 0
			manager._process(0)
		var settled: bool = await WAIT.until(tree, func(): return not manager.busy, 5000)
		check.call(settled and manager.state == PoiInstanceManager.State.FAILED and manager.active_id.is_empty() and manager._route_stack.is_empty(), mode + " clears the failed child route")
		check.call(player.get_parent() == arena and not player.in_ui_mode, mode + " restores outdoor player ownership and controls")
		check.call(manager.saved_instances.get(id, {}) == source and manager.saved_instances.get(id + ":stairs", {}) == child, mode + " commits the source without overwriting the prior child save")
		var retired: bool = await WAIT.until(tree, func(): return not manager.get_children().any(func(node): return node is SubViewport), 10000)
		check.call(retired and manager.viewport == null and manager._retained_viewport == null and manager.interior == null and manager._retained_interior == null, mode + " retires both source and destination viewports")
	manager.interior_factory = Callable()

static func _direct_bunker(tree: SceneTree, arena: Node3D, manager: PoiInstanceManager, player: CharacterBody3D, check: Callable) -> void:
	# Keep the existing outdoor bunker route independent of nested return history.
	var building := Node3D.new()
	building.name = "DirectBunkerEntrance"
	building.set_meta("poi_interior_profile", &"bunker")
	var marker := Marker3D.new()
	marker.name = "ReturnPoint"
	building.add_child(marker)
	arena.add_child(building)
	manager.interior_factory = func(): return DirectInterior.new()
	await manager.enter(player, building, "direct-after-chain", 913)
	if _inside(manager, player, "direct-after-chain", &"bunker", check):
		await _interact(tree, manager, player, manager.interior.exit_door, check)
		check.call(manager.state == PoiInstanceManager.State.OUTDOOR and player.get_parent() == arena, "Direct outdoor bunker exit returns outdoors without a stale stairwell route")
	manager.interior_factory = Callable()
	building.queue_free()
