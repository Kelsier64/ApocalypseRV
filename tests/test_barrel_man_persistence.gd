extends SceneTree
## Real actor and outdoor owner round trips; AI stays disabled for exact captures.
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func run() -> void:
	node_added.connect(func(node):
		if node is Monster: node.process_mode = Node.PROCESS_MODE_DISABLED)
	var world := Node3D.new()
	world.set_meta("entity_domain", true)
	root.add_child(world)
	current_scene = world
	var container := WorldEntities.get_container(world)
	check(SaveSceneCatalog.resolve(RoadSpawns.BARREL_MAN_SCENE, "monster") != null, "Barrel actor scene is trusted")
	check(SaveSceneCatalog.resolve(RoadSpawns.BARREL_MAN_SCENE, "item") == null, "Barrel monster cannot enter item inventory")
	for phase in range(4):
		var actor: Monster = load(RoadSpawns.BARREL_MAN_SCENE).instantiate()
		container.add_child(actor)
		actor.global_position = Vector3(2, 0, -3)
		actor.current_health = 43.0
		var height := 0.5 if phase == 0 else (1.4 if phase == 2 else 0.82)
		var state := {"phase": phase, "phase_elapsed": 0.31, "visual_height": height, "lost_interest_elapsed": 1.4}
		actor.restore_barrel_state(state)
		var captured := WorldActorSnapshot.capture(actor)
		check(WorldActorSnapshot.validation_error(captured, "actor").is_empty(), "Every live barrel phase validates")
		actor.free()
		var restored := WorldActorSnapshot.restore(bytes_to_var(var_to_bytes(captured)), container)
		check(WorldActorSnapshot.capture(restored) == captured, "Phase, animation progress, transform and reduced HP round trip exactly")
		check(restored.proximity_fuse_remaining < 0.0 and not captured.barrel.has("proximity_fuse_remaining"), "Existing barrel records restore unarmed and retain their exact dictionary shape")
		var corrupt := captured.duplicate(true)
		corrupt.barrel.phase = 4
		check(not WorldActorSnapshot.validation_error(corrupt, "actor").is_empty(), "Detonated barrel cannot be restored alive")
		corrupt = captured.duplicate(true)
		corrupt.barrel.phase_elapsed = NAN
		check(not WorldActorSnapshot.validation_error(corrupt, "actor").is_empty(), "Non-finite animation progress rejected")
		corrupt = captured.duplicate(true)
		corrupt.scene = RoadSpawns.RAKER_SCENE
		check(not WorldActorSnapshot.validation_error(corrupt, "actor").is_empty(), "Barrel state on unrelated species rejected")
		restored.is_dead = true
		check(WorldActorSnapshot.capture(restored).is_empty(), "Exploded barrel absent from actor records")
		restored.free()
	await exercise_fuse_snapshots(container)
	var old_raker := {"kind": "monster", "scene": RoadSpawns.RAKER_SCENE, "health": 37.0, "transform": Transform3D.IDENTITY}
	check(WorldActorSnapshot.validation_error(old_raker, "old").is_empty(), "Existing v5 Raker record remains valid")
	var old_actor := WorldActorSnapshot.restore(old_raker, container)
	check(old_actor is Raker and is_equal_approx(old_actor.current_health, 37.0), "Old actor species and HP stay authoritative")
	old_actor.free()
	await exercise_minor(world, container)
	world.free()
	await process_frame
	if failures.is_empty(): print("PASS: barrel snapshot validation, proximity fuse/legacy restore, deterministic minor species and decoy no-restock")
	quit(0 if failures.is_empty() else 1)

