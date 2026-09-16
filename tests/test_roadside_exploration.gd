extends SceneTree
var failures: Array[String] = []
func _init() -> void:
	_run.call_deferred()
func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
func check(okay: bool, message: String) -> void:
	if not okay:
		failures.append(message)
		push_error("FAIL: " + message)
func _run() -> void:
	var main: Node3D = load("res://world/test_world.tscn").instantiate()
	main.get_node("WorldGenerator").world_seed = 42
	# Legacy near-road layout remains supported by old checkpoints.
	main.get_node("WorldGenerator").profile = WorldProfile.new()
	main.get_node("WorldGenerator").profile.generation_version = 2
	root.add_child(main)
	current_scene = main
	for enemy in get_nodes_in_group(Groups.MONSTERS):
		enemy.queue_free()
	var field: WorldField = main.get_node("WorldGenerator").field
	var site := field.stop(1)
	var player = main.get_node("Player")
	player.global_position = site.frame.origin + Vector3.UP * 0.3
	player.velocity = Vector3.ZERO
	await _frames(60)
	var loot: Prop
	for actor in main.get_node("WorldEntities").get_children():
		if actor is Prop and actor.global_position.distance_to(site.building.origin) < 12:
			loot = actor
			break
	check(loot != null, "Small roadside stop contains physical loot")
	if loot != null:
		var aim: Vector3 = loot.global_position + site.building.basis.z * 1.1
		for i in range(480):
			var delta := Vector2(player.global_position.x - aim.x, player.global_position.z - aim.z)
			if delta.length() < 0.35:
				break
			player.look_at(Vector3(aim.x, player.global_position.y, aim.z))
			Input.action_press("move_forward")
			await physics_frame
		Input.action_release("move_forward")
		check(Vector2(player.global_position.x - aim.x, player.global_position.z - aim.z).length() < 0.6, "Walk from parking court to loot")
		player.camera.look_at(loot.global_position)
		await _frames(10)
		var before: int = player.inventory.items.size()
		Input.action_press("interact")
		await _frames(12)
		Input.action_release("interact")
		check(player.inventory.items.size() == before + 1, "Real E interaction picks up roadside supplies")
		var back: Vector3 = site.frame.origin
		player.camera.rotation = Vector3.ZERO
		for i in range(480):
			if Vector2(player.global_position.x - back.x, player.global_position.z - back.z).length() < 0.4:
				break
			player.look_at(Vector3(back.x, player.global_position.y, back.z))
			Input.action_press("move_forward")
			await physics_frame
		Input.action_release("move_forward")
		check(Vector2(player.global_position.x - back.x, player.global_position.z - back.z).length() < 0.6, "Return on foot to parking court")
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: roadside parking-to-loot walk, E pickup, and return")
	quit(0 if failures.is_empty() else 1)
