extends SceneTree
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func _run() -> void:
	for seed_value in range(100):
		var layout := MazeLayout.generate(seed_value)
		check(layout == MazeLayout.generate(seed_value), "Layout seed must replay exactly")
		check(layout.rooms.size() >= 50 and layout.rooms.size() <= 100, "Room budget")
		var reached := {0: true}
		for i in range(layout.rooms.size()):
			for edge: Vector2i in layout.edges:
				if reached.has(edge.x) or reached.has(edge.y):
					reached[edge.x] = true
					reached[edge.y] = true
		check(reached.size() == layout.rooms.size(), "Every room reachable")
		check(layout.edges.size() >= layout.rooms.size() + 2, "Maze has loops")
	for path in ["res://world/poi_kit/rooms/maze_utility.tscn", "res://world/poi_kit/rooms/maze_hall.tscn"]:
		var room: PoiRoom = load(path).instantiate()
		check(room.validate().is_empty(), "Authored maze room contracts: " + path)
		room.free()
	var main: Node3D = load("res://world/test_world.tscn").instantiate()
	main.get_node("WorldGenerator").world_seed = 42
	# The production sandbox may omit its debug enemy; this test owns its AI fixture.
	if not main.has_node("Zombie"):
		var enemy: Monster = load("res://enemies/zombie.tscn").instantiate()
		enemy.name = "Zombie"
		enemy.position = Vector3(0, 1, 8)
		main.add_child(enemy)
	root.add_child(main)
	current_scene = main
	# Registration occurs during ready; current_scene is set after adding in SceneTree tests.
	var manager := main.get_node("PoiInstances") as PoiInstanceManager
	var player = main.get_node("Player")
	var first_chunk: Node = main.get_node("WorldGenerator").active_chunks[2].node
	var building: Node3D
	for child in first_chunk.get_children():
		if child.has_node("Entrance"):
			building = child
	check(building != null, "Starting chunk guarantees an exterior")
	if building == null:
		quit(1)
		return
	if not building.has_meta("poi_id"):
		manager.register_entrance(building, 42)
	await frames(15)
	player.global_transform = building.get_node("ReturnPoint").global_transform
	player.global_basis = building.global_basis
	player.velocity = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	await frames(15)
	Input.action_press("interact")
	await frames(10)
	Input.action_release("interact")
	# Main scene tests intentionally use real interaction, not a direct enter call.
	var deadline := Time.get_ticks_msec() + 60000
	while (manager.busy or manager.interior == null) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(manager.interior != null and not manager.busy, "Main entrance ray enters instance")
	if manager.interior == null or manager.busy:
		quit(1)
		return
	var inside := manager.interior
	var clock: WorldClock = main.get_node("WorldClock")
	clock.weather.set_weather(Vector3(0, 2, 2), true)
	var weather_before := clock.weather.remaining
	await frames(5)
	check(clock.weather.remaining < weather_before, "Weather keeps advancing inside POI")
	check(clock.get_node("WeatherRain").visible_drops == 0, "Independent indoor world has no outdoor rain")
	check(not WorldEntities.same_world(player, main), "Independent physics world")
	check(WorldEntities.get_container(player) == inside.entities, "Indoor drops owned by indoor container")
	var outdoor: Monster = main.get_node("Zombie")
	outdoor.target_player = player
	await frames(5)
	check(outdoor.target_player == null, "Cached outdoor target cleared across worlds")
	check(outdoor._collect_player_candidates().is_empty(), "Outdoor AI cannot select indoor player")
	var chassis = main.get_node("NewRv/Chassis")
	var power_before: float = chassis.current_power
	await frames(60)
	check(chassis.current_power < power_before, "Overworld power drains during indoor visit")
	var chunks: int = main.get_node("WorldGenerator").active_chunks.size()
	player.position.z = -2000
	await frames(5)
	check(main.get_node("WorldGenerator").active_chunks.size() == chunks, "Indoor coordinates do not drive outdoor streaming")
	player.position = Vector3(0, 0.05, 2.5)
	var initial_count := inside.entities.get_child_count()
	var loot := inside.entities.get_child(0) as Prop
	loot.scrap_yields = {"Metal Parts": Vector2(7, 7)}
	loot.interact(player)
	await frames(2)
	check(player.inventory.items.size() == 1, "Pickup keeps inventory")
	player.drop_item()
	await frames(2)
	var dropped := inside.entities.get_child(-1) as Prop
	check(dropped.scrap_yields == {"Metal Parts": Vector2(7, 7)}, "Dropped loot preserves rolled yield")
	var indoor_enemy: Monster
	for actor in inside.entities.get_children():
		if actor is Monster:
			indoor_enemy = actor
			break
	check(indoor_enemy != null, "Indoor enemies spawned")
	indoor_enemy.take_damage(10000)
	await frames(5)
	check(inside.entities.get_child(-1) is Prop, "Dead indoor enemy drops in its own world")
	var expected := inside.snapshot()
	var id := manager.active_id
	await manager.leave()
	await frames(35)
	check(WorldEntities.same_world(player, main), "Exit returns original World3D")
	check(player.global_position.distance_to(building.get_node("ReturnPoint").global_position) < 6, "Exit returns near exterior landing")
	await manager.enter(player, building, id, int(building.get_meta("poi_seed")))
	check(manager.interior.entities.get_child_count() == expected.actors.size(), "Reentry preserves deaths, pickups and drops")
	check(manager.interior.entities.get_child_count() == initial_count, "Killed enemy replaced only by its loot")
	var restored_custom := false
	for actor in manager.interior.entities.get_children():
		if actor is Prop and actor.scrap_yields == {"Metal Parts": Vector2(7, 7)}:
			restored_custom = true
	check(restored_custom, "Reentry retains per-instance loot data")
	# Every link must be traversable in the baked geometry, including mixed sizes.
	await frames(5)
	var map := manager.interior.get_world_3d().navigation_map
	for edge: Vector2i in manager.interior.layout.edges:
		var a := manager.interior.rooms[edge.x].global_position
		var b := manager.interior.rooms[edge.y].global_position
		var path := NavigationServer3D.map_get_path(map, a, b, true)
		check(path.size() >= 2 and path[-1].distance_to(b) < 1, "Baked navigation connects furnished rooms %s" % edge)
	await manager.leave()
	await process_frame
	main.free()
	if failures.is_empty():
		print("PASS: 100 maze seeds; production entry, world isolation, power, persistence and navigation")
	quit(0 if failures.is_empty() else 1)
