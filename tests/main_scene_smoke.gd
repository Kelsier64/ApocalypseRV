extends SceneTree
## Production scene, terrain, navigation and player must all become usable.
func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var world: Node3D = load("res://world/test_world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	if await world.wait_for_play(0):
		push_error("FAIL: world reported ready before navigation synchronization")
		quit(1)
		return
	if not await world.wait_for_play(60000):
		push_error("FAIL: world.ready_for_play timed out")
		quit(1)
		return
	var player: CharacterBody3D = world.get_node("Player")
	var before := player.global_position
	Input.action_press("move_forward")
	for i in range(30): await physics_frame
	Input.action_release("move_forward")
	var travelled := Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
	if not player.global_transform.is_finite() or travelled < 0.1:
		push_error("FAIL: ready player cannot move")
		quit(1)
		return
	print("PASS: WORLD_READY_FOR_PLAY and production player movement")
	world.free()
	quit(0)
