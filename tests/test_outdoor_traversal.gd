extends SceneTree
var failures: Array[String] = []
var player: CharacterBody3D
var site: Dictionary
var field: WorldField

func _init() -> void: _run.call_deferred()

func check(okay: bool, message: String) -> void:
	if not okay:
		failures.append(message)
		push_error("FAIL: " + message)

func _walk(points: PackedVector3Array) -> float:
	var ticks := 0
	for target in points:
		var reached := false
		for i in range(1300):
			if Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() < 0.3:
				reached = true
				break
			player.look_at(Vector3(target.x, player.global_position.y, target.z))
			player.camera.rotation = Vector3.ZERO
			Input.action_press("move_forward")
			await physics_frame
			ticks += 1
		Input.action_release("move_forward")
		check(reached, "Actual player reaches waypoint %s from %s" % [target, player.global_position])
		if not reached: break
	return ticks / 60.0

func _run() -> void:
	var main: Node3D = load("res://world/test_world.tscn").instantiate()
	var generator = main.get_node("WorldGenerator")
	generator.world_seed = 42
	generator.profile = WorldProfile.new()
	generator.profile.chunks_ahead = 1
	generator.profile.chunks_behind = 1
	root.add_child(main)
	current_scene = main
	field = generator.field
	site = field.stop(0)
	for monster in get_nodes_in_group(Groups.MONSTERS): monster.queue_free()
	player = main.get_node("Player")
	player.global_position = site.route[0] + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	var engine := EngineState.new()
	var item := engine.item()
	player.add_item(item.name, true, item.scene_path, item.state)
	var seconds := await _walk(site.route)
	print("OUTDOOR carry-engine seconds=", seconds)
	check(seconds >= 95 and seconds <= 120, "Real 5m/s forest route takes 95-120 seconds")
	check(player.inventory.active_item().state.engine.id == engine.id, "Engine survives transport")
	var building: Node3D = get_first_node_in_group("poi_entrances")
	var manager := main.get_node("PoiInstances") as PoiInstanceManager
	player.global_basis = building.global_basis
	player.camera.rotation = Vector3.ZERO
	# Use actual E ray at the end of the walked route.
	for i in range(5): await physics_frame
	Input.action_press("interact")
	for i in range(10): await physics_frame
	Input.action_release("interact")
	var deadline := Time.get_ticks_msec() + 20000
	while (manager.busy or manager.interior == null) and Time.get_ticks_msec() < deadline: await process_frame
	check(manager.interior != null and not manager.busy, "Walked-to entrance loads existing instance")
	if manager.interior != null and not manager.busy:
		check(not main.get_node("OutdoorPresentation").effect.visible, "Interior transition removes outdoor filter")
		await manager.leave()
		check(player.inventory.active_item().state.engine.id == engine.id, "Instance return keeps carried engine")
	player.inventory.consume_active()
	player.add_item("Oil Barrel", true, "res://props/oil_barrel.tscn")
	var back: PackedVector3Array = site.route.duplicate()
	back.reverse()
	await _walk(back)
	check(player.inventory.active_item().is_large, "Large barrel passes every gap on return")
	main.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: production player, engine carry, real entrance, interior return and barrel walk back")
	quit(0 if failures.is_empty() else 1)
