extends SceneTree
const WAIT = preload("res://tests/support/test_wait.gd")
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func run() -> void:
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var profile := WorldProfile.new()
	profile.generation_version = 8
	var field := WorldField.new(42, profile)
	var band := -1
	var plan: Dictionary
	for candidate in range(3, 100):
		var data := RoadSpawns.plan(field, candidate)
		if not data.monsters.is_empty() and not (data.wrecks.is_empty() and data.strips.is_empty()):
			band = candidate
			plan = data
			break
	check(band >= 3, "Fixture finds a seeded mixed road encounter")
	if band < 3: quit(1); return
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
	check(container.get_child_count() == plan.monsters.size(), "Ready navigation creates the planned Rakers")
	chunk._spawn_road_monsters()
	check(container.get_child_count() == plan.monsters.size(), "Readiness notification is idempotent")
	var poses: Array[Transform3D] = []
	for child in chunk.get_children():
		if child is Node3D: poses.append(child.global_transform)
	for monster: Monster in container.get_children():
		monster.set_physics_process(false)
		var saved := WorldActorSnapshot.capture(monster)
		check(WorldActorSnapshot.validation_error(saved, "road_monster").is_empty(), "Road Raker uses existing actor snapshot schema")
	chunk.free()
	check(container.get_child_count() == plan.monsters.size(), "Birth chunk unloading leaves pursuing/RV riders alive")
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
	check(container.get_child_count() == plan.monsters.size(), "Generated-band reentry cannot duplicate live Rakers")
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
	generator._despawn_entities_behind(anchor)
	await process_frame
	check(is_instance_valid(near), "Monster within 450 m survives even with a remote birth band")
	check(not is_instance_valid(behind) and not is_instance_valid(ahead), "v8 removes monsters beyond 450 m in both directions")
	check(is_instance_valid(protected), "Loaded walk-in protection is retained")
	generator.profile = profile.duplicate()
	generator.profile.generation_version = 7
	var old_ahead := make_monster(container, Vector3(0, 0, anchor - 700))
	generator._despawn_entities_behind(anchor)
	await process_frame
	check(is_instance_valid(old_ahead), "v7 preserves its original forward cleanup behavior")
	generator.free()
	chunk.free()
	# Full ChunkGenerator bake proves automatic spawn happens after actual
	# server readiness, and static wreck collision participates in that bake.
	var baked := ChunkGenerator.new()
	world.add_child(baked)
	await baked.generate(field, band, POISpawner.new(), true)
	if not await WAIT.navigation_ready(self, [baked]):
		check(false, "Road encounter navigation did not publish before timeout")
	else:
		check(baked.navigation_ready and baked._road_monsters_spawned, "Real navigation publication triggers road monsters")
		var road_monsters := container.get_children().filter(func(n): return n is Monster and n.global_position.distance_to(plan.monsters[0]) < 40)
		check(road_monsters.size() == plan.monsters.size(), "Actual chunk generation creates one planned group")
	world.free()
	await process_frame
	if failures.is_empty(): print("PASS: road navigation readiness, deterministic rebuilding, actor lifetime and v8 cleanup")
	quit(0 if failures.is_empty() else 1)

func make_monster(container: Node3D, point: Vector3) -> Monster:
	var monster: Monster = load("res://enemies/raker.tscn").instantiate()
	container.add_child(monster)
	monster.global_position = point
	monster.set_physics_process(false)
	return monster
