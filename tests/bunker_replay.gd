extends RefCounted
## Same continuous input replay is used by headless checks and the visible playground.
var interior: PoiInterior
var player: CharacterBody3D
var message: Callable
var failures: Array[String] = []
var travelled := 0.0
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
func walk(target: Vector3) -> bool:
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
	var cargo: Prop = preload("res://props/engine_standard.tscn").instantiate()
	interior.entities.add_child(cargo)
	cargo.position = player.position + Vector3(1,0.6,0)
	cargo.freeze = true
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
	check(inside.entities.get_child_count() == 1,"Only player cargo is left in bunker")
	report("PASS / all rooms and return / %.1f metres" % travelled)
	return failures.is_empty()