func exercise_fuse_snapshots(container: Node3D) -> void:
	var actor: BarrelMan = load(RoadSpawns.BARREL_MAN_SCENE).instantiate()
	container.add_child(actor)
	var state := {"phase": BarrelMan.Phase.CHASE, "phase_elapsed": 0.31, "visual_height": 1.4, "lost_interest_elapsed": 1.4, "proximity_fuse_remaining": 0.37}
	actor.restore_barrel_state(state)
	var captured := WorldActorSnapshot.capture(actor)
	check(WorldActorSnapshot.validation_error(captured, "armed").is_empty(), "Armed countdown is accepted by the actor snapshot validator")
	actor.free()
	var restored: BarrelMan = WorldActorSnapshot.restore(bytes_to_var(var_to_bytes(captured)), container)
	check(restored != null, "Serialized armed barrel restores as a live actor")
	if restored == null: return
	check(WorldActorSnapshot.capture(restored) == captured and is_equal_approx(restored.proximity_fuse_remaining, 0.37), "Armed actor snapshot preserves exact remaining countdown across binary round trip")
	restored._update_proximity_fuse(0.25)
	check(is_equal_approx(restored.proximity_fuse_remaining, 0.12) and not restored.is_dead, "Restored committed countdown resumes without any target")
	var old_state := state.duplicate()
	old_state.erase("proximity_fuse_remaining")
	restored.restore_barrel_state(old_state)
	check(restored.proximity_fuse_remaining < 0.0 and restored.capture_barrel_state() == old_state, "Applying a legacy barrel state clears a previously armed countdown")
	for bad_value in [NAN, INF, -INF, -1.0, -0.001, 60.001, "0.2", true, null]:
		var corrupt := captured.duplicate(true)
		corrupt.barrel.proximity_fuse_remaining = bad_value
		check(not WorldActorSnapshot.validation_error(corrupt, "armed").is_empty(), "Invalid optional fuse value is rejected: %s" % str(bad_value))
	for valid_value in [0, 0.5, 60.0]:
		var valid := captured.duplicate(true)
		valid.barrel.proximity_fuse_remaining = valid_value
		check(WorldActorSnapshot.validation_error(valid, "armed").is_empty(), "Finite fuse boundary within zero to sixty seconds is valid: %s" % str(valid_value))
	restored.restore_barrel_state(state)
	restored._update_proximity_fuse(0.371)
	check(restored.is_dead and WorldActorSnapshot.capture(restored).is_empty(), "Resumed fuse expiry removes actor from saves immediately before deferred blast resolution")
	await process_frame
	await physics_frame

