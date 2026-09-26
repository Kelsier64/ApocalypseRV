extends SceneTree
func _init() -> void: run.call_deferred()
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	for version in [5, 6]:
		var profile := WorldProfile.new()
		profile.generation_version = version
		var field := WorldField.new(0, profile)
		for band in [4, 5, 6]:
			var chunk := ChunkGenerator.new()
			chunk.set_meta("skip_actors", true)
			chunk.set_meta("skip_walk_in", true)
			world.add_child(chunk)
			await chunk.generate(field, band, POISpawner.new(), true)
			while not chunk.navigation_ready: await physics_frame
			print("MINOR_STREAM version=%d band=%d build_ms=%.1f max_slice_ms=%.1f" % [version, band, chunk.build_ms, chunk.max_slice_ms])
			chunk.free()
	world.free()
	quit()
