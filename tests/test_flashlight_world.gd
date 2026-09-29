extends SceneTree
## Production-world flashlight pickup and disk checkpoint ownership round trips.

const SAVE_PATH := "res://.godot/test-flashlight-world.save"
const FLASHLIGHT_SCENE := "res://props/flashlight.tscn"
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error("FAIL: " + detail)

func frames(count: int) -> void:
	for i in count: await physics_frame

func ground_flashlights(world: Node) -> Array[Flashlight]:
	var found: Array[Flashlight] = []
	for node in world.get_children():
		if node is Flashlight and not node.is_queued_for_deletion(): found.append(node)
	for node in world.get_node("WorldEntities").get_children():
		if node is Flashlight and not node.is_queued_for_deletion(): found.append(node)
	return found

func carried_flashlights(player: Node) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Dictionary in player.inventory.items:
		if item.get("scene_path", "") == FLASHLIGHT_SCENE: found.append(item)
	return found

func quiet_world(world: Node3D) -> void:
	for actor in get_nodes_in_group(Groups.CHASSIS):
		if WorldEntities.same_world(actor, world):
			actor.set_engine_running(false)
			actor.set_handbrake(true)
			actor.freeze = true
			actor.set_physics_process(false)
	for actor in get_nodes_in_group(Groups.MONSTERS):
		if WorldEntities.same_world(actor, world): actor.process_mode = Node.PROCESS_MODE_DISABLED

func _run() -> void:
	var world: Node3D = load("res://world/test_world.tscn").instantiate()
	world.get_node("WorldGenerator").world_seed = 42
	root.add_child(world)
	current_scene = world
	check(await world.wait_for_play(60000), "Production world becomes ready")
	if not world.play_ready:
		quit(1)
		return
	quiet_world(world)
	var player: CharacterBody3D = world.get_node("Player")
	player.set_physics_process(false)
	var loose: Flashlight = world.get_node("Flashlight")
	check(ground_flashlights(world).size() == 1 and carried_flashlights(player).is_empty(), "Fresh world has one ground flashlight and no inventory grant")
	await frames(120)
	check(loose.global_position.distance_to(Vector3(0, 0.15, 3)) < 0.65 and loose.linear_velocity.length() < 0.25, "Default flashlight settles on production ground near (0, 0, 3)")
	var identity := loose.persistent_id
	player.global_position = loose.global_position + Vector3(0, 0, 1.9)
	player.velocity = Vector3.ZERO
	player.camera.look_at(loose.global_position)
	await frames(3)
	var ray: RayCast3D = player.camera.get_node("InteractRay")
	ray.force_raycast_update()
	check(ray.get_collider() == loose, "Unobstructed player interaction ray reaches settled flashlight")
	if ray.get_collider() != loose:
		quit(1)
		return
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(2)
	check(ground_flashlights(world).is_empty() and carried_flashlights(player).size() == 1, "E picks up default flashlight exactly once")
	if carried_flashlights(player).size() != 1:
		quit(1)
		return
	check(carried_flashlights(player)[0].state.id == identity, "E pickup preserves original world identity")
	player._toggle_flashlight()
	player._advance_flashlight(90.0)
	player._toggle_flashlight()
	var charge := float(carried_flashlights(player)[0].state.flashlight.charge)
	check(charge > 69.0 and charge < 71.0, "Illuminated usage lowers carried charge to about 70 percent")
	var checkpoint := root.get_node("Checkpoint")
	check(checkpoint.save_world(world, SAVE_PATH), "Disk checkpoint saves carried flashlight")
	var disk: Dictionary = checkpoint.read_checkpoint(SAVE_PATH)
	check(not disk.is_empty() and disk.player.items.size() == 1 and not disk.actors.any(func(actor): return actor.get("scene", "") == FLASHLIGHT_SCENE), "Saved checkpoint owns flashlight only in inventory")
	check(await checkpoint.load_world(world, SAVE_PATH), "Disk checkpoint loads into fresh production world")
	world = current_scene as Node3D
	player = world.get_node("Player")
	quiet_world(world)
	player.set_physics_process(false)
	check(ground_flashlights(world).is_empty() and carried_flashlights(player).size() == 1, "Fresh world restores one carried flashlight and suppresses default ground spawn")
	if carried_flashlights(player).size() != 1:
		quit(1)
		return
	check(carried_flashlights(player)[0].state.id == identity and is_equal_approx(float(carried_flashlights(player)[0].state.flashlight.charge), charge), "Fresh inventory retains identity and partial charge")
	player.drop_item()
	await frames(2)
	var dropped := ground_flashlights(world)
	check(dropped.size() == 1 and carried_flashlights(player).is_empty(), "Drop moves flashlight to loose world actors exactly once")
	if dropped.size() != 1:
		quit(1)
		return
	dropped[0].freeze = true
	dropped[0].global_position = Vector3(10, 1, 8)
	check(checkpoint.save_world(world, SAVE_PATH), "Disk checkpoint saves moved loose flashlight")
	disk = checkpoint.read_checkpoint(SAVE_PATH)
	check(not disk.is_empty() and disk.player.items.is_empty() and disk.actors.filter(func(actor): return actor.get("scene", "") == FLASHLIGHT_SCENE).size() == 1, "Saved checkpoint owns flashlight only as loose actor")
	check(await checkpoint.load_world(world, SAVE_PATH), "Loose flashlight checkpoint loads into fresh production world")
	world = current_scene as Node3D
	player = world.get_node("Player")
	dropped = ground_flashlights(world)
	check(dropped.size() == 1 and carried_flashlights(player).is_empty(), "Fresh world has one loose flashlight and no inventory duplicate")
	if dropped.size() == 1:
		check(dropped[0].persistent_id == identity and is_equal_approx(dropped[0].charge, charge) and dropped[0].global_position.distance_to(Vector3(10, 1, 8)) < 0.5, "Loose restore retains identity, charge, and moved position")
	# Simulate an older checkpoint whose actor list never contained a flashlight.
	var legacy: Dictionary = disk.duplicate(true)
	legacy.actors = legacy.actors.filter(func(actor): return actor.get("scene", "") != FLASHLIGHT_SCENE)
	check(checkpoint.write_checkpoint(SAVE_PATH, legacy), "Older checkpoint fixture writes without flashlight actor")
	check(await checkpoint.load_world(world, SAVE_PATH), "Older checkpoint loads into fresh production world")
	world = current_scene as Node3D
	player = world.get_node("Player")
	check(ground_flashlights(world).is_empty() and carried_flashlights(player).is_empty(), "Older checkpoint omitting flashlight does not grant or respawn it")
	Input.action_release("interact")
	if failures.is_empty(): print("PASS: production flashlight E pickup, ground settling, inventory/loose disk round trips, and old-save omission")
	quit(0 if failures.is_empty() else 1)
