extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(okay: bool, message: String) -> void:
	if not okay: failures.append(message)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var player: CharacterBody3D = load("res://player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(0, 0, 1.5)
	var first := _entry("res://props/scrap.tscn", "cache-scrap-a", 23.0)
	var second := _entry("res://props/scrap.tscn", "cache-scrap-b", 71.0)
	var cache: BunkerCache = load("res://world/instances/bunker_cache.tscn").instantiate()
	cache.cache_id = "cache-test"
	cache.remaining.assign([first, second])
	world.add_child(cache)
	await physics_frame
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 2, 0), Vector3(0, 0.1, 0))
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(hit.get("collider") == cache, "Real physics ray can target the cache for interaction")
	check(cache.get_node("Visuals/LidPivot") is Node3D, "Cache has separate visuals")
	check(cache.get_interaction_prompt(player).contains("長按 E"), "Prompt describes hold interaction")
	for i in PlayerInventory.MAX_SLOTS:
		check(player.add_item("placeholder", false, "res://props/scrap.tscn"), "Fill inventory slot %d" % i)
	check(cache.interact_hold(player).contains("背包已滿"), "Full inventory rejects transfer")
	check(cache.remaining.size() == 2 and not cache.searched, "Rejected transfer retains stock and closed state")
	player.inventory.items.clear()
	player.refresh_inventory()
	check(cache.interact_hold(player).contains("已取得"), "First hold transfers a prop")
	check(player.inventory.items.size() == 1 and cache.remaining.size() == 1, "One hold transfers exactly one prop")
	check(player.inventory.items[0].state.id == "cache-scrap-a" and is_equal_approx(player.inventory.items[0].state.condition, 23.0), "First prop identity and condition survive transfer")
	var captured: Dictionary = cache.capture_state()
	check(captured.id == "cache-test" and captured.searched and captured.remaining.size() == 1, "Snapshot captures opened cache and stock")
	var restored: BunkerCache = load("res://world/instances/bunker_cache.tscn").instantiate()
	world.add_child(restored)
	restored.restore_state(captured)
	check(restored.cache_id == cache.cache_id and restored.searched and restored.remaining == cache.remaining, "Restore retains cache identity and remaining prop")
	check(restored.get_node("Visuals/LidPivot").rotation.x < -1.0 and restored.get_node("Visuals/Status").text == "OPEN", "Restore updates opened visual")
	check(restored.interact_hold(player).contains("已取得"), "Second hold transfers restored prop")
	check(restored.remaining.is_empty() and player.inventory.items.size() == 2, "Restored prop is consumed once")
	check(player.inventory.items[1].state.id == "cache-scrap-b" and is_equal_approx(player.inventory.items[1].state.condition, 71.0), "Second prop state survives transfer")
	check(restored.get_node("Visuals/Status").text == "EMPTY", "Empty searched cache shows empty visual")
	check(restored.interact_hold(player).contains("搜空") and player.inventory.items.size() == 2, "Repeated hold cannot duplicate loot")
	player.position = Vector3(10, 0, 0)
	check(cache.interact_hold(player).contains("無法"), "Remote player cannot search")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: bunker cache transfer, full inventory, repeat hold, state restore")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _entry(scene_path: String, id: String, condition: float) -> Dictionary:
	var prop: Prop = load(scene_path).instantiate()
	prop.persistent_id = id
	prop.condition = condition
	var data := {"scene": scene_path, "state": prop.capture_item_state(), "name": prop.item_name, "large": prop.is_large}
	prop.free()
	return data
