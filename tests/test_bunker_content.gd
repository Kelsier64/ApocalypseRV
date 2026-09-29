extends SceneTree
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)
func frames(count: int) -> void:
	for i in count: await physics_frame
func freeze_enemies(inside: PoiInterior) -> Array[Monster]:
	var result: Array[Monster] = []
	for actor in inside.entities.get_children():
		if actor is Monster:
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			result.append(actor)
	return result
func build_inside(seed_value: int, count: int, saved: Dictionary = {}) -> PoiInterior:
	var inside := PoiInterior.new()
	inside.room_count = count
	inside.target_floors = 3
	inside.instance_id = "content-test:%d" % seed_value
	root.add_child(inside)
	current_scene = inside
	check(await inside.build(seed_value, saved), "Populated bunker builds %d rooms" % count)
	freeze_enemies(inside)
	return inside
func _run() -> void:
	for count in [30, 45, 60]:
		var inside := await build_inside(42, count)
		var snapshot := inside.snapshot()
		check(CheckpointSchema.poi_error({"test": snapshot}).is_empty(), "Content snapshot validates")
		check(not inside.content.get("cargo_id", "").is_empty(), "Deep cargo generated")
		var distances := InteriorLayout.distances(inside.layout)
		var cargo_distance := 0.0
		for i in inside.layout.rooms.size():
			if inside.layout.rooms[i].id == inside.content.get("cargo_room", ""): cargo_distance = distances[i]
		check(cargo_distance >= float(distances.max()) * 0.6, "High-value cargo lies in the deeper portion of the connection graph")
		check(inside.caches.size() >= 1 and inside.caches.size() <= 5, "Sparse searchable caches placed")
		if inside.caches.is_empty():
			inside.free()
			quit(1)
			return
		var enemies := freeze_enemies(inside)
		check(enemies.size() <= 4, "Indoor encounters stay within four opportunities")
		for enemy in enemies:
			check(enemy is Raker, "Generated bunker enemy uses Raker")
			check(enemy.position.distance_to(inside.spawn_transform().origin) >= 18, "No enemy at entrance")
		check(BunkerContent.reachable(inside), "Cargo and every cache accessible")
		var map := inside.get_world_3d().navigation_map
		for edge: Vector2i in inside.layout.edges:
			var path := NavigationServer3D.map_get_path(map, inside.navigation_anchor(edge.x), inside.navigation_anchor(edge.y), true)
			check(path.size() > 1 and path[-1].distance_to(inside.navigation_anchor(edge.y)) < 1, "Cache placement keeps every connection open")
		print("BUNKER_CONTENT_TEST rooms=%d actors=%d caches=%d enemies=%d build_ms=%d" % [inside.rooms.size(), inside.entities.get_child_count(), inside.caches.size(), enemies.size(), inside.build_msec])
		if count == 30: await _exercise(inside, snapshot)
		else:
			inside.free()
			await process_frame
	# Independent encounter rolls must support empty, single and multiple outcomes.
	var observed_counts: Dictionary = {}
	for seed_value in range(1, 81):
		var variant := await build_inside(seed_value, 60)
		var variant_enemies := freeze_enemies(variant)
		check(variant_enemies.size() <= 4, "Encounter opportunities never exceed four")
		observed_counts[mini(variant_enemies.size(), 2)] = true
		variant.free()
		await process_frame
		if observed_counts.size() == 3: break
	check(observed_counts.has(0) and observed_counts.has(1) and observed_counts.has(2), "Encounter seeds demonstrate zero, one and many Rakers")
	# Pre-content v3 layouts are authoritative, including completely empty actors.
	var old := {"layout": InteriorLayout.generate(42, 12), "actors": [], "explored": []}
	var legacy := await build_inside(42, 60, old)
	check(legacy.entities.get_child_count() == 0 and legacy.caches.is_empty() and legacy.content.is_empty(), "Visited v3 bunker never retroactively restocks")
	check(legacy.layout == old.layout, "Old twelve-room layout is unchanged")
	legacy.free()
	if failures.is_empty(): print("PASS: bunker content placement, cargo extraction, cache/actor persistence, schema and v3 compatibility")
	quit(0 if failures.is_empty() else 1)
