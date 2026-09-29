extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)
func _run() -> void:
	var inside: PoiInterior
	var enemies: Array[Monster] = []
	var encounter_seed := -1
	for seed_value in range(1, 81):
		inside = PoiInterior.new()
		inside.room_count = 60
		inside.target_floors = 3
		root.add_child(inside)
		current_scene = inside
		if not await inside.build(seed_value):
			check(false, "Encounter dungeon builds")
			quit(1)
			return
		enemies.clear()
		for actor in inside.entities.get_children():
			if actor is Monster:
				actor.process_mode = Node.PROCESS_MODE_DISABLED
				enemies.append(actor)
		if enemies.size() >= 2:
			encounter_seed = seed_value
			break
		inside.free()
		await process_frame
	if enemies.size() < 2:
		check(false, "An encounter seed supplies two real spawned enemies")
		quit(1)
		return
	var enemy := enemies[0]
	check(enemy is Raker and enemies[1] is Raker, "Encounter spawns Rakers")
	var player = preload("res://player/player.tscn").instantiate()
	inside.add_child(player)
	player.set_physics_process(false)
	var map := inside.get_world_3d().navigation_map
	var found := false
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var candidate := NavigationServer3D.map_get_closest_point(map, enemy.position + direction * 4.0)
		var path := NavigationServer3D.map_get_path(map, enemy.position, candidate, true)
		var distance := candidate.distance_to(enemy.position)
		var path_length := 0.0
		for i in range(1, path.size()): path_length += path[i].distance_to(path[i-1])
		if distance >= 3.0 and distance <= 5.0 and path.size() > 1 and path_length < 6.0 and absf(candidate.y - enemy.position.y) < 0.7:
			player.position = candidate - Vector3.UP * 0.25
			found = true
			break
	check(found, "Player can stand in a nearby reachable detection area")
	var before: Vector3 = enemy.position
	var initial_health: float = player.current_player_health
	enemy.process_mode = Node.PROCESS_MODE_INHERIT
	for i in 360:
		await physics_frame
		if player.current_player_health < initial_health: break
	check(enemy.target_player == player, "Spawned indoor enemy detects the real same-world player")
	check(enemy.position.distance_to(before) > 0.5, "Spawned indoor enemy follows navigation toward player")
	check(player.current_player_health < initial_health, "Spawned indoor enemy reaches and damages player")
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	var survivor_id: String = enemy.get_meta("bunker_actor_id")
	var dead_id: String = enemies[1].get_meta("bunker_actor_id")
	var survivor_health := enemy.current_health - 11.0
	enemy.take_damage(11)
	enemies[1].take_damage(10000)
	await process_frame
	check(is_equal_approx(enemy.current_health, survivor_health) and enemies[1].is_dead, "Damage and death occurred before capture")
	var saved := inside.snapshot()
	check(saved.actors.any(func(actor): return actor.get("id", "") == survivor_id and is_equal_approx(float(actor.get("health", -1)), survivor_health)), "Snapshot records reduced survivor health")
	check(not saved.actors.any(func(actor): return actor.get("id", "") == dead_id), "Dead enemy excluded from snapshot")
	inside.free()
	await process_frame
	var restored := PoiInterior.new()
	root.add_child(restored)
	current_scene = restored
	check(await restored.build(encounter_seed, bytes_to_var(var_to_bytes(saved))), "Encounter state restores")
	var restored_enemies: Array[Monster] = []
	for actor in restored.entities.get_children():
		if actor is Monster:
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			restored_enemies.append(actor)
	check(restored_enemies.size() == enemies.size() - 1, "Killed enemy does not respawn")
	check(restored_enemies.any(func(actor): return actor.get_meta("bunker_actor_id", "") == survivor_id and is_equal_approx(actor.current_health, survivor_health)), "Surviving enemy identity and health survive reentry")
	restored.free()
	if failures.is_empty(): print("PASS: generated bunker enemy detection, navigation, damage, death and persistent survivor health")
	quit(0 if failures.is_empty() else 1)
