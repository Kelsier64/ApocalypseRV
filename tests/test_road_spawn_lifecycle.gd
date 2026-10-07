extends SceneTree
const WAIT = preload("res://tests/support/test_wait.gd")
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func run() -> void:
	for version in [8, 9]: await run_version(version)
	if failures.is_empty(): print("PASS: v8/v9 road readiness, deterministic rebuilding, actor lifetime and cleanup")
	quit(0 if failures.is_empty() else 1)

func run_version(version: int) -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var profile := WorldProfile.new()
	profile.generation_version = version
	var field := WorldField.new(42, profile)
	var band := -1
	var plan: Dictionary
	for candidate in range(3, 1500):
		var data := RoadSpawns.plan(field, candidate)
		if not data.monsters.is_empty() and field.stops_in_band(candidate).is_empty() and not (data.wrecks.is_empty() and data.strips.is_empty()) and (version == 8 or (RoadSpawns.BARREL_MAN_SCENE in data.monster_scenes and RoadSpawns.RAKER_SCENE in data.monster_scenes and not data.get("barrels", []).is_empty())):
			band = candidate
			plan = data
			break
	check(band >= 3, "Fixture finds a seeded mixed road encounter")
	if band < 3: world.free(); return
	var actor_count: int = plan.monsters.size() + plan.get("barrels", []).size()
	var container := WorldEntities.get_container(world)
	var chunk := ChunkGenerator.new()
	world.add_child(chunk)
	chunk.field = field
	chunk.band = band
	chunk.road_spawns = plan
	RoadSpawns.build_static(chunk, plan)
	chunk._spawn_road_monsters()
	check(container.get_child_count() == 0, "No road monster is created before navigation readiness")
	chunk.navigation_ready = true
	chunk._spawn_road_monsters()
	check(container.get_child_count() == actor_count, "Ready navigation creates the planned Rakers")
	for index in range(plan.monsters.size()):
		var enemy := container.get_child(index) as Monster
		check(enemy != null and enemy.scene_file_path == plan.monster_scenes[index], "Published road actor uses the planned species")
		var expected_point: Vector3 = plan.monsters[index] - Vector3.UP * 0.5 if enemy is BarrelMan else plan.monsters[index]
		check(enemy.global_position.is_equal_approx(expected_point), "Road root offset puts barrel feet on ground without shifting Rakers")
		if version >= 9:
			check(enemy.global_basis.is_equal_approx(Basis(Vector3.UP, plan.monster_yaws[index])), "Road monster uses its independent planned yaw")
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	for index in range(plan.get("barrels", []).size()):
		var barrel := container.get_child(plan.monsters.size() + index) as OilBarrel
		check(barrel != null, "Ordinary road barrel is an Item independent of monster species")
		if barrel == null: continue
		barrel.freeze = true
		barrel.process_mode = Node.PROCESS_MODE_DISABLED
		check(barrel.persistent_id == "road:%d:42:%d:barrel:%d" % [version, band, index], "Road barrel has stable per-band identity")
		var pose: Transform3D = plan.barrels[index].transform
		check(barrel.global_transform.is_equal_approx(pose), "Ordinary barrel uses its planned root pose")
		var bottom: Vector3 = barrel.global_transform * Vector3(0, -0.5, 0)
		check(is_equal_approx(bottom.y, RoadSpawns._surface_height(field, bottom)), "Tilted ordinary barrel bottom sits on the terrain or raised road surface")
		check(WorldActorSnapshot.validation_error(WorldActorSnapshot.capture(barrel), "road_barrel").is_empty(), "Road barrel uses the Item snapshot schema")
	chunk._spawn_road_monsters()
	check(container.get_child_count() == actor_count, "Readiness notification is idempotent")
	var poses: Array[Transform3D] = []
	for child in chunk.get_children():
		if child is Node3D: poses.append(child.global_transform)
		if str(child.name).begins_with("RoadWreck"):
			var aligned: Transform3D = child.global_transform * Transform3D(Basis(Vector3.UP, RoadSpawns.WRECK_MODEL_YAW), Vector3.ZERO)
			for mesh: MeshInstance3D in child.find_children("*", "MeshInstance3D", true, false):
				if mesh.mesh == null: continue
				for index in range(8):
					var point := aligned.affine_inverse() * (mesh.global_transform * mesh.mesh.get_aabb().get_endpoint(index))
					check(RoadSpawns.WRECK_BOUNDS.grow(0.01).has_point(point), "Planner bounds contain reused wreck visual %s at %s" % [mesh.name, point])
	for monster: Monster in container.get_children().filter(func(n): return n is Monster):
		monster.process_mode = Node.PROCESS_MODE_DISABLED
		var saved := WorldActorSnapshot.capture(monster)
		check(WorldActorSnapshot.validation_error(saved, "road_monster").is_empty(), "Road Raker uses existing actor snapshot schema")
	chunk.free()
	check(container.get_child_count() == actor_count, "Birth chunk unloading leaves pursuing/RV riders alive")
	chunk = ChunkGenerator.new()
	chunk.set_meta("skip_actors", true)
	world.add_child(chunk)
	chunk.field = field
	chunk.band = band
	chunk.road_spawns = RoadSpawns.plan(field, band)
	RoadSpawns.build_static(chunk, chunk.road_spawns)
	var rebuilt: Array[Transform3D] = []
	for child in chunk.get_children():
		if child is Node3D: rebuilt.append(child.global_transform)
	check(poses == rebuilt, "Static road obstacles rebuild at identical poses")
	chunk.navigation_ready = true
	chunk._spawn_road_monsters()
	check(container.get_child_count() == actor_count, "Generated-band reentry cannot duplicate live Rakers")
	for monster in container.get_children(): monster.free()
	chunk._spawn_road_monsters()
	check(container.get_child_count() == 0, "Killed/removed road monsters do not refill")
	# Exercise the production cleanup method in both directions, including the
	# second container loop and separate World3D isolation.
	var generator: Node3D = load("res://tests/support/road_spawn_generator.gd").new()
	generator.profile = profile
	generator.field = field
	world.add_child(generator)
	var anchor := -(band + 0.5) * 150.0
	var near := make_monster(container, Vector3(0, 0, anchor + 400))
	var behind := make_monster(container, Vector3(0, 0, anchor + 451))
	var ahead := make_monster(container, Vector3(0, 0, anchor - 451))
	var protected := make_monster(container, Vector3(0, 0, anchor - 600))
	var site_chunk := ChunkGenerator.new()
	world.add_child(site_chunk)
	site_chunk.sites = [{"kind": "walk_in", "bounds": AABB(Vector3(-10, -10, anchor - 620), Vector3(20, 30, 40))}]
	generator.active_chunks = [{"node": site_chunk, "index": band}]
	var other_viewport := SubViewport.new()
	other_viewport.own_world_3d = true
	world.add_child(other_viewport)
	var other_world := Node3D.new()
	other_world.set_meta("entity_domain", true)
	other_viewport.add_child(other_world)
	var foreign := make_monster(WorldEntities.get_container(other_world), Vector3(0, 0, anchor + 1000))
	generator._despawn_entities_behind(anchor)
	await process_frame
	check(is_instance_valid(near), "Monster within 450 m survives even with a remote birth band")
	check(not is_instance_valid(behind) and not is_instance_valid(ahead), "v8 removes monsters beyond 450 m in both directions")
	check(is_instance_valid(foreign), "Cleanup does not remove another World3D actor")
	check(is_instance_valid(protected), "Loaded walk-in protection is retained")
	generator.profile = profile.duplicate()
	generator.profile.generation_version = 7
	var old_ahead := make_monster(container, Vector3(0, 0, anchor - 700))
	generator._despawn_entities_behind(anchor)
	await process_frame
	check(is_instance_valid(old_ahead), "v7 preserves its original forward cleanup behavior")
	generator.free()
	chunk.free()
	for actor in container.get_children(): actor.free()
	# Full ChunkGenerator bake proves automatic spawn happens after actual
	# server readiness, and static wreck collision participates in that bake.
	container.child_entered_tree.connect(freeze_actor)
	var baked := ChunkGenerator.new()
	world.add_child(baked)
	await baked.generate(field, band, POISpawner.new(), true)
	if not await WAIT.navigation_ready(self, [baked]):
		check(false, "Road encounter navigation did not publish before timeout")
	else:
		var nav_map := baked.get_world_3d().navigation_map
		var excluded: Array[RID] = []
		for actor in container.get_children():
			if actor is CollisionObject3D: excluded.append(actor.get_rid())
			for body in actor.find_children("*", "CollisionObject3D", true, false): excluded.append(body.get_rid())
		for index in range(plan.monsters.size()):
			var point: Vector3 = plan.monsters[index]
			var closest := NavigationServer3D.map_get_closest_point(nav_map, point)
			var distance := closest.distance_to(point)
			if version == 8:
				check(distance < 2.0, "Legacy road spawn is reachable on published navigation point=%s closest=%s distance=%.3f" % [point, closest, distance])
				continue
			# Outdoor navigation simplifies terrain height. Monsters follow the XZ
			# path while physics grounds them; verify both contracts independently.
			var planar_distance := Vector2(point.x, point.z).distance_to(Vector2(closest.x, closest.z))
			check(planar_distance < 2.0, "v9 road spawn reaches XZ navigation band=%d point=%s closest=%s planar=%.3f" % [band, point, closest, planar_distance])
			var root_point: Vector3 = point - Vector3.UP * 0.5 if plan.monster_scenes[index] == RoadSpawns.BARREL_MAN_SCENE else point
			var query := PhysicsRayQueryParameters3D.create(root_point + Vector3.UP * 2.0, root_point - Vector3.UP * 4.0, 1)
			query.exclude = excluded
			var hit := baked.get_world_3d().direct_space_state.intersect_ray(query)
			check(not hit.is_empty() and absf(root_point.y - hit.position.y) < 0.75, "v9 road actor has physical ground support root=%s hit=%s" % [root_point, hit])
			var road := field.road_query(point.x, point.z)
			var connected := false
			var path_details: Array[String] = []
			for offset in [-10.0, 10.0]:
				var target: Vector3 = field.road_frame(float(road.s) + offset).origin
				if floori(-target.z / field.profile.chunk_length) != band: continue
				var path := NavigationServer3D.map_get_path(nav_map, point, target, true)
				if path.is_empty():
					path_details.append("target=%s empty" % target)
					continue
				var endpoint: Vector3 = path[path.size() - 1]
				var endpoint_gap := Vector2(endpoint.x, endpoint.z).distance_to(Vector2(target.x, target.z))
				path_details.append("target=%s endpoint=%s planar_gap=%.3f" % [target, endpoint, endpoint_gap])
				if endpoint_gap < 2.0: connected = true
			check(connected, "v9 road spawn has a connected path to nearby road point=%s paths=%s" % [point, path_details])
		check(baked.navigation_ready and baked._road_monsters_spawned, "Real navigation publication triggers road monsters")
		var road_monsters := container.get_children().filter(func(n): return n is Monster)
		check(road_monsters.size() == plan.monsters.size(), "Actual generation creates all independent planned monsters regardless of distance")
		var road_barrels := container.get_children().filter(func(n): return n is OilBarrel)
		check(road_barrels.size() == plan.get("barrels", []).size(), "Actual navigation publication also creates ordinary road barrels")
		for barrel in road_barrels: barrel.free()
		# Tree destruction rebakes the same region after the initial publication.
		# Removed road actors must remain absent when that callback runs again.
		for monster in road_monsters: monster.free()
		var remaining := container.get_child_count()
		var region := baked.navigation
		baked.request_navigation_rebuild()
		await baked._navigation_rebuild_timer.timeout
		if not await WAIT.navigation_ready(self, [baked]):
			check(false, "Tree-triggered navigation rebake publishes before timeout")
		else:
			check(baked.navigation == region, "Runtime rebake reuses the original navigation region")
			check(container.get_child_count() == remaining, "Tree-triggered rebake does not resurrect removed road Rakers")
	world.free()
	await process_frame

func make_monster(container: Node3D, point: Vector3) -> Monster:
	var monster: Monster = load("res://enemies/raker.tscn").instantiate()
	container.add_child(monster)
	monster.global_position = point
	monster.set_physics_process(false)
	return monster

func freeze_actor(actor: Node) -> void:
	if actor is Monster: actor.process_mode = Node.PROCESS_MODE_DISABLED
	elif actor is OilBarrel:
		actor.freeze = true
		actor.process_mode = Node.PROCESS_MODE_DISABLED
