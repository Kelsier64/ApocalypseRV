extends SceneTree
## CPU generation benchmark; headless results do not measure GPU frame rate.
func _init() -> void:
	run.call_deferred()

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var field := WorldField.new(42)
	for band in [0, 3]:
		var chunk := ChunkGenerator.new()
		chunk.set_meta("skip_actors", true)
		world.add_child(chunk)
		var start := Time.get_ticks_usec()
		await chunk.generate(field, band, POISpawner.new(), true)
		print("BENCH band=%d cpu_ms=%.2f max_slice_ms=%.2f wall_ms=%.2f" % [band, chunk.build_ms, chunk.max_slice_ms, (Time.get_ticks_usec() - start) / 1000.0])
		while NavigationServer3D.is_baking_navigation_mesh(chunk.navigation.navigation_mesh):
			await process_frame
		chunk.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	quit()
