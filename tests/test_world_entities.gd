extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var chunk := Node3D.new()
	world.add_child(chunk)
	var static_content := Node3D.new()
	chunk.add_child(static_content)
	var container := WorldEntities.get_container(chunk)
	var active_entity := Node3D.new()
	container.add_child(active_entity)
	chunk.queue_free()
	await process_frame
	var survived := is_instance_valid(active_entity) and not is_instance_valid(static_content)
	var reused := WorldEntities.get_container(world) == container
	world.free()
	var next_world := Node3D.new()
	root.add_child(next_world)
	current_scene = next_world
	var next_container := WorldEntities.get_container(next_world)
	var recreated := is_instance_valid(next_container) and next_container.get_parent() == next_world
	next_world.free()
	if survived and reused and recreated:
		print("PASS: world entity ownership survives chunk unload and resets after scene free")
		quit(0)
	else:
		push_error("World entity ownership failed: survival=%s reuse=%s recreation=%s" % [survived, reused, recreated])
		quit(1)