func exercise_minor(world: Node3D, container: Node3D) -> void:
	var generator: Node3D = load("res://tests/support/road_spawn_generator.gd").new()
	world.add_child(generator)
	var chunk := Node3D.new()
	world.add_child(chunk)
	var building: Node3D = load("res://world/roadside_pois/cargo_0.tscn").instantiate()
	building.set_meta("poi_id", "barrel-site")
	chunk.add_child(building)
	await physics_frame
	await physics_frame
	var site := {"id": "barrel-site", "index": 7, "definition_id": "roadside_cargo_0", "minor": true, "bounds": AABB(Vector3(-30, -10, -30), Vector3(60, 30, 60))}
	var profile := WorldProfile.new()
	var observed_species := {}
	var persisted := false
	profile.generation_version = 7
	generator.field = WorldField.new(42, profile)
	WalkInSites.activate(generator, site, chunk)
	for actor in container.get_children():
		if actor is Monster: check(actor is Raker, "v7 outdoor species remains exactly Raker")
		if actor is Item: check(actor.persistent_id != "outdoor:barrel-site:barrel_decoy", "v7 receives no new decoy")
		actor.free()
	for seed_value in range(50):
		profile.generation_version = 8
		generator.field = WorldField.new(seed_value, profile)
		# Reproduce the existing marker/count RNG with the SAME generation
		# version: generation version itself is part of WorldField's RNG seed.
		var legacy_loot: Array = []
		var loot_rng: RandomNumberGenerator = generator.field.rng_for(site.index, "minor_loot")
		for point in building.find_children("*", "Marker3D", true, false):
			if not point is PoiLootPoint: continue
			var scene: PackedScene = point.roll_scene(loot_rng)
			if scene == null: continue
			var prop: Item = scene.instantiate()
			legacy_loot.append({"scene": scene.resource_path, "transform": point.global_transform, "name": prop.item_name})
			prop.free()
		var legacy_monsters: Array[Vector3] = []
		var enemy_rng: RandomNumberGenerator = generator.field.rng_for(site.index, "minor_enemies")
		var points := building.get_node("EnemySpawns").get_children()
		for index in range(enemy_rng.randi_range(0, 2)):
			legacy_monsters.append(points.pop_at(enemy_rng.randi_range(0, points.size() - 1)).global_position)
		generator.outdoor_sites.clear()
		WalkInSites.activate(generator, site, chunk)
		check(loot_signature(container) == legacy_loot, "v8 species and guaranteed decoy do not consume existing loot RNG")
		var monsters := container.get_children().filter(func(node): return node is Monster)
		check(monsters.size() == legacy_monsters.size(), "Species substitution preserves existing enemy slot count")
		for index in range(monsters.size()):
			var actor: Monster = monsters[index]
			observed_species[actor.scene_file_path] = true
			check((actor is Raker and actor.scene_file_path == RoadSpawns.RAKER_SCENE) or (actor is BarrelMan and actor.scene_file_path == RoadSpawns.BARREL_MAN_SCENE), "Minor enemy uses an exact approved species")
			check(Vector2(actor.global_position.x, actor.global_position.z).is_equal_approx(Vector2(legacy_monsters[index].x, legacy_monsters[index].z)), "Species substitution preserves selected spawn marker")
			if actor is BarrelMan:
				check(is_equal_approx(actor.global_position.y, WalkInSites._ground_position(building, legacy_monsters[index], actor).y), "Barrel root sits on actual POI ground")
		var decoys := container.get_children().filter(func(node): return node is Item and node.persistent_id == "outdoor:barrel-site:barrel_decoy")
		check(decoys.size() == 1, "Every new eligible v8 site owns one normal Item decoy independent of enemies")
		if not persisted and observed_species.has(RoadSpawns.BARREL_MAN_SCENE):
			for actor in container.get_children():
				if actor is Item: actor.freeze = true
			WalkInSites.deactivate(generator, site)
			var dormant: Dictionary = generator.outdoor_sites[site.id].duplicate(true)
			check(not dormant.loaded and not dormant.actors.is_empty(), "Owner unload saves real barrel and ordinary decoy")
			generator.outdoor_sites[site.id] = bytes_to_var(var_to_bytes(dormant))
			WalkInSites.activate(generator, site, chunk)
			var returned: Array = []
			for actor in container.get_children(): returned.append(WorldActorSnapshot.capture(actor))
			check(returned == dormant.actors, "Site reentry restores exact records without rerolling species, HP or decoy identity")
			for actor in container.get_children(): actor.free()
			generator.outdoor_sites[site.id] = {"definition_id": "roadside_cargo_0", "content_version": 1, "loaded": false, "actors": []}
			WalkInSites.activate(generator, site, chunk)
			check(container.get_child_count() == 0, "Previously cleared site restores no monsters or decoy")
			persisted = true
		for actor in container.get_children(): actor.free()
	check(observed_species.has(RoadSpawns.RAKER_SCENE) and observed_species.has(RoadSpawns.BARREL_MAN_SCENE), "Minor seed scan exercises both species")
	check(persisted, "Seed scan exercised barrel-bearing owner persistence")
	generator.free()
	chunk.free()

func loot_signature(container: Node3D) -> Array:
	var result: Array = []
	for actor in container.get_children():
		if actor is Item and actor.persistent_id != "outdoor:barrel-site:barrel_decoy":
			result.append({"scene": actor.scene_file_path, "transform": actor.global_transform, "name": actor.item_name})
	return result

