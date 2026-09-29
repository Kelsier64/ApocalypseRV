extends SceneTree
## The generated reward must leave through the player-facing exit and survive disk restore.
const SAVE_PATH := "res://.godot/test-bunker-extraction.save"
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func frames(count: int) -> void:
	for i in count: await physics_frame

func freeze_enemies(inside: PoiInterior) -> void:
	for actor in inside.entities.get_children():
		if actor is Monster: actor.process_mode = Node.PROCESS_MODE_DISABLED

func find_cargo(inside: PoiInterior, identity: String) -> Prop:
	for actor in inside.entities.get_children():
		if actor is Prop and actor.persistent_id == identity: return actor
	return null

func carried_engine(player: Node3D, identity: String) -> Dictionary:
	for item: Dictionary in player.inventory.items:
		if item.get("state", {}).get("engine", {}).get("id", "") == identity: return item
	return {}

func find_entrance(world: Node3D, identity := "") -> Node3D:
	var generator = world.get_node("WorldGenerator")
	for chunk in generator.active_chunks:
		for child in chunk.node.get_children():
			if child.has_node("Entrance") and (identity.is_empty() or child.get_meta("poi_id", "") == identity): return child
	return null

func _run() -> void:
	var world: Node3D = load("res://world/test_world.tscn").instantiate()
	world.get_node("WorldGenerator").world_seed = 42
	root.add_child(world)
	current_scene = world
	check(await world.wait_for_play(60000), "Original world is ready")
	var building := find_entrance(world)
	check(building != null, "Production exterior exists")
	if building == null:
		quit(1)
		return
	var manager := world.get_node("PoiInstances") as PoiInstanceManager
	if not building.has_meta("poi_id"): manager.register_entrance(building, 42)
	var identity: String = str(building.get_meta("poi_id"))
	var seed_value: int = int(building.get_meta("poi_seed"))
	var player: CharacterBody3D = world.get_node("Player")
	await manager.enter(player, building, identity, seed_value)
	check(manager.interior != null and not manager.busy, "Production manager enters generated bunker")
	if manager.interior == null:
		quit(1)
		return
	var inside := manager.interior
	freeze_enemies(inside)
	var cargo_id: String = inside.content.get("cargo_id", "")
	var cargo := find_cargo(inside, cargo_id)
	check(not cargo_id.is_empty() and cargo != null, "Generated upgraded engine exists")
	if cargo == null:
		quit(1)
		return
	var expected_health: float = EngineState.definition_for("upgraded").max_health * 0.7
	check(cargo.engine.model_id == "upgraded" and is_equal_approx(cargo.engine.health, expected_health), "Generated cargo starts at 70% upgraded-engine health")
	var cache: BunkerCache = inside.caches[0]
	player.global_position = cache.global_position + Vector3(0, 0, 1.5)
	cache.interact_hold(player)
	check(cache.searched and cache.remaining.size() == 1, "Search consumes one cache item")
	# The long traversal is covered by bunker_replay; this test isolates extraction.
	player.global_position = cargo.global_position + Vector3(0, -0.4, 1.5)
	cargo.interact(player)
	await frames(2)
	var item := carried_engine(player, cargo_id)
	check(not item.is_empty() and item.scene_path == "res://props/engine_upgraded.tscn" and is_equal_approx(float(item.state.engine.health), expected_health), "Player carries generated engine with original identity and durability")
	var exit_door := inside.exit_door
	player.global_position = exit_door.global_position + exit_door.global_basis.z * 1.55 + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	player.look_at(Vector3(exit_door.global_position.x, player.global_position.y, exit_door.global_position.z))
	player.camera.look_at(exit_door.global_position + Vector3.UP * 1.4)
	await frames(6)
	var ray: RayCast3D = player.camera.get_node("InteractRay")
	ray.force_raycast_update()
	check(ray.get_collider() == exit_door, "Player interaction ray targets the bunker exit")
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	var deadline := Time.get_ticks_msec() + 60000
	while (manager.busy or manager.interior != null) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(manager.interior == null and manager.active_id.is_empty() and not manager.busy, "E on exit transfers player outdoors")
	if manager.interior != null:
		quit(1)
		return
	check(WorldEntities.same_world(player, world), "Player returns to outdoor World3D")
	item = carried_engine(player, cargo_id)
	check(not item.is_empty() and is_equal_approx(float(item.state.engine.health), expected_health), "Extracted engine keeps identity and 70% health outdoors")
	var saved_poi: Dictionary = manager.saved_instances.get(identity, {})
	check(saved_poi.get("content", {}).get("cargo_id", "") == cargo_id and not saved_poi.get("actors", []).any(func(actor): return actor.get("state", {}).get("engine", {}).get("id", "") == cargo_id), "Exited bunker records cargo as removed from world")
	check(saved_poi.get("caches", []).size() > 0 and saved_poi.caches[0].searched and saved_poi.caches[0].remaining.size() == 1, "Exited bunker records searched cache")
	var checkpoint := root.get_node("Checkpoint")
	check(checkpoint.save_world(world, SAVE_PATH), "Disk checkpoint saves extracted cargo")
	var disk: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	check(not disk.is_empty() and disk.poi.get(identity, {}) == saved_poi, "Disk checkpoint preserves exact bunker state")
	check(await checkpoint.load_world(world, SAVE_PATH), "Checkpoint loads into a fresh production world")
	world = current_scene as Node3D
	await frames(2)
	manager = world.get_node("PoiInstances") as PoiInstanceManager
	player = world.get_node("Player")
	item = carried_engine(player, cargo_id)
	check(not item.is_empty() and is_equal_approx(float(item.state.engine.health), expected_health), "Fresh world restores extracted engine in player inventory")
	check(manager.saved_instances.get(identity, {}) == saved_poi, "Fresh manager restores bunker manifest, caches and actors")
	# Use the real service bay path to prove the reward works as an RV engine.
	var rv: Chassis = get_first_node_in_group(Groups.CHASSIS)
	check(rv != null, "Checkpoint restores an RV")
	if rv == null:
		quit(1)
		return
	rv.freeze = true
	rv.set_physics_process(false)
	rv.set_engine_running(false)
	rv.set_handbrake(true)
	rv.engine_bay.get_node("Hatch").set_open(true)
	for slot in player.inventory.items.size():
		if player.inventory.items[slot].get("state", {}).get("engine", {}).get("id", "") == cargo_id:
			player._set_active_slot(slot)
			break
	var installed_message: String = rv.engine_bay.interact(player)
	check(rv.get_engine() != null and rv.get_engine().id == cargo_id and is_equal_approx(rv.get_engine().health, expected_health), "RV service bay installs the extracted upgraded engine: " + installed_message)
	check(rv.set_engine_running(true), "Installed upgraded engine starts the RV")
	var restored_building := find_entrance(world, identity)
	check(restored_building != null, "Original bunker entrance exists after disk load")
	if restored_building == null:
		quit(1)
		return
	await manager.enter(player, restored_building, identity, seed_value)
	check(manager.interior != null and not manager.busy, "Manager reenters saved bunker in fresh world")
	if manager.interior != null:
		freeze_enemies(manager.interior)
		check(manager.interior.content.get("cargo_id", "") == cargo_id and find_cargo(manager.interior, cargo_id) == null, "Reentered bunker retains objective without respawning extracted engine")
		check(manager.interior.caches.size() == saved_poi.caches.size() and manager.interior.caches[0].capture_state() == saved_poi.caches[0], "Reentered cache remains partially searched with exact remaining stock")
		check(rv.get_engine().id == cargo_id, "Installed reward remains owned by RV during reentry")
	if failures.is_empty(): print("PASS: generated engine extraction through E exit, RV install/use, disk load, reentry without cargo duplication or cache restock")
	quit(0 if failures.is_empty() else 1)
