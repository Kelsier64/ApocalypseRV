extends RefCounted
## Same continuous input replay is used by headless checks and the visible playground.
var interior: PoiInterior
var player: CharacterBody3D
var message: Callable
var failures: Array[String] = []
var travelled := 0.0
var collected_loose_props := 0
var cargo_id := ""
func check(ok: bool, detail: String) -> bool:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)
	return ok
func report(detail: String) -> void:
	print("BUNKER_REPLAY: " + detail)
	if message.is_valid(): message.call(detail)
func frames(count: int) -> void:
	for i in count: await interior.get_tree().physics_frame
func clear_blocking_prop(prop: Prop) -> bool:
	Input.action_release("move_forward")
	if not check(player.inventory.items.size() < PlayerInventory.MAX_SLOTS, "Blocked by %s but inventory is full" % prop.persistent_id): return false
	var identity := prop.persistent_id
	player.look_at(Vector3(prop.global_position.x, player.global_position.y, prop.global_position.z))
	player.camera.look_at(prop.global_position)
	var ray := player.get_node("Camera3D/InteractRay") as RayCast3D
	ray.force_raycast_update()
	var aimed := ray.get_collider() if ray.is_colliding() else null
	if not check(aimed == prop, "Blocked by %s but interaction ray hits %s" % [identity, str(aimed.get_path()) if aimed is Node else "nothing"]): return false
	Input.action_press("interact")
	await frames(2)
	Input.action_release("interact")
	await frames(2)
	if not check(not is_instance_valid(prop) and player.inventory.items.any(func(item: Dictionary) -> bool: return item.get("state", {}).get("id", "") == identity), "Failed to pick up blocking small Prop %s" % identity): return false
	if not check(player.inventory.active_item().get("state", {}).get("id", "") == cargo_id, "Picking up obstruction switched away from carried engine"): return false
	collected_loose_props += 1
	report("Picked up blocking loose Prop %s" % identity)
	return true
func walk(target: Vector3) -> bool:
	var stuck_prop: Prop = null
	var stuck_frames := 0
	for frame in 1200:
		if Vector2(player.position.x-target.x, player.position.z-target.z).length() < 0.22:
			Input.action_release("move_forward")
			await frames(5)
			return check(absf(player.position.y + 0.25-target.y) < 0.8, "Correct floor at %s actual=%s" % [target,player.position])
		player.look_at(Vector3(target.x, player.position.y, target.z))
		player.camera.rotation = Vector3.ZERO
		var before := player.position
		Input.action_press("move_forward")
		await frames(1)
		travelled += before.distance_to(player.position)
		var blocking: Prop = null
		if before.distance_to(player.position) < 0.01:
			for collision_index in player.get_slide_collision_count():
				var collider := player.get_slide_collision(collision_index).get_collider()
				if collider is Prop and not collider.is_large:
					blocking = collider
					break
		if blocking == null:
			stuck_prop = null
			stuck_frames = 0
		elif blocking == stuck_prop:
			stuck_frames += 1
		else:
			stuck_prop = blocking
			stuck_frames = 1
		if stuck_frames >= 18:
			if not await clear_blocking_prop(stuck_prop): return false
			stuck_prop = null
			stuck_frames = 0
			player.camera.rotation = Vector3.ZERO
	Input.action_release("move_forward")
	return check(false, "Blocked walk %s actual=%s" % [target,player.position])
func route(target: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(interior.get_world_3d().navigation_map, player.position, target, true)
	if not check(path.size() > 1 and path[-1].distance_to(target) < 1, "Navigation reaches target"): return false
	for i in range(1,path.size()):
		if not await walk(path[i]): return false
	return true
func run(inside: PoiInterior, actor: CharacterBody3D, callback := Callable()) -> bool:
	interior = inside
	player = actor
	message = callback
	await frames(15)
	var initial_count := interior.entities.get_child_count()
	var cargo: Prop = preload("res://props/engine_standard.tscn").instantiate()
	interior.entities.add_child(cargo)
	cargo.position = player.position + Vector3(1,0.6,0)
	cargo.freeze = true
	cargo_id = cargo.persistent_id
	cargo.interact(player)
	await frames(2)
	check(player.inventory.items.any(func(item): return item.is_large), "Carry large engine")
	for i in inside.rooms.size():
		report("Walking %s / %d rooms / %d floors" % [inside.layout.rooms[i].id,inside.rooms.size(),InteriorLayout.floor_count(inside.layout)])
		if not await route(inside.navigation_anchor(i)): return false
	if not await route(inside.spawn_transform().origin): return false
	check(player.inventory.items.any(func(item): return item.is_large), "Cargo survives complete route")
	player.drop_item()
	await frames(15)
	check(inside.entities.get_child_count() == initial_count - collected_loose_props + 1,"Replay cargo and remaining bunker content keep exact ownership")
	report("PASS / all rooms and return / %.1f metres" % travelled)
	return failures.is_empty()