func _exercise(inside: PoiInterior, initial: Dictionary) -> void:
	var player = preload("res://player/player.tscn").instantiate()
	inside.add_child(player)
	player.transform = inside.spawn_transform()
	await frames(10)
	var cache: BunkerCache = inside.caches[0]
	player.position = cache.position + Vector3(0, 0, 1.5)
	var cache_item_id: String = cache.remaining[0].state.id
	cache.interact_hold(player)
	check(player.inventory.items.size() == 1 and player.inventory.items[0].state.id == cache_item_id, "Cache transfers exact saved item")
	check(cache.searched and cache.remaining.size() == 1, "Partly searched cache records remaining item")
	var enemies := freeze_enemies(inside)
	if enemies.size() >= 2:
		enemies[0].take_damage(10)
		enemies[1].take_damage(10000)
	await frames(2)
	var cargo: Prop
	for actor in inside.entities.get_children():
		if actor is Prop and actor.persistent_id == inside.content.cargo_id: cargo = actor
	check(cargo != null, "Objective identifies existing cargo")
	if cargo == null: return
	# Walk the actual baked route, then carry the real generated engine back.
	player.transform = inside.spawn_transform()
	player.velocity = Vector3.ZERO
	var replay = preload("res://tests/bunker_replay.gd").new()
	replay.interior = inside
	replay.player = player
	var approach := NavigationServer3D.map_get_closest_point(inside.get_world_3d().navigation_map, cargo.position + Vector3(0, 0, 1.3))
	check(await replay.route(approach), "Continuous input reaches deep cargo")
	cargo.interact(player)
	await frames(2)
	check(player.inventory.items.any(func(item): return item.state.get("id", "") == inside.content.cargo_id), "Generated upgraded engine can be carried")
	check(await replay.route(inside.spawn_transform().origin), "Continuous input carries reward back to entry")
	var saved := inside.snapshot()
	check(saved.caches[0].remaining.size() == 1 and saved.caches[0].searched, "Snapshot captures searched cache")
	check(not saved.actors.any(func(actor): return actor.get("state", {}).get("id", "") == inside.content.cargo_id), "Carried reward absent from world snapshot")
	var corrupted := saved.duplicate(true)
	corrupted.caches[0].remaining[0].scene = "res://player/player.tscn"
	check(not CheckpointSchema.poi_error({"test": corrupted}).is_empty(), "Untrusted cache scene rejected")
	corrupted = saved.duplicate(true)
	corrupted.content.version = 999
	check(not CheckpointSchema.poi_error({"test": corrupted}).is_empty(), "Unknown content version rejected")
	corrupted = saved.duplicate(true)
	if corrupted.actors.any(func(actor): return actor.has("health")):
		for actor: Dictionary in corrupted.actors:
			if actor.has("health"): actor["state"] = "invalid"
		check(not CheckpointSchema.poi_error({"test": corrupted}).is_empty(), "Malformed enemy state rejected without a script error")
	inside.free()
	await process_frame
	var restored := await build_inside(42, 60, bytes_to_var(var_to_bytes(saved)))
	check(restored.layout == saved.layout and restored.content == saved.content, "Saved geometry and objective never rerolled")
	check(restored.snapshot().caches == saved.caches, "Cache position and exact remaining stock restored")
	check(restored.snapshot().actors == saved.actors, "Positions, health, deaths and extracted reward restored exactly")
	restored.free()
	await process_frame
	# Identical initial seed/scope reproduces loot/caches despite runtime RNG changes.
	seed(97531)
	var repeat := await build_inside(42, 30)
	check(repeat.snapshot() == initial, "Initial content is deterministic and independent of global RNG")
	repeat.free()
	await process_frame
